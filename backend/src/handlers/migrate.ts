import path from 'node:path';
import {
  BeginTransactionCommand,
  CommitTransactionCommand,
  ExecuteStatementCommand,
  RDSDataClient,
  RollbackTransactionCommand,
  type Field,
} from '@aws-sdk/client-rds-data';
import { loadMigrations, migrate, type MigrationDb } from '../db/migrate.js';

/**
 * Runs once after each deploy (a CDK trigger) and brings the database schema
 * up to date. The migration files are copied next to the bundle.
 */
export async function handler(): Promise<{ applied: string[] }> {
  const client = new RDSDataClient({});
  const target = {
    resourceArn: process.env.DB_CLUSTER_ARN!,
    secretArn: process.env.DB_SECRET_ARN!,
    database: process.env.DB_NAME ?? 'saenggak',
  };
  const value = (f: Field) => (f.isNull ? null : (f.stringValue ?? f.longValue ?? f.doubleValue ?? f.booleanValue));
  const db: MigrationDb = {
    begin: async () => (await retry(() => client.send(new BeginTransactionCommand(target)))).transactionId!,
    exec: async (sql, transactionId) => {
      const out = await retry(() => client.send(new ExecuteStatementCommand({ ...target, sql, transactionId })));
      return (out.records ?? []).map((row) => row.map(value));
    },
    commit: async (transactionId) => {
      await client.send(new CommitTransactionCommand({ ...target, transactionId }));
    },
    rollback: async (transactionId) => {
      await client.send(new RollbackTransactionCommand({ ...target, transactionId })).catch(() => undefined);
    },
  };
  const dir = path.join(process.env.LAMBDA_TASK_ROOT ?? '.', 'migrations');
  const applied = await migrate(db, loadMigrations(dir));
  console.log('migrations applied', applied);
  return { applied };
}

/** A paused or just-created database answers "resuming" for a few seconds. */
async function retry<T>(call: () => Promise<T>, attempts = 12): Promise<T> {
  for (let k = 1; ; k++) {
    try {
      return await call();
    } catch (e) {
      const name = (e as { name?: string }).name;
      if (k >= attempts || name !== 'DatabaseResumingException') throw e;
      await new Promise((r) => setTimeout(r, Math.min(10_000, 1000 * k)));
    }
  }
}
