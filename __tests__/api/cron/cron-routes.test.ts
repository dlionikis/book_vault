/**
 * Auth-guard tests for the internal cron routes. The job logic itself is
 * covered in lib/*.test.ts; here we only assert the CRON_SECRET gate and that
 * an authorized call invokes the job.
 */

import { NextRequest } from 'next/server';

jest.mock('@/lib/sync-availability', () => ({ syncAvailability: jest.fn() }));
jest.mock('@/lib/poll-restore-status', () => ({ pollRestoreStatus: jest.fn() }));

import { GET as syncRoute } from '@/app/api/cron/sync-availability/route';
import { GET as pollRoute } from '@/app/api/cron/poll-restores/route';
import { syncAvailability } from '@/lib/sync-availability';
import { pollRestoreStatus } from '@/lib/poll-restore-status';

const mockSync = syncAvailability as jest.MockedFunction<typeof syncAvailability>;
const mockPoll = pollRestoreStatus as jest.MockedFunction<typeof pollRestoreStatus>;

const OLD_ENV = process.env.CRON_SECRET;
beforeEach(() => {
  jest.clearAllMocks();
  process.env.CRON_SECRET = 'test-cron-secret';
  mockSync.mockResolvedValue({
    checked: 0,
    available: 0,
    archived: 0,
    restoring: 0,
    errors: 0,
    changed: 0,
  });
  mockPoll.mockResolvedValue({
    checked: 0,
    completed: 0,
    stillRestoring: 0,
    failed: 0,
    errors: 0,
  });
});
afterAll(() => {
  process.env.CRON_SECRET = OLD_ENV;
});

const req = (auth?: string) =>
  new NextRequest(
    'http://localhost:3000/api/cron/x',
    auth ? { headers: { authorization: auth } } : {}
  );

describe.each([
  ['sync-availability', syncRoute, () => mockSync],
  ['poll-restores', pollRoute, () => mockPoll],
] as const)('GET /api/cron/%s', (_name, route, getMock) => {
  it('401s with no Authorization header', async () => {
    const res = await route(req());
    expect(res.status).toBe(401);
    expect(getMock()).not.toHaveBeenCalled();
  });

  it('401s with a wrong secret', async () => {
    const res = await route(req('Bearer nope'));
    expect(res.status).toBe(401);
    expect(getMock()).not.toHaveBeenCalled();
  });

  it('runs the job with the correct secret', async () => {
    const res = await route(req('Bearer test-cron-secret'));
    expect(res.status).toBe(200);
    expect(getMock()).toHaveBeenCalledTimes(1);
    const body = await res.json();
    expect(body.success).toBe(true);
    expect(body).toHaveProperty('result');
  });

  it('fails closed when CRON_SECRET is unset', async () => {
    delete process.env.CRON_SECRET;
    const res = await route(req('Bearer test-cron-secret'));
    expect(res.status).toBe(401);
    expect(getMock()).not.toHaveBeenCalled();
  });
});
