import { describe, it, expect, beforeEach } from 'vitest';
import { RateLimiterDO } from '../RateLimiterDO';

// Mock DurableObjectState for testing
function createMockDurableObjectState() {
  const storage = new Map<string, any>();
  return {
    storage: {
      get: async (key: string) => storage.get(key),
      put: async (key: string, value: any) => { storage.set(key, value); },
      delete: async (key: string) => { storage.delete(key); },
    },
  } as unknown as DurableObjectState;
}

describe('RateLimiterDO', () => {
  let rateLimiter: RateLimiterDO;
  let mockState: DurableObjectState;

  beforeEach(() => {
    mockState = createMockDurableObjectState();
    rateLimiter = new RateLimiterDO(mockState);
  });

  describe('handleRateCheck', () => {
    it('should allow first request', async () => {
      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'POST' })
      );
      expect(response.status).toBe(200);
      const body = await response.json() as { success: boolean; remaining: number };
      expect(body.success).toBe(true);
      expect(body.remaining).toBe(99);
    });

    it('should track multiple requests and decrease remaining', async () => {
      // Make 5 requests
      for (let i = 0; i < 5; i++) {
        await rateLimiter.fetch(
          new Request('http://rate-limiter/check', { method: 'POST' })
        );
      }

      // Check remaining
      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'POST' })
      );
      expect(response.status).toBe(200);
      const body = await response.json() as { remaining: number };
      expect(body.remaining).toBe(94); // 100 - 6
    });

    it('should reject requests exceeding the limit', async () => {
      // Make 100 requests to hit the limit
      for (let i = 0; i < 100; i++) {
        await rateLimiter.fetch(
          new Request('http://rate-limiter/check', { method: 'POST' })
        );
      }

      // The 101st request should be rate limited
      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'POST' })
      );
      expect(response.status).toBe(429);
      const body = await response.json() as { error: string; remaining: number };
      expect(body.error).toBe('QUOTA_EXCEEDED');
      expect(body.remaining).toBe(0);
    });

    it('should include Retry-After header when rate limited', async () => {
      // Hit the limit
      for (let i = 0; i < 101; i++) {
        await rateLimiter.fetch(
          new Request('http://rate-limiter/check', { method: 'POST' })
        );
      }

      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'POST' })
      );
      expect(response.headers.get('Retry-After')).not.toBeNull();
      const retryAfter = parseInt(response.headers.get('Retry-After')!);
      expect(retryAfter).toBeGreaterThan(0);
      expect(retryAfter).toBeLessThanOrEqual(3600);
    });
  });

  describe('handleReset', () => {
    it('should clear rate limit state', async () => {
      // Make some requests
      for (let i = 0; i < 50; i++) {
        await rateLimiter.fetch(
          new Request('http://rate-limiter/check', { method: 'POST' })
        );
      }

      // Reset
      const resetResponse = await rateLimiter.fetch(
        new Request('http://rate-limiter/reset', { method: 'POST' })
      );
      expect(resetResponse.status).toBe(200);
      const resetBody = await resetResponse.json() as { success: boolean };
      expect(resetBody.success).toBe(true);

      // Should allow requests again
      const checkResponse = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'POST' })
      );
      expect(checkResponse.status).toBe(200);
      const checkBody = await checkResponse.json() as { remaining: number };
      expect(checkBody.remaining).toBe(99);
    });
  });

  describe('unknown path', () => {
    it('should return 404 for unknown paths', async () => {
      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/unknown', { method: 'GET' })
      );
      expect(response.status).toBe(404);
      const body = await response.json() as { error: string };
      expect(body.error).toBe('NOT_FOUND');
    });

    it('should return 404 for wrong method on check path', async () => {
      const response = await rateLimiter.fetch(
        new Request('http://rate-limiter/check', { method: 'GET' })
      );
      expect(response.status).toBe(404);
    });
  });
});
