/**
 * Push-notification service (AWS SNS → APNs).
 *
 * Registers device tokens as SNS platform endpoints and publishes push
 * notifications (currently: "your restored audiobook is ready"). Called by the
 * restore poller (lib/poll-restore-status.ts) via a guarded dynamic import, and
 * by the device-token registration route.
 *
 * The SNS platform application ARNs are provided via env (created out-of-band —
 * see docs/plans/s3-archive-restore-workflow-v2.md Phase 6.1). When they're
 * absent (e.g. before the AWS setup, or in dev), this service degrades to a
 * logged no-op rather than throwing, so the rest of the app is unaffected.
 */

import {
  SNSClient,
  PublishCommand,
  CreatePlatformEndpointCommand,
  SetEndpointAttributesCommand,
} from '@aws-sdk/client-sns';
import { prisma } from './db';
import { logger } from './logger';

const REGION = process.env.AWS_REGION || 'us-east-1';

let snsClient: SNSClient | null = null;
function getSnsClient(): SNSClient {
  if (!snsClient) snsClient = new SNSClient({ region: REGION });
  return snsClient;
}

/**
 * The APNs platform application ARN. Production builds use the APNS app;
 * everything else uses APNS_SANDBOX (debug/TestFlight-sandbox device tokens).
 */
function platformApplicationArn(): string | undefined {
  return process.env.NODE_ENV === 'production'
    ? process.env.AWS_SNS_PLATFORM_APPLICATION_ARN
    : process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;
}

export function isPushEnabled(): boolean {
  return Boolean(platformApplicationArn());
}

export class NotificationService {
  /**
   * Create or recover the SNS platform endpoint for a device token, returning
   * its ARN.
   *
   * CreatePlatformEndpoint is only idempotent when the token's attributes match
   * what SNS already has. If the token exists with different attributes SNS
   * throws InvalidParameter with the existing ARN embedded in the message —
   * recover it. Then SetEndpointAttributes ensures the endpoint carries the
   * current token and is enabled (APNs feedback can disable endpoints).
   */
  static async registerEndpoint(deviceToken: string, _platform: string): Promise<string | null> {
    const appArn = platformApplicationArn();
    if (!appArn) {
      logger.info('Push not configured (no SNS platform ARN) — skipping endpoint registration');
      return null;
    }

    const client = getSnsClient();
    let endpointArn: string;
    try {
      const result = await client.send(
        new CreatePlatformEndpointCommand({
          PlatformApplicationArn: appArn,
          Token: deviceToken,
        })
      );
      endpointArn = result.EndpointArn!;
    } catch (error) {
      const message = (error as { message?: string }).message ?? '';
      const match = /Endpoint (arn:aws:sns:\S+) already exists/.exec(message);
      if ((error as { name?: string }).name === 'InvalidParameterException' && match) {
        endpointArn = match[1];
      } else {
        throw error;
      }
    }

    // Ensure the endpoint is enabled and carries the current token.
    await client.send(
      new SetEndpointAttributesCommand({
        EndpointArn: endpointArn,
        Attributes: { Token: deviceToken, Enabled: 'true' },
      })
    );

    return endpointArn;
  }

  /**
   * Send a push notification to a user's active devices when a book restore
   * completes. Best-effort: a disabled endpoint (APNs feedback) is marked
   * inactive; other per-device failures are logged and skipped, never thrown.
   */
  static async sendRestoreComplete(
    userId: string,
    bookId: string,
    bookTitle: string
  ): Promise<void> {
    if (!isPushEnabled()) {
      logger.info('Push not configured — skipping restore-complete notification', { bookId });
      return;
    }

    const tokens = await prisma.userDeviceToken.findMany({
      where: { userId, isActive: true },
    });
    if (tokens.length === 0) {
      logger.info('No active device tokens for user — skipping notification', { userId, bookId });
      return;
    }

    const payload = {
      aps: {
        alert: {
          title: 'Audiobook Ready',
          body: `"${bookTitle}" has been restored and is ready to play.`,
        },
        sound: 'default',
        badge: 1,
      },
      bookId,
      action: 'restore_complete',
    };
    const message = JSON.stringify({
      default: `${bookTitle} is ready to play`,
      APNS: JSON.stringify(payload),
      APNS_SANDBOX: JSON.stringify(payload),
    });

    const client = getSnsClient();
    for (const token of tokens) {
      if (!token.snsEndpointArn) continue;
      try {
        await client.send(
          new PublishCommand({
            TargetArn: token.snsEndpointArn,
            Message: message,
            MessageStructure: 'json',
          })
        );
        logger.info('Push sent', { userId, bookId });
      } catch (error) {
        if ((error as { name?: string }).name === 'EndpointDisabledException') {
          await prisma.userDeviceToken.update({
            where: { id: token.id },
            data: { isActive: false },
          });
          logger.info('Disabled stale SNS endpoint', { userId, tokenId: token.id });
        } else {
          logger.error('Failed to send push', {
            userId,
            endpoint: token.snsEndpointArn,
            error: String(error),
          });
        }
      }
    }
  }
}
