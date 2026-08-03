import { NextRequest } from 'next/server';
import { checkIpRateLimit, checkRateLimit, getClientIp, __resetRateLimits } from '@/lib/rate-limit';

function requestFrom(headers: Record<string, string> = {}) {
  return new NextRequest('http://localhost:3000/api/auth/mobile/login', {
    method: 'POST',
    headers,
  });
}

beforeEach(() => {
  __resetRateLimits();
});

describe('getClientIp', () => {
  it('takes the left-most x-forwarded-for entry (the client, not a proxy hop)', () => {
    // The ALB appends the client IP and preserves any upstream chain, so the
    // client is left-most.
    expect(getClientIp(requestFrom({ 'x-forwarded-for': '203.0.113.5, 10.0.0.1, 10.0.0.2' }))).toBe(
      '203.0.113.5'
    );
  });

  it('trims whitespace around the entry', () => {
    expect(getClientIp(requestFrom({ 'x-forwarded-for': '  203.0.113.9 , 10.0.0.1' }))).toBe(
      '203.0.113.9'
    );
  });

  it('falls back to x-real-ip', () => {
    expect(getClientIp(requestFrom({ 'x-real-ip': '198.51.100.7' }))).toBe('198.51.100.7');
  });

  it('falls back to a shared bucket when no forwarding header is present', () => {
    // Stricter than skipping the limit — local dev shares one budget.
    expect(getClientIp(requestFrom())).toBe('unknown');
  });
});

describe('checkIpRateLimit', () => {
  const ip = { 'x-forwarded-for': '203.0.113.5' };

  it('allows requests up to the limit and rejects the next one', () => {
    for (let i = 0; i < 10; i++) {
      expect(checkIpRateLimit(requestFrom(ip), 'login', 10)).toBe(true);
    }
    expect(checkIpRateLimit(requestFrom(ip), 'login', 10)).toBe(false);
  });

  it('tracks each IP independently', () => {
    for (let i = 0; i < 10; i++) {
      checkIpRateLimit(requestFrom(ip), 'login', 10);
    }

    // A different client must not inherit the exhausted budget.
    expect(checkIpRateLimit(requestFrom({ 'x-forwarded-for': '198.51.100.1' }), 'login', 10)).toBe(
      true
    );
  });

  it('keeps buckets separate so one route cannot exhaust another', () => {
    for (let i = 0; i < 10; i++) {
      checkIpRateLimit(requestFrom(ip), 'login', 10);
    }
    expect(checkIpRateLimit(requestFrom(ip), 'login', 10)).toBe(false);
    expect(checkIpRateLimit(requestFrom(ip), 'refresh', 10)).toBe(true);
  });

  it('starts a fresh window once the previous one expires', () => {
    jest.useFakeTimers();
    try {
      for (let i = 0; i < 10; i++) {
        checkIpRateLimit(requestFrom(ip), 'login', 10, 60_000);
      }
      expect(checkIpRateLimit(requestFrom(ip), 'login', 10, 60_000)).toBe(false);

      jest.advanceTimersByTime(60_001);

      expect(checkIpRateLimit(requestFrom(ip), 'login', 10, 60_000)).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });
});

describe('checkRateLimit', () => {
  it('still limits per user id', () => {
    for (let i = 0; i < 3; i++) {
      expect(checkRateLimit('user-1', 3)).toBe(true);
    }
    expect(checkRateLimit('user-1', 3)).toBe(false);
    expect(checkRateLimit('user-2', 3)).toBe(true);
  });

  it('does not share a bucket with the IP limiter', () => {
    for (let i = 0; i < 10; i++) {
      checkIpRateLimit(requestFrom({ 'x-forwarded-for': '203.0.113.5' }), 'login', 10);
    }
    expect(checkRateLimit('user-1', 10)).toBe(true);
  });
});
