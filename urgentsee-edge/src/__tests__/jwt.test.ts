import { describe, it, expect } from 'vitest';
import { verifyJWT } from '../index';

const SECRET = 'test-secret-key-for-testing-purposes-only';

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

describe('verifyJWT', () => {
  it('should reject a token with wrong number of parts', async () => {
    const result = await verifyJWT('onlytwo.parts', SECRET);
    expect(result).toBeNull();
  });

  it('should reject a token with too many parts', async () => {
    const result = await verifyJWT('a.b.c.d', SECRET);
    expect(result).toBeNull();
  });

  it('should reject a token with empty parts', async () => {
    const result = await verifyJWT('..', SECRET);
    expect(result).toBeNull();
  });

  it('should reject an expired token', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user123', iat: now - 7200, exp: now - 3600 };
    const token = await createTestJWT(payload, SECRET);
    const result = await verifyJWT(token, SECRET);
    expect(result).toBeNull();
  });

  it('should accept a valid non-expired token with correct signature', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user123', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, SECRET);
    const result = await verifyJWT(token, SECRET);
    expect(result).not.toBeNull();
    expect(result?.sub).toBe('user123');
  });

  it('should reject token signed with different secret', async () => {
    const now = Math.floor(Date.now() / 1000);
    const payload = { sub: 'user123', iat: now, exp: now + 3600 };
    const token = await createTestJWT(payload, 'different-secret');
    const result = await verifyJWT(token, SECRET);
    expect(result).toBeNull();
  });
});
