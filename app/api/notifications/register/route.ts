import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { prisma } from '@/lib/db';
import { logger } from '@/lib/logger';
import { NotificationService } from '@/lib/notification-service';

/**
 * POST /api/notifications/register — register/refresh an APNs device token.
 * Creates (or recovers) an SNS platform endpoint and upserts the token row.
 *
 * Auth: Required. Idempotent per (user, deviceToken).
 */
export async function POST(request: NextRequest) {
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  let body: { deviceToken?: unknown; platform?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  const { deviceToken } = body;
  if (!deviceToken || typeof deviceToken !== 'string') {
    return NextResponse.json({ error: 'deviceToken is required' }, { status: 400 });
  }
  const platform = typeof body.platform === 'string' ? body.platform : 'ios';

  try {
    // Best-effort SNS endpoint; null when push isn't configured yet. We still
    // persist the token so it can be back-filled once push is enabled.
    const snsEndpointArn = await NotificationService.registerEndpoint(deviceToken, platform);

    await prisma.userDeviceToken.upsert({
      where: { userId_deviceToken: { userId: auth.user.id, deviceToken } },
      create: { userId: auth.user.id, deviceToken, platform, snsEndpointArn, isActive: true },
      update: { snsEndpointArn, isActive: true },
    });

    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error('Device token registration failed', { error: String(error) });
    return NextResponse.json({ error: 'Failed to register device token' }, { status: 500 });
  }
}

/**
 * DELETE /api/notifications/register — deactivate a device token (e.g. logout).
 * Auth: Required.
 */
export async function DELETE(request: NextRequest) {
  const auth = await requireUser(request);
  if (auth.error) return auth.error;

  let body: { deviceToken?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 });
  }

  const { deviceToken } = body;
  if (!deviceToken || typeof deviceToken !== 'string') {
    return NextResponse.json({ error: 'deviceToken is required' }, { status: 400 });
  }

  try {
    await prisma.userDeviceToken.updateMany({
      where: { userId: auth.user.id, deviceToken },
      data: { isActive: false },
    });
    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error('Device token unregistration failed', { error: String(error) });
    return NextResponse.json({ error: 'Failed to unregister device token' }, { status: 500 });
  }
}
