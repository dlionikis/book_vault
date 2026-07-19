/**
 * @jest-environment node
 */

describe('S3 Helper Module', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeAll(() => {
    // Save original environment and set up test environment
    originalEnv = { ...process.env };

    // Set environment variables that will be used by all tests
    Object.defineProperty(process.env, 'NODE_ENV', {
      value: 'production',
      writable: true,
      configurable: true,
    });
    process.env.AWS_S3_BUCKET = 'test-bucket';
    process.env.AWS_ACCESS_KEY_ID = 'test-key-id';
    process.env.AWS_SECRET_ACCESS_KEY = 'test-secret-key';
    process.env.AWS_REGION = 'us-west-2';
  });

  afterAll(() => {
    // Restore original environment
    process.env = originalEnv;
  });

  it('module exports all expected functions', async () => {
    const s3Module = await import('@/lib/s3');

    expect(typeof s3Module.isS3Enabled).toBe('function');
    expect(typeof s3Module.getS3Bucket).toBe('function');
    expect(typeof s3Module.getS3Region).toBe('function');
    expect(typeof s3Module.getS3Client).toBe('function');
    expect(typeof s3Module.streamS3Object).toBe('function');
    expect(typeof s3Module.streamS3ObjectWithRange).toBe('function');
    expect(typeof s3Module.getS3ObjectMetadata).toBe('function');
    expect(typeof s3Module.s3ObjectExists).toBe('function');
  });

  it('isS3Enabled returns true with valid config', async () => {
    const { isS3Enabled } = await import('@/lib/s3');
    expect(isS3Enabled()).toBe(true);
  });

  it('getS3Bucket returns configured bucket', async () => {
    const { getS3Bucket } = await import('@/lib/s3');
    expect(getS3Bucket()).toBe('test-bucket');
  });

  it('getS3Region returns configured region', async () => {
    const { getS3Region } = await import('@/lib/s3');
    expect(getS3Region()).toBe('us-west-2');
  });

  it('getS3Client creates instance', async () => {
    const { getS3Client } = await import('@/lib/s3');
    const client = getS3Client();
    expect(client).toBeDefined();
  });
});

describe('isS3Enabled — S3_ENABLED dev override', () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    jest.resetModules(); // S3_BUCKET is captured at module load, so re-import per case
    // Non-production baseline (mirrors `next dev`, which pins NODE_ENV=development)
    Object.defineProperty(process.env, 'NODE_ENV', {
      value: 'development',
      writable: true,
      configurable: true,
    });
    process.env.AWS_S3_BUCKET = 'test-bucket';
    process.env.AWS_ACCESS_KEY_ID = 'test-key-id';
    process.env.AWS_SECRET_ACCESS_KEY = 'test-secret-key';
    delete process.env.S3_ENABLED;
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('returns false in development by default (no override)', async () => {
    const { isS3Enabled } = await import('@/lib/s3');
    expect(isS3Enabled()).toBe(false);
  });

  it('returns true in development when S3_ENABLED=true (hybrid mode)', async () => {
    process.env.S3_ENABLED = 'true';
    jest.resetModules();
    const { isS3Enabled } = await import('@/lib/s3');
    expect(isS3Enabled()).toBe(true);
  });

  it('still requires a bucket even with the override set', async () => {
    process.env.S3_ENABLED = 'true';
    delete process.env.AWS_S3_BUCKET;
    jest.resetModules();
    const { isS3Enabled } = await import('@/lib/s3');
    expect(isS3Enabled()).toBe(false);
  });

  it('ignores non-"true" override values', async () => {
    process.env.S3_ENABLED = '1';
    jest.resetModules();
    const { isS3Enabled } = await import('@/lib/s3');
    expect(isS3Enabled()).toBe(false);
  });
});
