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
      console.log(formatLog('info', message, meta));
    }
  },

  debug(message: string, meta?: Record<string, unknown>) {
    if (shouldLog('debug')) {
      console.log(formatLog('debug', message, meta));
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
      console.log(
        formatLog(level as LogLevel, `${method} ${path} ${status} ${durationMs}ms`, meta)
      );
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
