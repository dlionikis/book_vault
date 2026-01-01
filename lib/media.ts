// Utility to get the correct URL for media files (images, audio)
// In development: serves from local filesystem via API
// In production: generates presigned S3 URLs directly

import path from 'path';
import { isS3Enabled, generatePresignedUrl } from './s3';

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

// ============================================================================
// SYNC URL HELPERS (for development/local filesystem)
// ============================================================================

/**
 * Convert a relative file path to local API URL (sync, for development)
 * @param relativePath - Path relative to media directory
 * @returns Local API URL
 */
export function getLocalMediaUrl(relativePath: string | null): string | null {
  if (!relativePath) return null;
  const encodedPath = relativePath.split('/').map(encodeURIComponent).join('/');
  const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
  return `${baseUrl}/api/images/${encodedPath}`;
}

/**
 * Get local audio URL (sync, for development)
 */
export function getLocalAudioUrl(audioPath: string | null): string | null {
  if (!audioPath) return null;
  const encodedPath = audioPath.split('/').map(encodeURIComponent).join('/');
  const baseUrl = process.env.NEXTAUTH_URL || 'http://localhost:3000';
  return `${baseUrl}/api/audio/${encodedPath}`;
}

// ============================================================================
// ASYNC URL HELPERS (for production with presigned S3 URLs)
// ============================================================================

/** Presigned URL expiry time in seconds (1 hour) */
const PRESIGNED_URL_EXPIRY = 3600;

/**
 * Get cover image URL - async version that generates presigned S3 URLs in production
 * @param coverPath - Relative path to cover image
 * @returns Presigned S3 URL in production, local API URL in development
 */
export async function getCoverUrl(coverPath: string | null): Promise<string | null> {
  if (!coverPath) return null;

  if (isS3Enabled()) {
    // Production: Generate presigned S3 URL
    return await generatePresignedUrl(coverPath, PRESIGNED_URL_EXPIRY);
  }

  // Development: Use local API route
  return getLocalMediaUrl(coverPath);
}

/**
 * Get audio file URL - async version that generates presigned S3 URLs in production
 * @param audioPath - Relative path to audio file
 * @returns Presigned S3 URL in production, local API URL in development
 */
export async function getAudioUrl(audioPath: string | null): Promise<string | null> {
  if (!audioPath) return null;

  if (isS3Enabled()) {
    // Production: Generate presigned S3 URL
    return await generatePresignedUrl(audioPath, PRESIGNED_URL_EXPIRY);
  }

  // Development: Use local API route
  return getLocalAudioUrl(audioPath);
}
