import { describe, it, expect, vi } from 'vitest';
import {
  handleTokenSync,
  handlePublicKeyUpdate,
  handlePublicKeyFetch,
  handleHeartbeat,
  authenticateRequest,
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

describe('Integration Tests - Part 2', () => {
  describe('handleTokenSync', () => {
    it('should sync APNs token', async () => {
      const env = createMockEnv();
      const request = new Request('http://localhost/v1/user/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          userId: 'user-123',
          apnsToken: 'device-token-abc',
        }),
      });

      const response = await handleTokenSync(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.success).toBe(true);
      expect(body.userId).toBe('user-123');
    });

    it('should reject missing userId', async () => {
      const env = createMockEnv();
      const request = new Request('http://localhost/v1/user/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ apnsToken: 'token' }),
      });

      const response = await handleTokenSync(request, env);
      expect(response.status).toBe(400);
    });
  });

  describe('handlePublicKeyUpdate', () => {
    it('should update public key', async () => {
      const env = createMockEnv();
      const token = await createJWT('user-123', env.JWT_SECRET, 3600);
      // 32 bytes = 44 chars base64 (with padding)
      const validPublicKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      const request = new Request('http://localhost/v1/user/public-key', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ publicKey: validPublicKey }),
      });

      const response = await handlePublicKeyUpdate(request, env);
      expect(response.status).toBe(200);
    });

    it('should reject unauthorized request', async () => {
      const env = createMockEnv();
      const request = new Request('http://localhost/v1/user/public-key', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ publicKey: 'key' }),
      });

      const response = await handlePublicKeyUpdate(request, env);
      expect(response.status).toBe(401);
    });
  });

  describe('handlePublicKeyFetch', () => {
    it('should fetch public key for a user', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.first.mockResolvedValue({ public_key: 'user-public-key' });

      const token = await createJWT('user-123', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/user/user-456/public-key', {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${token}` },
      });

      const response = await handlePublicKeyFetch(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.publicKey).toBe('user-public-key');
    });

    it('should return 404 for missing user', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.first.mockResolvedValue(null);

      const token = await createJWT('user-123', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/user/unknown-user/public-key', {
        method: 'GET',
        headers: { 'Authorization': `Bearer ${token}` },
      });

      const response = await handlePublicKeyFetch(request, env);
      expect(response.status).toBe(404);
    });
  });
});
