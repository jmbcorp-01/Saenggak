import type { ExecuteStatementCommand, Field, SqlParameter } from '@aws-sdk/client-rds-data';
import type pg from 'pg';

/**
 * Runs RDS Data API statements on a plain Postgres connection, for tests.
 * Parameters are typed the way the Data API sends them (strings as varchar,
 * longs as bigint, nulls untyped), so SQL that needs a cast fails here too.
 */
export class PgDataApi {
  constructor(private readonly client: pg.Client) {}

  async send(cmd: ExecuteStatementCommand) {
    const input = cmd.input;
    const params = input.parameters ?? [];
    const values: unknown[] = [];
    const sql = (input.sql ?? '').replace(/(?<![:\w]):([a-zA-Z_]\w*)/g, (_m, name: string) => {
      const p = params.find((x) => x.name === name);
      if (!p) throw new Error(`missing parameter ${name}`);
      values.push(valueOf(p));
      return `$${values.length}${castOf(p)}`;
    });
    const res = await this.client.query({ text: sql, values, rowMode: 'array' });
    return {
      columnMetadata: res.fields.map((f) => ({ name: f.name })),
      records: (res.rows as unknown[][]).map((row) => row.map(toField)),
    };
  }
}

function valueOf(p: SqlParameter): unknown {
  const v = p.value!;
  if (v.isNull) return null;
  return v.stringValue ?? v.longValue ?? v.doubleValue ?? v.booleanValue ?? null;
}

function castOf(p: SqlParameter): string {
  const v = p.value!;
  if (v.isNull) return '';
  if (v.stringValue !== undefined) return '::varchar';
  if (v.longValue !== undefined) return '::bigint';
  if (v.doubleValue !== undefined) return '::float8';
  return '::boolean';
}

function toField(v: unknown): Field {
  if (v === null || v === undefined) return { isNull: true };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { longValue: v } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  return { stringValue: v instanceof Date ? v.toISOString() : JSON.stringify(v) };
}
