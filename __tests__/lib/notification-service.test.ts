/**
 * SDK-level tests for the SNS-backed NotificationService (aws-sdk-client-mock).
 * Pins the tricky bits: endpoint recovery on InvalidParameter, disabling stale
 * endpoints, and the no-op when push isn't configured.
 */

import {
  SNSClient,
  CreatePlatformEndpointCommand,
  SetEndpointAttributesCommand,
  PublishCommand,
} from '@aws-sdk/client-sns';
import { mockClient } from 'aws-sdk-client-mock';

jest.mock('@/lib/db', () => ({
  prisma: {
    userDeviceToken: { findMany: jest.fn(), update: jest.fn() },
  },
}));

import { NotificationService, isPushEnabled } from '@/lib/notification-service';
import { prisma } from '@/lib/db';

const snsMock = mockClient(SNSClient);

const APP_ARN = 'arn:aws:sns:us-east-1:123:app/APNS_SANDBOX/book-vault';
const OLD_ENV = { ...process.env };

beforeEach(() => {
  jest.clearAllMocks();
  snsMock.reset();
  // Jest runs with NODE_ENV=test (non-production), so the service uses the
  // SANDBOX ARN — set that one.
  process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX = APP_ARN;
  delete process.env.AWS_SNS_PLATFORM_APPLICATION_ARN;
  (prisma.userDeviceToken.update as jest.Mock).mockResolvedValue({});
});
afterAll(() => {
  process.env = OLD_ENV;
});

describe('isPushEnabled', () => {
  it('true when a platform ARN is configured, false otherwise', () => {
    expect(isPushEnabled()).toBe(true);
    delete process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;
    expect(isPushEnabled()).toBe(false);
  });
});

describe('registerEndpoint', () => {
  it('creates a new endpoint and enables it', async () => {
    snsMock.on(CreatePlatformEndpointCommand).resolves({ EndpointArn: 'arn:endpoint:new' });
    snsMock.on(SetEndpointAttributesCommand).resolves({});

    const arn = await NotificationService.registerEndpoint('tok-1', 'ios');

    expect(arn).toBe('arn:endpoint:new');
    const setCalls = snsMock.commandCalls(SetEndpointAttributesCommand);
    expect(setCalls[0].args[0].input.Attributes).toMatchObject({ Token: 'tok-1', Enabled: 'true' });
  });

  it('recovers the existing ARN when SNS says the token already exists', async () => {
    // Real SNS message shape: "...Endpoint <arn:aws:sns:...> already exists
    // with the same Token, but different attributes."
    const existing = 'arn:aws:sns:us-east-1:123:endpoint/APNS_SANDBOX/book-vault/abcd-1234';
    const err = Object.assign(
      new Error(`Invalid parameter: Token Reason: Endpoint ${existing} already exists with ...`),
      { name: 'InvalidParameterException' }
    );
    snsMock.on(CreatePlatformEndpointCommand).rejects(err);
    snsMock.on(SetEndpointAttributesCommand).resolves({});

    const arn = await NotificationService.registerEndpoint('tok-1', 'ios');

    expect(arn).toBe(existing);
    // Recovered endpoint still gets re-enabled with the current token.
    expect(snsMock.commandCalls(SetEndpointAttributesCommand)).toHaveLength(1);
  });

  it('returns null (no-op) when push is not configured', async () => {
    delete process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;
    const arn = await NotificationService.registerEndpoint('tok-1', 'ios');
    expect(arn).toBeNull();
    expect(snsMock.commandCalls(CreatePlatformEndpointCommand)).toHaveLength(0);
  });
});

describe('sendRestoreComplete', () => {
  it('publishes to each active endpoint', async () => {
    (prisma.userDeviceToken.findMany as jest.Mock).mockResolvedValue([
      { id: 't1', snsEndpointArn: 'arn:e1', isActive: true },
      { id: 't2', snsEndpointArn: 'arn:e2', isActive: true },
    ]);
    snsMock.on(PublishCommand).resolves({ MessageId: 'm' });

    await NotificationService.sendRestoreComplete('user-1', 'book-1', 'Twelve Months');

    const pubs = snsMock.commandCalls(PublishCommand);
    expect(pubs).toHaveLength(2);
    expect(pubs[0].args[0].input.MessageStructure).toBe('json');
    // APNs payload carries the deep-link fields
    const apns = JSON.parse(JSON.parse(pubs[0].args[0].input.Message as string).APNS);
    expect(apns).toMatchObject({ bookId: 'book-1', action: 'restore_complete' });
  });

  it('deactivates an endpoint that SNS reports disabled', async () => {
    (prisma.userDeviceToken.findMany as jest.Mock).mockResolvedValue([
      { id: 't1', snsEndpointArn: 'arn:e1', isActive: true },
    ]);
    snsMock
      .on(PublishCommand)
      .rejects(Object.assign(new Error('gone'), { name: 'EndpointDisabledException' }));

    await NotificationService.sendRestoreComplete('user-1', 'book-1', 'Title');

    expect(prisma.userDeviceToken.update).toHaveBeenCalledWith({
      where: { id: 't1' },
      data: { isActive: false },
    });
  });

  it('no-ops when push is not configured', async () => {
    delete process.env.AWS_SNS_PLATFORM_APPLICATION_ARN_SANDBOX;
    await NotificationService.sendRestoreComplete('user-1', 'book-1', 'Title');
    expect(prisma.userDeviceToken.findMany).not.toHaveBeenCalled();
  });

  it('no-ops when the user has no active tokens', async () => {
    (prisma.userDeviceToken.findMany as jest.Mock).mockResolvedValue([]);
    await NotificationService.sendRestoreComplete('user-1', 'book-1', 'Title');
    expect(snsMock.commandCalls(PublishCommand)).toHaveLength(0);
  });
});
