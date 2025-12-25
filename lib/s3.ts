/**
 * AWS S3 Helper Module
 *
 * Provides singleton S3 client and streaming utilities for production media storage.
 * Falls back to local filesystem in development.
 */

import { S3Client, GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Readable } from 'stream';

const S3_BUCKET = process.env.AWS_S3_BUCKET;
const S3_REGION = process.env.AWS_REGION || 'us-east-1';

// Singleton S3 client (similar to Prisma singleton pattern)
let s3Client: S3Client | null = null;

/**
 * Get or create S3 client singleton
 * Only initializes when S3 is enabled
 */
export function getS3Client(): S3Client {
  if (!s3Client) {
    if (!process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) {
      throw new Error('AWS credentials not configured');
    }

    s3Client = new S3Client({
      region: S3_REGION,
      credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
      },
    });
  }
  return s3Client;
}

/**
 * Check if S3 is enabled and properly configured
 * Returns true only in production with valid credentials
 */
export function isS3Enabled(): boolean {
  return !!(
    process.env.NODE_ENV === 'production' &&
    S3_BUCKET &&
    process.env.AWS_ACCESS_KEY_ID &&
    process.env.AWS_SECRET_ACCESS_KEY
  );
}

/**
 * Get the configured S3 bucket name
 */
export function getS3Bucket(): string | undefined {
  return S3_BUCKET;
}

/**
 * Get the configured S3 region
 */
export function getS3Region(): string {
  return S3_REGION;
}

/**
 * Stream an object from S3
 * Used for images and other non-seekable content
 *
 * @param key - S3 object key (file path)
 * @returns Stream, content type, and content length
 */
export async function streamS3Object(key: string): Promise<{
  stream: Readable;
  contentType: string;
  contentLength: number;
}> {
  const client = getS3Client();
  const command = new GetObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
  });

  const response = await client.send(command);

  if (!response.Body) {
    throw new Error('No body in S3 response');
  }

  return {
    stream: response.Body as Readable,
    contentType: response.ContentType || 'application/octet-stream',
    contentLength: response.ContentLength || 0,
  };
}

/**
 * Stream an object from S3 with optional range support
 * Used for audio streaming with seeking capabilities
 *
 * @param key - S3 object key (file path)
 * @param range - Optional byte range {start, end}
 * @returns Stream with metadata including content range
 */
export async function streamS3ObjectWithRange(
  key: string,
  range?: { start: number; end: number }
): Promise<{
  stream: Readable;
  contentType: string;
  contentLength: number;
  contentRange?: string;
  totalSize: number;
}> {
  const client = getS3Client();

  // Build Range header if provided
  const rangeHeader = range ? `bytes=${range.start}-${range.end}` : undefined;

  const command = new GetObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Range: rangeHeader,
  });

  const response = await client.send(command);

  if (!response.Body) {
    throw new Error('No body in S3 response');
  }

  // Extract total size from ContentRange header (format: "bytes start-end/total")
  const totalSize = range
    ? parseInt(response.ContentRange?.split('/')[1] || '0', 10)
    : response.ContentLength || 0;

  return {
    stream: response.Body as Readable,
    contentType: response.ContentType || 'application/octet-stream',
    contentLength: response.ContentLength || 0,
    contentRange: response.ContentRange,
    totalSize,
  };
}

/**
 * Get metadata for an S3 object without downloading it
 * Used to get file size for range request validation
 *
 * @param key - S3 object key (file path)
 * @returns Object metadata including size and content type
 */
export async function getS3ObjectMetadata(key: string): Promise<{
  size: number;
  contentType: string;
}> {
  const client = getS3Client();
  const command = new HeadObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
  });

  const response = await client.send(command);

  return {
    size: response.ContentLength || 0,
    contentType: response.ContentType || 'application/octet-stream',
  };
}

/**
 * Check if an S3 object exists
 *
 * @param key - S3 object key (file path)
 * @returns true if object exists, false otherwise
 */
export async function s3ObjectExists(key: string): Promise<boolean> {
  try {
    await getS3ObjectMetadata(key);
    return true;
  } catch (error: any) {
    if (error.name === 'NotFound' || error.name === 'NoSuchKey') {
      return false;
    }
    throw error;
  }
}

/**
 * Generate a pre-signed URL for downloading an S3 object
 * URL is valid for specified duration (default 1 hour)
 *
 * @param key - S3 object key (file path)
 * @param expiresIn - URL validity in seconds (default: 3600 = 1 hour)
 * @returns Pre-signed URL string
 */
export async function generatePresignedUrl(key: string, expiresIn: number = 3600): Promise<string> {
  const client = getS3Client();
  const command = new GetObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
  });

  const url = await getSignedUrl(client, command, { expiresIn });
  return url;
}
