// Utility to get the correct URL for media files (images, audio)
// In development: serves from local filesystem via API
// In production: serves from S3

import path from 'path';

const S3_BUCKET = process.env.AWS_S3_BUCKET;
const S3_REGION = process.env.AWS_REGION || 'us-east-1';
const USE_S3 = process.env.NODE_ENV === 'production' && S3_BUCKET;

/**
 * Get the configured media data path from environment variable
 * Falls back to test-data directory if not set
 */
export function getMediaPath(): string {
  return process.env.MEDIA_DATA_PATH || 'test-data';
}

/**
 * Get the absolute media data path
 */
export function getAbsoluteMediaPath(): string {
  const mediaPath = getMediaPath();
  return path.isAbsolute(mediaPath) ? mediaPath : path.join(process.cwd(), mediaPath);
}

/**
 * Validate that a requested path is within the media directory
 * Prevents directory traversal attacks
 */
export function validateMediaPath(requestedPath: string): boolean {
  const mediaDir = getAbsoluteMediaPath();
  const resolvedPath = path.resolve(requestedPath);
  return resolvedPath.startsWith(mediaDir);
}

/**
 * Convert a relative file path to the appropriate URL
 * @param relativePath - Path relative to test-data directory (e.g., "Book Title [ASIN]/cover.jpg")
 * @returns Full URL to access the file
 */
export function getMediaUrl(relativePath: string | null): string | null {
  if (!relativePath) return null;

  if (USE_S3) {
    // Production: S3 URL
    // Assuming files are uploaded to S3 with the same path structure
    const encodedPath = relativePath.split('/').map(encodeURIComponent).join('/');
    return `https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${encodedPath}`;
  } else {
    // Development: Local API endpoint with absolute URL for mobile clients
    const encodedPath = relativePath.split('/').map(encodeURIComponent).join('/');
    const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
    return `${baseUrl}/api/images/${encodedPath}`;
  }
}

/**
 * Get cover image URL
 */
export function getCoverUrl(coverPath: string | null): string | null {
  return getMediaUrl(coverPath);
}

/**
 * Get audio file URL
 * For audio files, use the /api/audio endpoint for streaming support
 */
export function getAudioUrl(audioPath: string | null): string | null {
  if (!audioPath) return null;

  if (USE_S3) {
    // Production: S3 URL
    const encodedPath = audioPath.split('/').map(encodeURIComponent).join('/');
    return `https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${encodedPath}`;
  } else {
    // Development: Audio streaming API endpoint with absolute URL for mobile clients
    const encodedPath = audioPath.split('/').map(encodeURIComponent).join('/');
    const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
    return `${baseUrl}/api/audio/${encodedPath}`;
  }
}
