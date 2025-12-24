/**
 * Get the base URL for API calls
 * Uses environment variable or falls back to localhost in development
 */
export function getBaseUrl(): string {
  // Check for explicit API URL setting
  if (process.env.NEXT_PUBLIC_API_URL) {
    return process.env.NEXT_PUBLIC_API_URL;
  }

  // In production, use VERCEL_URL if available
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }

  // In development or when deployed elsewhere, use localhost
  return process.env.NODE_ENV === 'production'
    ? 'https://your-production-domain.com' // Replace with actual domain
    : 'http://localhost:3000';
}
