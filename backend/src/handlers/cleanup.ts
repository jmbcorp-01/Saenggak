import { AuroraRepository } from '../services/repository.js';

/** Retention promised in the privacy policy. Runs once a day. */
export const CLEANUP_SQL = [
  // Only the last hour matters for the write limit.
  `DELETE FROM write_log WHERE at < now() - interval '1 day'`,
  `DELETE FROM admin_actions WHERE at < now() - interval '1 year'`,
  `DELETE FROM reports WHERE resolved_at < now() - interval '1 year'`,
];

class Cleaner extends AuroraRepository {
  async run(): Promise<void> {
    for (const sql of CLEANUP_SQL) await this.query(sql);
  }
}

export async function handler(): Promise<{ ok: true }> {
  await new Cleaner().run();
  return { ok: true };
}
