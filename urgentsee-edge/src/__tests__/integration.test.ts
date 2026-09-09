import { describe, it, expect, vi } from 'vitest';
import {
  handleDeviceRegister,
  handlePairingCode,
  handlePairingClaim,
  handleTokenSync,
  handlePublicKeyUpdate,
  handlePublicKeyFetch,
  handleTrustCircleList,
  handleTrustCircleInvite,
  handleTrustCircleAccept,
  handleTrustCircleBlock,
  handleTrustCircleRemove,
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

describe('Integration Tests', () => {
  describe('handleDeviceRegister', () => {
    it('should register a new device and return JWT', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });

      const request = new Request('http://localhost/v1/device/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          deviceId: 'test-device-123',
          publicKey: 'cHVibGljLWtleS10ZXN0',
          displayName: 'Test Device',
        }),
      });

      const response = await handleDeviceRegister(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.userId).toBeDefined();
      expect(body.userId.startsWith('usr_')).toBe(true);
      expect(body.token).toBeDefined();
    });

    it('should reject missing deviceId', async () => {
      const env = createMockEnv();
      const request = new Request('http://localhost/v1/device/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ publicKey: 'test-key' }),
      });

      const response = await handleDeviceRegister(request, env);
      expect(response.status).toBe(400);
    });
  });

  describe('handlePairingCode', () => {
    it('should generate a pairing code', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });

      const token = await createJWT('user-123', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/pairing/code', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
      });

      const response = await handlePairingCode(request, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.code).toBeDefined();
      expect(body.code.length).toBe(6);
      expect(body.expiresAt).toBeDefined();
    });
  });

  describe('handlePairingClaim', () => {
    it('should claim a valid pairing code', async () => {
      const env = createMockEnv();
      env.READRUSH_DB.run.mockResolvedValue({ success: true });

      // First generate a code
      const token1 = await createJWT('user-1', env.JWT_SECRET, 3600);
      const codeRequest = new Request('http://localhost/v1/pairing/code', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token1}`,
        },
      });
      const codeResponse = await handlePairingCode(codeRequest, env);
      const { code } = await codeResponse.json() as any;

      // Mock KV to return the target user when code is looked up
      env.DEVICE_TOKENS_KV.get.mockImplementation((key: string) => {
        if (key === `pairing:${code}`) return Promise.resolve('user-1');
        return Promise.resolve(null);
      });

      // Now claim it with a different user
      const token2 = await createJWT('user-2', env.JWT_SECRET, 3600);
      const claimRequest = new Request('http://localhost/v1/pairing/claim', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token2}`,
        },
        body: JSON.stringify({ code }),
      });

      const response = await handlePairingClaim(claimRequest, env);
      expect(response.status).toBe(200);

      const body = await response.json() as any;
      expect(body.success).toBe(true);
      expect(body.pairedWith).toBe('user-1');
    });

    it('should reject invalid pairing code', async () => {
      const env = createMockEnv();
      env.DEVICE_TOKENS_KV.get.mockResolvedValue(null); // Code not found

      const token = await createJWT('user-1', env.JWT_SECRET, 3600);
      const request = new Request('http://localhost/v1/pairing/claim', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
        },
        body: JSON.stringify({ code: 'INVALID' }),
      });

      const response = await handlePairingClaim(request, env);
      expect(response.status).toBe(404);
    });
  });
});
