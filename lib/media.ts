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
 * Generate local API URL for audio files served via /api/audio endpoint.
 *
 * Used in development when S3 is not enabled. Encodes path segments to handle
 * special characters. Supports range requests for audio streaming.
 *
 * @param audioPath - Path relative to media directory (e.g., "books/book1.m4b")
 * @returns Local API URL (e.g., "http://localhost:3000/api/audio/books/book1.m4b")
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
 * Get cover image URL with environment-aware handling.
 *
 * In production (S3 enabled): Generates time-limited presigned S3 URL (1 hour expiry)
 * In development: Returns local API route URL
 *
 * This is async because S3 presigned URL generation requires API calls. Used by
 * book transformers to ensure cover images are accessible in API responses.
 *
 * @param coverPath - Relative path to cover image from MEDIA_DATA_PATH
 * @returns Promise resolving to presigned S3 URL or local API URL, null if no path
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
