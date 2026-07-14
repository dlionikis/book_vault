import net from 'net';
import { seedE2E } from '../scripts/seed-e2e';

/**
 * Playwright global setup: run once before the dev server starts and before any
 * test. Ensures the local stack the smoke depends on is actually up, then seeds
 * deterministic fixtures.
 *
 * Docker is intentionally NOT started here — if Postgres is down we fail fast
 * with an actionable message, matching the pattern scripts/validate.sh uses.
 */

// Host port docker-compose maps Postgres to (5433:5432). Overridable for CI,
// where the Postgres service typically listens on 5432.
const DB_PORT = Number(process.env.E2E_DB_PORT || 5433);
const DB_HOST = process.env.E2E_DB_HOST || '127.0.0.1';

function probeTcp(host: string, port: number, timeoutMs = 1500): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    const done = (ok: boolean) => {
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
    socket.connect(port, host);
  });
}

async function globalSetup(): Promise<void> {
  const dbUp = await probeTcp(DB_HOST, DB_PORT);
  if (!dbUp) {
    throw new Error(
      [
        '',
        `❌ Postgres is not reachable at ${DB_HOST}:${DB_PORT}.`,
        '',
        '   The web smoke needs the local database running. Start it with:',
        '',
        '     docker-compose up -d',
        '',
        '   (Set E2E_DB_HOST / E2E_DB_PORT to point elsewhere, e.g. 5432 in CI.)',
        '',
      ].join('\n')
    );
  }

  console.log(`✓ Postgres reachable at ${DB_HOST}:${DB_PORT}`);
  await seedE2E();
}

export default globalSetup;
