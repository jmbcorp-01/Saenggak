import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

export interface Migration {
  /** File name without .sql, such as "001_initial". Applied in this order. */
  id: string;
  sql: string;
}

/** What the migrator needs from the database: plain statements inside one transaction. */
export interface MigrationDb {
  begin(): Promise<string>;
  exec(sql: string, tx?: string): Promise<unknown[][]>;
  commit(tx: string): Promise<void>;
  rollback(tx: string): Promise<void>;
}

/**
 * Splits a migration file into statements. The Data API runs one statement per
 * call. Comments are dropped; migrations must not put semicolons inside
 * strings or function bodies.
 */
export function splitStatements(sql: string): string[] {
  return sql
    .replace(/--.*$/gm, '')
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function loadMigrations(dir: string): Migration[] {
  return readdirSync(dir)
    .filter((f) => /^\d{3}_[\w-]+\.sql$/.test(f))
    .sort()
    .map((f) => ({ id: f.replace(/\.sql$/, ''), sql: readFileSync(path.join(dir, f), 'utf8') }));
}

/**
 * Applies the migrations not yet recorded in schema_migrations, each in its own
 * transaction, so a failed one leaves nothing half done. Returns the ids applied.
 */
export async function migrate(db: MigrationDb, migrations: Migration[]): Promise<string[]> {
  await db.exec(
    `CREATE TABLE IF NOT EXISTS schema_migrations (id text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`,
  );
  const done = new Set((await db.exec(`SELECT id FROM schema_migrations`)).map((r) => String(r[0])));
  const applied: string[] = [];
  for (const m of migrations) {
    if (done.has(m.id)) continue;
    const tx = await db.begin();
    try {
      for (const statement of splitStatements(m.sql)) await db.exec(statement, tx);
      await db.exec(`INSERT INTO schema_migrations (id) VALUES ('${m.id.replace(/'/g, "''")}')`, tx);
      await db.commit(tx);
    } catch (e) {
      await db.rollback(tx);
      throw new Error(`migration ${m.id} failed`, { cause: e });
    }
    applied.push(m.id);
  }
  return applied;
}
