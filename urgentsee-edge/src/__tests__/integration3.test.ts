import { describe, it, expect, vi } from 'vitest';
import {
  handleTrustCircleInvite,
  handleTrustCircleAccept,
  handleTrustCircleBlock,
  handleTrustCircleRemove,
  createJWT,
} from '../index';

// Mock Env factory
function createMockEnv(overrides: Partial<any> = {}): any {
  const db = {
    prepare: vi.fn().mockReturnThis(),
    bind: vi.fn().mockReturnThis(),
    run: vi.fn().mockResolvedValue({ success: true }),
    all: vi.fn().mockResolvedValue({ results: [] }),
    first: vi.fn().mockResolvedValue(null),
  };

  const kv = {
    get: vi.fn().mockResolvedValue(null),
    put: vi.fn().mockResolvedValue(undefined),
    delete: vi.fn().mockResolvedValue(undefined),
  };

  return {
    READRUSH_DB: db,
    DEVICE_TOKENS_KV: kv,
    RATE_LIMITER_DO: {
      idFromName: vi.fn().mockReturnValue({ toString: () => 'test-id' }),
      get: vi.fn().mockReturnValue({
        fetch: vi.fn().mockResolvedValue(new Response(JSON.stringify({ success: true, remaining: 99 }))),
      }),
    },
    APNS_TOPIC: 'com.urgentsee.UrgentSee',
    APNS_AUTH_KEY: 'test-key',
    APNS_KEY_ID: 'test-key-id',
    APNS_TEAM_ID: 'test-team-id',
    APNS_ENV: 'development',
    JWT_SECRET: 'test-secret-for-integration-tests',
    ...overrides,
  };
}

describe('Integration Tests - Trust Circle', () => {
  describe('handleTrustCircleInvite', () => {
    it('should invite a user to trust circle', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });
      // Mock: first call returns target user, second call returns null (no existing relationship)
      let firstCallCount = 0;
      env.READRUSH_DB.first.mockImplementation(() => {
        firstCallCount++;
        if (firstCallCount === 1) return Promise.resolve({ user_id: 'user-2' }); // User exists
        return Promise.resolve(null); // No existing relationship
      });

      const token = await createJWT('user-1', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/trust-circle/invite', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ palId: 'user-2' }),
      });

      const response = await handleTrustCircleInvite(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.success).toBe(true);
    });

    it('should reject self-invitation', async () => {
      const env = createMockEnv();
      const token = await createJWT('user-1', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/trust-circle/invite', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ palId: 'user-1' }),
      });

      const response = await handleTrustCircleInvite(request, env);
      expect(response.status).toBe(400);
    });

    it('should reject unauthorized request', async () => {
      const env = createMockEnv();
      const request = new Request('http://localhost/v1/trust-circle/invite', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ palId: 'user-2' }),
      });

      const response = await handleTrustCircleInvite(request, env);
      expect(response.status).toBe(401);
    });
  });

  describe('handleTrustCircleAccept', () => {
    it('should accept a trust circle invite', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });
      // Mock: pending invite exists
      env.READRUSH_DB.first.mockResolvedValue({ user_id: 'user-1', pal_id: 'user-2', status: 'PENDING' });

      const token = await createJWT('user-2', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/trust-circle/accept', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ palId: 'user-1' }),
      });

      const response = await handleTrustCircleAccept(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.success).toBe(true);
    });
  });

  describe('handleTrustCircleBlock', () => {
    it('should block a user', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });

      const token = await createJWT('user-1', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/trust-circle/block', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ palId: 'user-2' }),
      });

      const response = await handleTrustCircleBlock(request, env);
      expect(response.status).toBe(200);
    });
  });

  describe('handleTrustCircleRemove', () => {
    it('should remove a user from trust circle', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });

      const token = await createJWT('user-1', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/trust-circle/remove', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ palId: 'user-2' }),
      });

      const response = await handleTrustCircleRemove(request, env);
      expect(response.status).toBe(200);
    });
  });
});
