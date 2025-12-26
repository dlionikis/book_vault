import { NextResponse } from 'next/server';

/**
 * Health check endpoint for CI/CD and monitoring
 * Returns 200 OK if server is running
 */
export async function GET() {
  return NextResponse.json({ status: 'ok' }, { status: 200 });
}
