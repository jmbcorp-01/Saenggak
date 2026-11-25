import { describe, expect, it } from 'vitest';
import { migrate, splitStatements, type MigrationDb } from '../src/db/migrate.js';

describe('migrations', () => {
  it('splits statements and drops comments', () => {
    expect(splitStatements(`-- note; with a semicolon\nCREATE TABLE a (x int);\n\nCREATE INDEX i ON a (x); -- tail`)).toEqual([
      'CREATE TABLE a (x int)',
      'CREATE INDEX i ON a (x)',
    ]);
  });

  it('applies only new migrations and rolls back a failed one', async () => {
    const log: string[] = [];
    const db: MigrationDb = {
      begin: async () => (log.push('begin'), 'tx'),
      exec: async (sql) => {
        log.push(sql);
        if (sql.startsWith('SELECT id')) return [['001_a']];
        if (sql === 'BROKEN') throw new Error('syntax');
        return [];
      },
      commit: async () => void log.push('commit'),
      rollback: async () => void log.push('rollback'),
    };
    const ms = [
      { id: '001_a', sql: 'ONE;' },
      { id: '002_b', sql: 'TWO;' },
    ];
    expect(await migrate(db, ms)).toEqual(['002_b']);
    expect(log).not.toContain('ONE');
    expect(log).toContain('TWO');

    await expect(migrate(db, [{ id: '003_c', sql: 'BROKEN;' }])).rejects.toThrow('migration 003_c failed');
    expect(log.at(-1)).toBe('rollback');
  });
});
