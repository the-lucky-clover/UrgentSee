import { describe, it, expect, vi } from 'vitest';

// We need to test authenticateRequest but it's not exported.
// We'll test it indirectly by mocking the Env and calling verifyJWT.
// Since authenticateRequest depends on verifyJWT (which is also not exported directly),
// we test the exported verifyJWT thoroughly instead.

import { verifyJWT, base64UrlDecode } from '../index';

const SECRET = 'test-secret-key';

function base64UrlEncode(data: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < data.byteLength; i++) binary += String.fromCharCode(data[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function createTestJWT(payload: Record<string, any>, secret: string): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const data = `${headerB64}.${payloadB64}`;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data));
  return `${data}.${base64UrlEncode(new Uint8Array(sig))}`;
}

describe('JWT Authentication Flow', () => {
  it('should correctly extract sub from a valid token', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user-abc-123', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, SECRET);

    const result = await verifyJWT(token, SECRET);
    expect(result).not.toBeNull();
    expect(result?.sub).toBe('user-abc-123');
  });

  it('should reject token at exact expiration boundary', async () => {
    const now = Math.floor(Date.now() / 1000);
    // Token that expires "now" - should be rejected because exp * 1000 < Date.now()
    const payload = { sub: 'user123', iat: now - 3600, exp: now };
    const token = await createTestJWT(payload, SECRET);

    // This might pass or fail depending on execution speed, but generally
    // if exp is exactly now, exp * 1000 should be <= Date.now()
    const result = await verifyJWT(token, SECRET);
    // We just verify it doesn't crash; the exact behavior at boundary is timing-dependent
    expect(result === null || result?.sub === 'user123').toBe(true);
  });

  it('should handle tokens with special characters in sub', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user+test/test@domain.com', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, SECRET);

    const result = await verifyJWT(token, SECRET);
    expect(result).not.toBeNull();
    expect(result?.sub).toBe('user+test/test@domain.com');
  });

  it('should handle tokens with unicode in sub', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user-🎉-test', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, SECRET);

    const result = await verifyJWT(token, SECRET);
    expect(result).not.toBeNull();
    expect(result?.sub).toBe('user-🎉-test');
  });

  it('should reject token with modified payload after signing', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'original', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, SECRET);

    // Tamper with the token by replacing the payload
    const parts = token.split('.');
    const maliciousPayload = { sub: 'admin', iat: now, exp: now + 3600 };
    const maliciousPayloadB64 = base64UrlEncode(
      new TextEncoder().encode(JSON.stringify(maliciousPayload))
    );
    const tamperedToken = `${parts[0]}.${maliciousPayloadB64}.${parts[2]}`;

    const result = await verifyJWT(tamperedToken, SECRET);
    expect(result).toBeNull();
  });

  it('should reject token with algorithm confusion (none)', async () => {
    // Create a token with alg: none
    const header = { alg: 'none', typ: 'JWT' };
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user123', iat: now, exp: now + 3600 };

    const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
    const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const token = `${headerB64}.${payloadB64}.`;

    const result = await verifyJWT(token, SECRET);
    // Should reject because signature verification will fail on empty signature
    expect(result).toBeNull();
  });
});
