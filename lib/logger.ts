/**
 * Simple structured logger for API requests
 *
 * Log levels (controlled by LOG_LEVEL env var):
 * - error: Only errors (default for production if not set)
 * - warn: Errors + warnings
 * - info: Errors + warnings + request summaries
 * - debug: Everything including request/response details
 */

type LogLevel = 'error' | 'warn' | 'info' | 'debug';

const LOG_LEVELS: Record<LogLevel, number> = {
  error: 0,
  warn: 1,
  info: 2,
  debug: 3,
};

function getLogLevel(): LogLevel {
  const level = process.env.LOG_LEVEL?.toLowerCase() as LogLevel;
  return LOG_LEVELS[level] !== undefined ? level : 'info';
}

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] <= LOG_LEVELS[getLogLevel()];
}

function formatLog(level: LogLevel, message: string, meta?: Record<string, unknown>): string {
  const timestamp = new Date().toISOString();
  const metaStr = meta ? ` ${JSON.stringify(meta)}` : '';
  return `${timestamp} [${level.toUpperCase()}] ${message}${metaStr}`;
}

export const logger = {
  error(message: string, meta?: Record<string, unknown>) {
    if (shouldLog('error')) {
      console.error(formatLog('error', message, meta));
    }
  },

  warn(message: string, meta?: Record<string, unknown>) {
    if (shouldLog('warn')) {
      console.warn(formatLog('warn', message, meta));
    }
  },

  info(message: string, meta?: Record<string, unknown>) {
    if (shouldLog('info')) {
      // Use console.warn for info level (ESLint only allows warn/error)
      console.warn(formatLog('info', message, meta));
    }
  },

  debug(message: string, meta?: Record<string, unknown>) {
    if (shouldLog('debug')) {
      // Use console.warn for debug level (ESLint only allows warn/error)
      console.warn(formatLog('debug', message, meta));
    }
  },

  /**
   * Log an API request summary
   * Use at the end of API route handlers
   */
  request(
    method: string,
    path: string,
    status: number,
    durationMs: number,
    meta?: Record<string, unknown>
  ) {
    if (shouldLog('info')) {
      const level = status >= 500 ? 'error' : status >= 400 ? 'warn' : 'info';
      // Route to appropriate console method based on status
      const logFn = status >= 500 ? console.error : console.warn;
      logFn(formatLog(level as LogLevel, `${method} ${path} ${status} ${durationMs}ms`, meta));
    }
  },
};

/**
 * Helper to measure request duration
 * Usage:
 *   const timer = startTimer();
 *   // ... handle request
 *   logger.request('GET', '/api/books', 200, timer());
 */
export function startTimer(): () => number {
  const start = Date.now();
  return () => Date.now() - start;
}

// MARK: - Route Wrapper for Automatic Logging

import { NextRequest, NextResponse } from 'next/server';

type RouteHandler = (
  request: NextRequest,
  context?: { params: Promise<Record<string, string>> }
) => Promise<NextResponse>;

/**
 * Wraps an API route handler with automatic request/response logging.
 * Logs method, path, status code, and duration for every request.
 *
 * Usage:
 * ```typescript
 * import { withLogging } from '@/lib/logger';
 *
 * export const GET = withLogging(async (request) => {
 *   // Your handler logic
 *   return NextResponse.json({ data });
 * });
 * ```
 */
export function withLogging(handler: RouteHandler): RouteHandler {
  return async (request: NextRequest, context?: { params: Promise<Record<string, string>> }) => {
    const timer = startTimer();
    const method = request.method;
    const path = request.nextUrl.pathname;

    try {
      const response = await handler(request, context);
      const duration = timer();
      logger.request(method, path, response.status, duration);
      return response;
    } catch (error) {
      const duration = timer();
      logger.error(`${method} ${path} failed`, { error: String(error), durationMs: duration });
      throw error;
    }
  };
}
