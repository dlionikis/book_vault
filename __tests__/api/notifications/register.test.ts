import { NextRequest } from 'next/server';

jest.mock('next-auth');
jest.mock('@/lib/auth');
jest.mock('@/lib/db', () => ({
  prisma: { userDeviceToken: { upsert: jest.fn(), updateMany: jest.fn() } },
}));
jest.mock('@/lib/notification-service', () => ({
  NotificationService: { registerEndpoint: jest.fn() },
}));

import { POST, DELETE } from '@/app/api/notifications/register/route';
import { getServerSession } from 'next-auth';
import { getAuthUserFromRequest } from '@/lib/auth';
import { prisma } from '@/lib/db';
import { NotificationService } from '@/lib/notification-service';

const mockSession = getServerSession as jest.MockedFunction<typeof getServerSession>;
const mockBearer = getAuthUserFromRequest as jest.MockedFunction<typeof getAuthUserFromRequest>;
const mockRegisterEndpoint = NotificationService.registerEndpoint as jest.Mock;

function req(method: string, body?: unknown) {
  return new NextRequest('http://localhost:3000/api/notifications/register', {
    method,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  mockSession.mockResolvedValue(null);
  mockBearer.mockResolvedValue({ id: 'user-1', username: 'u' });
  (prisma.userDeviceToken.upsert as jest.Mock).mockResolvedValue({});
  (prisma.userDeviceToken.updateMany as jest.Mock).mockResolvedValue({ count: 1 });
  mockRegisterEndpoint.mockResolvedValue('arn:endpoint:1');
});

describe('POST /api/notifications/register', () => {
  it('401 when unauthenticated', async () => {
    mockBearer.mockResolvedValue(null);
    expect((await POST(req('POST', { deviceToken: 't' }))).status).toBe(401);
  });

  it('400 when deviceToken missing', async () => {
    const res = await POST(req('POST', { platform: 'ios' }));
    expect(res.status).toBe(400);
    expect(prisma.userDeviceToken.upsert).not.toHaveBeenCalled();
  });

  it('registers the SNS endpoint and upserts the token', async () => {
    const res = await POST(req('POST', { deviceToken: 'abc123', platform: 'ios' }));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ success: true });
    expect(mockRegisterEndpoint).toHaveBeenCalledWith('abc123', 'ios');
    expect(prisma.userDeviceToken.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { userId_deviceToken: { userId: 'user-1', deviceToken: 'abc123' } },
        create: expect.objectContaining({ snsEndpointArn: 'arn:endpoint:1', isActive: true }),
        update: { snsEndpointArn: 'arn:endpoint:1', isActive: true },
      })
    );
  });

  it('still persists the token when push is unconfigured (endpoint arn null)', async () => {
    mockRegisterEndpoint.mockResolvedValue(null);
    const res = await POST(req('POST', { deviceToken: 'abc123' }));
    expect(res.status).toBe(200);
    expect(prisma.userDeviceToken.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ update: { snsEndpointArn: null, isActive: true } })
    );
  });
});

describe('DELETE /api/notifications/register', () => {
  it('401 when unauthenticated', async () => {
    mockBearer.mockResolvedValue(null);
    expect((await DELETE(req('DELETE', { deviceToken: 't' }))).status).toBe(401);
  });

  it('400 when deviceToken missing', async () => {
    expect((await DELETE(req('DELETE', {}))).status).toBe(400);
  });

  it('deactivates the token', async () => {
    const res = await DELETE(req('DELETE', { deviceToken: 'abc123' }));
    expect(res.status).toBe(200);
    expect(prisma.userDeviceToken.updateMany).toHaveBeenCalledWith({
      where: { userId: 'user-1', deviceToken: 'abc123' },
      data: { isActive: false },
    });
  });
});
