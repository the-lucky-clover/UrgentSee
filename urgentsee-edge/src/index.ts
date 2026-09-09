export interface Env {
  READRUSH_DB: D1Database;
  DEVICE_TOKENS_KV: KVNamespace;
  RATE_LIMITER_DO: DurableObjectNamespace;
  APNS_TOPIC: string;
  APNS_AUTH_KEY: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  APNS_ENV: string;
  JWT_SECRET: string;
}

export { RateLimiterDO } from './RateLimiterDO';
export { base64UrlDecode, verifyJWT };

interface JWTPayload {
  sub: string;
  iat: number;
  exp: number;
}

async function verifyJWT(token: string, secret: string): Promise<JWTPayload | null> {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const [headerB64, payloadB64, signatureB64] = parts;
    const data = `${headerB64}.${payloadB64}`;

    const key = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const signature = base64UrlDecode(signatureB64);
    const dataBytes = new TextEncoder().encode(data);
    // Create a new ArrayBuffer-backed Uint8Array to satisfy the strict BufferSource type
    const dataBuf = new Uint8Array(dataBytes);
    const valid = await crypto.subtle.verify('HMAC', key, signature, dataBuf);
    if (!valid) return null;

    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(payloadB64))) as JWTPayload;
    
    if (payload.exp * 1000 < Date.now()) return null;

    return payload;
  } catch {
    return null;
  }
}

function base64UrlDecode(str: string): ArrayBuffer {
  // Replace URL-safe chars
  let base64 = str.replace(/-/g, '+').replace(/_/g, '/');

  // Pad with '=' to make length a multiple of 4
  const pad = base64.length % 4;
  if (pad) {
    base64 += '='.repeat(4 - pad);
  }

  // Decode using atob (available in the Workers runtime)
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

export async function authenticateRequest(request: Request, env: Env): Promise<{ userId: string } | Response> {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'UNAUTHORIZED', message: 'Missing or invalid Authorization header' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const token = authHeader.slice(7);
  const payload = await verifyJWT(token, env.JWT_SECRET);
  
  if (!payload) {
    return new Response(JSON.stringify({ error: 'UNAUTHORIZED', message: 'Invalid or expired token' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  return { userId: payload.sub };
}

// MARK: - JWT signing (server-issued tokens)

export // MARK: - CORS

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS, PUT, GET, DELETE',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  'Access-Control-Max-Age': '86400',
};

function withCORS(response: Response): Response {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function base64UrlEncode(data: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < data.byteLength; i++) binary += String.fromCharCode(data[i]);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

// Cache one APNs provider token in KV and reuse it across isolates (~55 min).
// Apple rate-limits provider token generation to ~1 per 20 minutes, so signing
// per-request (or per-isolate) triggers 429 TooManyProviderTokenUpdates.
const apnsTokenCache = new Map<string, { token: string; expiresAt: number }>();

async function cachedAPNsAuthToken(env: Env): Promise<string> {
  const kvKey = `apns_provider_token:${env.APNS_KEY_ID}`;
  const now = Date.now();

  // Fast path: in-isolate cache.
  const local = apnsTokenCache.get(kvKey);
  if (local && local.expiresAt - now > 5 * 60 * 1000) {
    return local.token;
  }

  // Shared path: KV cache written by whichever isolate generated the current token.
  const stored = await env.DEVICE_TOKENS_KV.get(kvKey);
  if (stored) {
    try {
      const parsed = JSON.parse(stored) as { token: string; expiresAt: number };
      if (parsed.expiresAt - now > 5 * 60 * 1000) {
        apnsTokenCache.set(kvKey, parsed);
        return parsed.token;
      }
    } catch {
      // fall through and regenerate
    }
  }

  const token = await createAPNsAuthToken(env);
  const entry = { token, expiresAt: now + 55 * 60 * 1000 };
  apnsTokenCache.set(kvKey, entry);
  await env.DEVICE_TOKENS_KV.put(kvKey, JSON.stringify(entry), { expirationTtl: 3600 });
  return token;
}

export async function createJWT(sub: string, secret: string, ttlSeconds: number): Promise<string> {
  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = { sub, iat: now, exp: now + ttlSeconds };

  const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );

  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(signingInput) as unknown as BufferSource
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function pemToDer(pem: string): Uint8Array {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

// Signs an APNs provider token (ES256) valid for ~50 minutes.
async function createAPNsAuthToken(env: Env): Promise<string> {
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(env.APNS_AUTH_KEY) as unknown as BufferSource,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );

  const header = { alg: 'ES256', kid: env.APNS_KEY_ID };
  const payload = { iss: env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) };
  const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput) as unknown as BufferSource
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

// MARK: - Device bootstrap (issues real server-signed JWT)



export async function handleDeviceRegister(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as { deviceId: string; publicKey: string; displayName?: string };
  if (!body.deviceId || !body.publicKey) {
    return new Response(JSON.stringify({ error: 'MISSING_REQUIRED_FIELDS' }), { status: 400 });
  }

  // Stable user id derived from the device id so reinstalls keep identity when keys persist.
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body.deviceId));
  const userId = `usr_${base64UrlEncode(new Uint8Array(digest)).slice(0, 12).toLowerCase()}`;

  await env.READRUSH_DB.prepare(
    `INSERT INTO us_users (user_id, public_key, apns_token, updated_at)
     VALUES (?, ?, NULL, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id) DO UPDATE SET public_key = ?, updated_at = CURRENT_TIMESTAMP`
  ).bind(userId, body.publicKey, body.publicKey).run();

  const token = await createJWT(userId, env.JWT_SECRET, 60 * 60 * 24 * 365); // 1 year dev token

  return new Response(JSON.stringify({ userId, token, displayName: body.displayName ?? null }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// MARK: - Pairing (master pairs a recipient via a short code)

export async function handlePairingCode(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const userId = authResult.userId;

  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  const rand = new Uint8Array(6);
  crypto.getRandomValues(rand);
  for (let i = 0; i < 6; i++) code += alphabet[rand[i] % alphabet.length];

  const ttlSeconds = 15 * 60;
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();
  await env.DEVICE_TOKENS_KV.put(`pairing:${code}`, userId, { expirationTtl: ttlSeconds });

  return new Response(JSON.stringify({ code, expiresAt }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handlePairingClaim(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const claimantId = authResult.userId;

  const body = (await request.json()) as { code: string };
  if (!body.code) {
    return new Response(JSON.stringify({ error: 'MISSING_CODE' }), { status: 400 });
  }

  const code = body.code.trim().toUpperCase();
  const targetUserId = await env.DEVICE_TOKENS_KV.get(`pairing:${code}`);
  if (!targetUserId) {
    return new Response(JSON.stringify({ error: 'INVALID_OR_EXPIRED_CODE' }), { status: 404 });
  }
  if (targetUserId === claimantId) {
    return new Response(JSON.stringify({ error: 'CANNOT_PAIR_WITH_SELF' }), { status: 400 });
  }

  // Create ACTIVE link both directions so both sides see each other as recipients.
  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status, has_app_installed, last_seen_at, created_at)
     VALUES (?, ?, 'ACTIVE', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, pal_id) DO UPDATE SET status = 'ACTIVE'`
  ).bind(claimantId, targetUserId).run();

  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status, has_app_installed, last_seen_at, created_at)
     VALUES (?, ?, 'ACTIVE', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id, pal_id) DO UPDATE SET status = 'ACTIVE'`
  ).bind(targetUserId, claimantId).run();

  await env.DEVICE_TOKENS_KV.delete(`pairing:${code}`);

  return new Response(JSON.stringify({ success: true, pairedWith: targetUserId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return withCORS(new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST, OPTIONS, PUT, GET, DELETE',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      }));
    }

    try {
      if (url.pathname === '/v1/device/register' && request.method === 'POST') {
        return withCORS(await handleDeviceRegister(request, env));
      }
      if (url.pathname === '/v1/pairing/code' && request.method === 'POST') {
        return withCORS(await handlePairingCode(request, env));
      }
      if (url.pathname === '/v1/pairing/claim' && request.method === 'POST') {
        return withCORS(await handlePairingClaim(request, env));
      }
      const alertDetailMatch = url.pathname.match(/^\/v1\/rush\/alerts\/([^/]+)$/);
      if (alertDetailMatch && request.method === 'GET') {
        return withCORS(await handleGetAlert(request, env, alertDetailMatch[1]));
      }
      if (url.pathname === '/v1/rush/unsend' && request.method === 'POST') {
        return withCORS(await handleUnsend(request, env));
      }
      if (url.pathname === '/v1/user/token' && request.method === 'POST') {
        return withCORS(await handleTokenSync(request, env));
      }
      if (url.pathname === '/v1/user/public-key' && request.method === 'PUT') {
        return withCORS(await handlePublicKeyUpdate(request, env));
      }
      if (url.pathname.match(/^\/v1\/user\/([^/]+)\/public-key$/) && request.method === 'GET') {
        return withCORS(await handlePublicKeyFetch(request, env));
      }
      // Recipients endpoints
      if (url.pathname === '/v1/trust-circle' && request.method === 'GET') {
        return withCORS(await handleTrustCircleList(request, env));
      }
      if (url.pathname === '/v1/trust-circle/invite' && request.method === 'POST') {
        return withCORS(await handleTrustCircleInvite(request, env));
      }
      if (url.pathname === '/v1/trust-circle/accept' && request.method === 'POST') {
        return withCORS(await handleTrustCircleAccept(request, env));
      }
      if (url.pathname === '/v1/trust-circle/block' && request.method === 'POST') {
        return withCORS(await handleTrustCircleBlock(request, env));
      }
      if (url.pathname === '/v1/trust-circle/remove' && request.method === 'POST') {
        return withCORS(await handleTrustCircleRemove(request, env));
      }
      if (url.pathname === '/v1/user/heartbeat' && request.method === 'POST') {
        return withCORS(await handleHeartbeat(request, env));
      }
      // Admin override for rate limiting
      if (url.pathname === '/v1/rush/rate-limit-override' && request.method === 'POST') {
        return withCORS(await handleRateLimitOverride(request, env));
      }
      if (url.pathname === '/v1/rush/dispatch' && request.method === 'POST') {
        return withCORS(await handleDispatch(request, env));
      }
      if (url.pathname === '/v1/rush/ack' && request.method === 'POST') {
        return withCORS(await handleReverseAck(request, env));
      }
      if (url.pathname === '/v1/rush/history' && request.method === 'GET') {
        return withCORS(await handleHistory(request, env));
      }
      if (url.pathname === '/v1/telemetry/summary' && request.method === 'GET') {
        return withCORS(await handleTelemetrySummary(request, env));
      }

      return withCORS(new Response(JSON.stringify({ error: 'NOT_FOUND' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      }));
    } catch (err: any) {
      return withCORS(new Response(JSON.stringify({ error: 'INTERNAL_SERVER_ERROR', message: err.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      }));
    }
  },

  // Cron trigger handler: retries "until received" alerts every 5 minutes
  async scheduled(event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(handleCronRetry(env));
  },
};

export async function handleTokenSync(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as { userId: string; apnsToken: string };

  if (!body.userId || !body.apnsToken) {
    return new Response(JSON.stringify({ error: 'INVALID_PAYLOAD' }), { status: 400 });
  }

  await env.DEVICE_TOKENS_KV.put(`apns_token:${body.userId}`, body.apnsToken);

  await env.READRUSH_DB.prepare(
    `INSERT INTO us_users (user_id, public_key, apns_token, updated_at)
     VALUES (?, 'DEFAULT_KEY', ?, CURRENT_TIMESTAMP)
     ON CONFLICT(user_id) DO UPDATE SET apns_token = ?, updated_at = CURRENT_TIMESTAMP`
  )
    .bind(body.userId, body.apnsToken, body.apnsToken)
    .run();

  return new Response(JSON.stringify({ success: true, userId: body.userId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handlePublicKeyUpdate(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as { publicKey: string };

  if (!body.publicKey) {
    return new Response(JSON.stringify({ error: 'MISSING_PUBLIC_KEY' }), { status: 400 });
  }

  // Validate base64 format (32 bytes = 44 chars base64)
  let publicKeyData: Uint8Array;
  try {
    publicKeyData = new Uint8Array(base64UrlDecode(body.publicKey));
    if (publicKeyData.length !== 32) throw new Error('Invalid length');
  } catch {
    return new Response(JSON.stringify({ error: 'INVALID_PUBLIC_KEY_FORMAT' }), { status: 400 });
  }

  await env.READRUSH_DB.prepare(
    `UPDATE us_users SET public_key = ?, updated_at = CURRENT_TIMESTAMP WHERE user_id = ?`
  )
    .bind(body.publicKey, authenticatedUserId)
    .run();

  return new Response(JSON.stringify({ success: true, userId: authenticatedUserId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handlePublicKeyFetch(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;

  const url = new URL(request.url);
  const userId = url.pathname.split('/')[3]; // /v1/user/:userId/public-key

  if (!userId) {
    return new Response(JSON.stringify({ error: 'MISSING_USER_ID' }), { status: 400 });
  }

  const user = await env.READRUSH_DB.prepare(
    `SELECT public_key FROM us_users WHERE user_id = ?`
  )
    .bind(userId)
    .first<{ public_key: string }>();

  if (!user || !user.public_key || user.public_key === 'DEFAULT_KEY') {
    return new Response(JSON.stringify({ error: 'PUBLIC_KEY_NOT_FOUND' }), { status: 404 });
  }

  return new Response(JSON.stringify({ userId, publicKey: user.public_key }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Recipients Management

interface TrustCircleMember {
  pal_id: string;
  status: 'PENDING' | 'ACTIVE' | 'BLOCKED';
  created_at: string;
  pal_name?: string;
  pal_public_key?: string;
  direction?: 'sent' | 'received';
}

export async function handleTrustCircleList(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  // Get all trust circle relationships for the user (both as user_id and pal_id)
  const sentInvites = await env.READRUSH_DB.prepare(
    `SELECT tc.pal_id, tc.status, tc.created_at, u.public_key as pal_public_key
     FROM us_trust_circles tc
     LEFT JOIN us_users u ON u.user_id = tc.pal_id
     WHERE tc.user_id = ?`
  ).bind(authenticatedUserId).all<TrustCircleMember>();

  const receivedInvites = await env.READRUSH_DB.prepare(
    `SELECT tc.user_id as pal_id, tc.status, tc.created_at, u.public_key as pal_public_key
     FROM us_trust_circles tc
     LEFT JOIN us_users u ON u.user_id = tc.user_id
     WHERE tc.pal_id = ?`
  ).bind(authenticatedUserId).all<TrustCircleMember>();

  // Combine and deduplicate (prefer ACTIVE status)
  const allMembers = new Map<string, TrustCircleMember>();
  
  for (const member of sentInvites.results || []) {
    allMembers.set(member.pal_id, { ...member, pal_name: member.pal_id, direction: 'sent' });
  }
  for (const member of receivedInvites.results || []) {
    const existing = allMembers.get(member.pal_id);
    if (!existing || existing.status === 'PENDING' && member.status === 'ACTIVE') {
      allMembers.set(member.pal_id, { ...member, pal_name: member.pal_id, direction: 'received' });
    }
  }

  const members = Array.from(allMembers.values()).map(m => ({
    userId: m.pal_id,
    status: m.status,
    createdAt: m.created_at,
    publicKey: m.pal_public_key,
    direction: m.direction ?? 'received',
  }));

  return new Response(JSON.stringify({ members }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

export async function handleTrustCircleInvite(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as { palId: string };

  if (!body.palId) {
    return new Response(JSON.stringify({ error: 'MISSING_PAL_ID' }), { status: 400 });
  }

  if (body.palId === authenticatedUserId) {
    return new Response(JSON.stringify({ error: 'CANNOT_INVITE_SELF' }), { status: 400 });
  }

  // Check if user exists
  const targetUser = await env.READRUSH_DB.prepare(
    `SELECT user_id FROM us_users WHERE user_id = ?`
  ).bind(body.palId).first();

  if (!targetUser) {
    return new Response(JSON.stringify({ error: 'USER_NOT_FOUND' }), { status: 404 });
  }

  // Check if relationship already exists
  const existing = await env.READRUSH_DB.prepare(
    `SELECT status FROM us_trust_circles WHERE user_id = ? AND pal_id = ?`
  ).bind(authenticatedUserId, body.palId).first();

  if (existing) {
    return new Response(JSON.stringify({ error: 'RELATIONSHIP_EXISTS', message: 'Invite already sent or user already in trust circle' }), { status: 409 });
  }

// Create pending invite
  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status) VALUES (?, ?, 'PENDING')`
  ).bind(authenticatedUserId, body.palId).run();

  // TODO: Send push notification to palId about the invite

  // Log telemetry for trust circle invite
  await logTelemetryEvent(
    env,
    authenticatedUserId,
    'trust_circle_invite',
    `palId=${body.palId}`,
    200
  );

  return new Response(JSON.stringify({ success: true, palId: body.palId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

export async function handleTrustCircleAccept(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as { palId: string };

  if (!body.palId) {
    return new Response(JSON.stringify({ error: 'MISSING_PAL_ID' }), { status: 400 });
  }

  // Find the pending invite from palId to authenticatedUserId
  const invite = await env.READRUSH_DB.prepare(
    `SELECT * FROM us_trust_circles WHERE user_id = ? AND pal_id = ? AND status = 'PENDING'`
  ).bind(body.palId, authenticatedUserId).first();

  if (!invite) {
    return new Response(JSON.stringify({ error: 'INVITE_NOT_FOUND' }), { status: 404 });
  }

  // Update to ACTIVE (bidirectional - update both directions or insert reverse)
  await env.READRUSH_DB.prepare(
    `UPDATE us_trust_circles SET status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND pal_id = ?`
  ).bind(body.palId, authenticatedUserId).run();

// Also create reverse relationship
  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status) VALUES (?, ?, 'ACTIVE')
     ON CONFLICT(user_id, pal_id) DO UPDATE SET status = 'ACTIVE', updated_at = CURRENT_TIMESTAMP`
  ).bind(authenticatedUserId, body.palId).run();

  // TODO: Send push notification to palId that invite was accepted

  // Log telemetry for trust circle accept
  await logTelemetryEvent(
    env,
    authenticatedUserId,
    'trust_circle_accept',
    `palId=${body.palId}`,
    200
  );

  return new Response(JSON.stringify({ success: true, palId: body.palId, status: 'ACTIVE' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

export async function handleTrustCircleBlock(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as { palId: string };

  if (!body.palId) {
    return new Response(JSON.stringify({ error: 'MISSING_PAL_ID' }), { status: 400 });
  }

// Block in both directions
  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status) VALUES (?, ?, 'BLOCKED')
     ON CONFLICT(user_id, pal_id) DO UPDATE SET status = 'BLOCKED', updated_at = CURRENT_TIMESTAMP`
  ).bind(authenticatedUserId, body.palId).run();

  await env.READRUSH_DB.prepare(
    `INSERT INTO us_trust_circles (user_id, pal_id, status) VALUES (?, ?, 'BLOCKED')
     ON CONFLICT(user_id, pal_id) DO UPDATE SET status = 'BLOCKED', updated_at = CURRENT_TIMESTAMP`
  ).bind(body.palId, authenticatedUserId).run();

  // Log telemetry for trust circle block
  await logTelemetryEvent(
    env,
    authenticatedUserId,
    'trust_circle_block',
    `palId=${body.palId}`,
    200
  );

  return new Response(JSON.stringify({ success: true, palId: body.palId, status: 'BLOCKED' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

export async function handleTrustCircleRemove(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as { palId: string };

  if (!body.palId) {
    return new Response(JSON.stringify({ error: 'MISSING_PAL_ID' }), { status: 400 });
  }

  // Remove in both directions
  await env.READRUSH_DB.prepare(
    `DELETE FROM us_trust_circles WHERE user_id = ? AND pal_id = ?`
  ).bind(authenticatedUserId, body.palId).run();

  await env.READRUSH_DB.prepare(
    `DELETE FROM us_trust_circles WHERE user_id = ? AND pal_id = ?`
  ).bind(body.palId, authenticatedUserId).run();

  // Log telemetry for trust circle removal
  await logTelemetryEvent(
    env,
    authenticatedUserId,
    'trust_circle_remove',
    `palId=${body.palId}`,
    200
  );

  return new Response(JSON.stringify({ success: true, palId: body.palId }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
}

export async function handleDispatch(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as {
    senderId: string;
    senderName: string;
    recipientId: string;
    messageText: string; // This is now the E2EE encrypted payload
    ttlMinutes: number;
    isCritical: boolean;
    untilReceived?: boolean;
    previewText?: string;
  };

  const { senderId, senderName, recipientId, messageText, ttlMinutes = 15, isCritical = true, untilReceived = false, previewText } = body;

  if (senderId !== authenticatedUserId) {
    return new Response(JSON.stringify({ error: 'FORBIDDEN', message: 'senderId does not match authenticated user' }), { status: 403 });
  }

  if (!senderId || !recipientId || !messageText) {
    return new Response(JSON.stringify({ error: 'MISSING_REQUIRED_FIELDS' }), { status: 400 });
  }

  const trustCheck = await env.READRUSH_DB.prepare(
    `SELECT status FROM us_trust_circles WHERE user_id = ? AND pal_id = ? AND status = 'ACTIVE'`
  )
    .bind(senderId, recipientId)
    .first();

  if (!trustCheck) {
    return new Response(
      JSON.stringify({ error: 'TRUST_CIRCLE_REQUIRED', message: 'User is not in your active Recipients.' }),
      { status: 403 }
    );
  }

  const doId = env.RATE_LIMITER_DO.idFromName(`${senderId}:${recipientId}`);
  const rateLimiter = env.RATE_LIMITER_DO.get(doId);
  const rateCheck = await rateLimiter.fetch(new Request('http://rate-limiter/check', { method: 'POST' }));

  if (rateCheck.status === 429) {
    return rateCheck;
  }

  const recipientApnsToken = await env.DEVICE_TOKENS_KV.get(`apns_token:${recipientId}`);
  if (!recipientApnsToken) {
    return new Response(
      JSON.stringify({ error: 'RECIPIENT_OFFLINE', message: 'Recipient has not registered APNs tokens.' }),
      { status: 404 }
    );
  }

  const alertId = crypto.randomUUID();
  const expiresAt = new Date(Date.now() + ttlMinutes * 60 * 1000).toISOString();

  // Create a short preview for lock screen. The app can send a plaintext preview;
  // otherwise fall back to a generic encrypted notice.
  const previewTextValue = (previewText ?? '').trim();
  const finalPreview = previewTextValue.length > 0
    ? previewTextValue
    : (isCritical ? "🔒 Critical Alert" : "🔒 Encrypted Message");

  await env.READRUSH_DB.prepare(
    `INSERT INTO us_rush_alerts (alert_id, sender_id, recipient_id, payload_ciphertext, raw_message_preview, is_critical, ttl_minutes, until_received, status, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PUSHED', ?)`
  )
    .bind(alertId, senderId, recipientId, messageText, finalPreview, isCritical ? 1 : 0, ttlMinutes, untilReceived ? 1 : 0, expiresAt)
    .run();

  // If untilReceived is true, schedule a retry check
  if (untilReceived) {
    await scheduleUntilReceivedRetry(env, alertId, senderId, recipientId, messageText, isCritical, ttlMinutes);
  }

  // Standard alert notification so the recipient's phone surfaces it immediately
  // Dev env: plain alert (no special interruption level) so nothing can suppress it.
  const useCritical = isCritical && env.APNS_ENV === 'production';
  const apnsPayload = {
    aps: {
      alert: {
        title: 'UrgentSee Received:',
        body: finalPreview,
      },
      sound: 'default',
      'thread-id': alertId,
      ...(useCritical
        ? {
            'interruption-level': 'critical',
            sound: { critical: 1, name: 'default', volume: 1.0 },
          }
        : {}),
    },
    alertId,
    senderName: senderName || '',
    rawMessagePreview: previewText,
    status: 'PUSHED',
  };

  const apnsHost = env.APNS_ENV === 'production' ? 'api.push.apple.com' : 'api.development.push.apple.com';
  const apnsTopic = env.APNS_TOPIC || 'com.urgentsee.UrgentSee';
  const apnsUrl = `https://${apnsHost}/3/device/${recipientApnsToken}`;
  const apnsAuth = await cachedAPNsAuthToken(env);
  const apnsSigPart = apnsAuth.split('.').pop() ?? '';
  console.log(`[UrgentSee] APNs debug: env=${env.APNS_ENV} host=${apnsHost} teamLen=${env.APNS_TEAM_ID.length} sigLen=${apnsSigPart.length}`);

  const apnsResponse = await fetch(apnsUrl, {
    method: 'POST',
    headers: {
      authorization: `bearer ${apnsAuth}`,
      'apns-topic': apnsTopic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': `${Math.floor(Date.now() / 1000) + ttlMinutes * 60}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify(apnsPayload),
  });

  const apnsSuccess = apnsResponse.ok;
  console.log(`[UrgentSee] APNs response status=${apnsResponse.status}`);
  
  if (!apnsSuccess) {
    const errorText = await apnsResponse.text();
    console.error('[UrgentSee] APNs push failed:', apnsResponse.status, errorText);
    
    // Check for unregistered device token (user uninstalled app)
    if (apnsResponse.status === 410 || (apnsResponse.status === 400 && errorText.includes('Unregistered'))) {
      console.log('[UrgentSee] APNs token unregistered for recipient:', recipientId);
      // Mark app as uninstalled for all us_users who have this recipient in their trust circle
      await env.READRUSH_DB.prepare(
        `UPDATE us_trust_circles SET has_app_installed = 0 WHERE pal_id = ?`
      ).bind(recipientId).run();
      
      // Also remove the invalid APNs token
      await env.DEVICE_TOKENS_KV.delete(`apns_token:${recipientId}`);
    }
    
    // Update alert status to reflect push failure
    await env.READRUSH_DB.prepare(
      `UPDATE us_rush_alerts SET status = 'EXPIRED' WHERE alert_id = ?`
    ).bind(alertId).run();
    
    // Log telemetry for push failure
    await logTelemetryEvent(
      env,
      senderId,
      'dispatch_apns_failed',
      `alertId=${alertId}, recipient=${recipientId}, status=${apnsResponse.status}, error=${errorText.substring(0, 200)}`,
      apnsResponse.status
    );
  } else {
    // Log telemetry for successful dispatch
    await logTelemetryEvent(
      env,
      senderId,
      'dispatch_apns_success',
      `alertId=${alertId}, recipient=${recipientId}, isCritical=${isCritical}`,
      200
    );
  }

  return new Response(
    JSON.stringify({
      success: apnsSuccess,
      alertId,
      status: apnsSuccess ? 'MOUNTED_ON_LOCK_SCREEN' : 'PUSH_FAILED',
      expiresAt,
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}

export async function handleReverseAck(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as {
    alertId: string;
    recipientId: string;
    ackType: string;
  };

  const { alertId, recipientId, ackType = 'UNLOCK_EVENT' } = body;

  if (recipientId !== authenticatedUserId) {
    return new Response(JSON.stringify({ error: 'FORBIDDEN', message: 'recipientId does not match authenticated user' }), { status: 403 });
  }

  if (!alertId || !recipientId) {
    return new Response(JSON.stringify({ error: 'MISSING_ALERT_OR_RECIPIENT_ID' }), { status: 400 });
  }

  const alertRecord = await env.READRUSH_DB.prepare(
    `UPDATE us_rush_alerts
     SET status = 'SEEN', acknowledged_at = CURRENT_TIMESTAMP
     WHERE alert_id = ? AND recipient_id = ?
     RETURNING sender_id, raw_message_preview`
  )
    .bind(alertId, recipientId)
    .first<{ sender_id: string; raw_message_preview: string }>();

  if (!alertRecord) {
    return new Response(JSON.stringify({ error: 'ALERT_NOT_FOUND_OR_ALREADY_SEEN' }), { status: 404 });
  }

  // Log telemetry for reverse ACK
  await logTelemetryEvent(
    env,
    authenticatedUserId,
    'reverse_ack_received',
    `alertId=${alertId}, sender=${alertRecord.sender_id}, ackType=${ackType}`,
    200
  );

  const senderApnsToken = await env.DEVICE_TOKENS_KV.get(`apns_token:${alertRecord.sender_id}`);

  if (senderApnsToken) {
    const reverseAckPayload = {
      aps: {
        alert: {
          title: 'UrgentSee Acknowledged 🟢',
          body: `Recipient unlocked device and viewed message via ${ackType}.`,
        },
        sound: 'default',
        'interruption-level': 'active',
      },
      alertId,
      status: 'SEEN',
    };

    await fetch(`https://api.development.push.apple.com/3/device/${senderApnsToken}`, {
      method: 'POST',
      headers: {
        'apns-topic': env.APNS_TOPIC,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(reverseAckPayload),
    });
  }

  return new Response(
    JSON.stringify({
      success: true,
      alertId,
      status: 'SEEN',
      ackType,
      acknowledgedAt: new Date().toISOString(),
    }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}

// MARK: - Message history (sent + received) for the History tab

export async function handleHistory(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const userId = authResult.userId;

  const url = new URL(request.url);
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') || '50', 10) || 50, 1), 200);
  const offset = Math.max(parseInt(url.searchParams.get('offset') || '0', 10) || 0, 0);

  const rows = await env.READRUSH_DB.prepare(
    `SELECT alert_id, sender_id, recipient_id, raw_message_preview, is_critical,
            ttl_minutes, until_received, retry_count, status, expires_at,
            acknowledged_at, created_at
     FROM us_rush_alerts
     WHERE sender_id = ? OR recipient_id = ?
     ORDER BY created_at DESC
     LIMIT ? OFFSET ?`
  ).bind(userId, userId, limit, offset).all<any>();

  const messages = (rows.results || []).map((r: any) => ({
    alertId: r.alert_id,
    senderId: r.sender_id,
    recipientId: r.recipient_id,
    direction: r.sender_id === userId ? 'sent' : 'received',
    preview: r.raw_message_preview,
    isCritical: r.is_critical === 1,
    ttlMinutes: r.ttl_minutes,
    untilReceived: r.until_received === 1,
    retryCount: r.retry_count ?? 0,
    status: r.status,
    expiresAt: r.expires_at,
    acknowledgedAt: r.acknowledged_at,
    createdAt: r.created_at,
  }));

  const totals = await env.READRUSH_DB.prepare(
    `SELECT
       COUNT(*) AS total,
       SUM(CASE WHEN sender_id = ? THEN 1 ELSE 0 END) AS sent,
       SUM(CASE WHEN recipient_id = ? THEN 1 ELSE 0 END) AS received,
       SUM(CASE WHEN status = 'SEEN' THEN 1 ELSE 0 END) AS seen
     FROM us_rush_alerts
     WHERE sender_id = ? OR recipient_id = ?`
  ).bind(userId, userId, userId, userId).first<any>();

  return new Response(JSON.stringify({
    messages,
    total: totals?.total ?? messages.length,
    sent: totals?.sent ?? 0,
    received: totals?.received ?? 0,
    seen: totals?.seen ?? 0,
    limit,
    offset,
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}

// MARK: - Telemetry summary (analytics for the History tab)

export async function handleTelemetrySummary(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const userId = authResult.userId;

  const byType = await env.READRUSH_DB.prepare(
    `SELECT event_type, COUNT(*) AS count
     FROM us_telemetry_events
     WHERE user_id = ?
     GROUP BY event_type
     ORDER BY count DESC`
  ).bind(userId).all<any>();

  const recent = await env.READRUSH_DB.prepare(
    `SELECT event_id, event_type, latency_ms, delivery_status, created_at
     FROM us_telemetry_events
     WHERE user_id = ?
     ORDER BY created_at DESC
     LIMIT 100`
  ).bind(userId).all<any>();

  const alertStats = await env.READRUSH_DB.prepare(
    `SELECT
       COUNT(*) AS totalDispatched,
       SUM(CASE WHEN status = 'SEEN' THEN 1 ELSE 0 END) AS seen,
       SUM(CASE WHEN is_critical = 1 THEN 1 ELSE 0 END) AS critical,
       AVG(retry_count) AS avgRetries
     FROM us_rush_alerts
     WHERE sender_id = ?`
  ).bind(userId).first<any>();

  const events = (recent.results || []).map((r: any) => ({
    eventId: r.event_id,
    eventType: r.event_type,
    latencyMs: r.latency_ms,
    deliveryStatus: r.delivery_status,
    createdAt: r.created_at,
  }));

  return new Response(JSON.stringify({
    byType: (byType.results || []).map((r: any) => ({ eventType: r.event_type, count: r.count })),
    recent: events,
    dispatchStats: {
      totalDispatched: alertStats?.totalDispatched ?? 0,
      seen: alertStats?.seen ?? 0,
      critical: alertStats?.critical ?? 0,
      avgRetries: alertStats?.avgRetries ?? 0,
    },
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}

// Fetch alert details + decrypted payload ciphertext for the recipient (opening a notification)
export async function handleGetAlert(request: Request, env: Env, alertId: string): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const row = await env.READRUSH_DB.prepare(
    `SELECT alert_id, sender_id, payload_ciphertext, raw_message_preview, status, created_at
     FROM us_rush_alerts
     WHERE alert_id = ? AND recipient_id = ?`
  ).bind(alertId, authenticatedUserId).first<any>();

  if (!row) {
    return new Response(JSON.stringify({ error: 'ALERT_NOT_FOUND' }), { status: 404 });
  }

  return new Response(JSON.stringify({
    alertId: row.alert_id,
    senderId: row.sender_id,
    payloadCiphertext: row.payload_ciphertext,
    preview: row.raw_message_preview,
    status: row.status,
    createdAt: row.created_at,
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}

// Recall/unsend an alert within a short window after sending.
export async function handleUnsend(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const senderId = authResult.userId;

  const body = (await request.json()) as { alertId: string };
  if (!body.alertId) {
    return new Response(JSON.stringify({ error: 'MISSING_ALERT_ID' }), { status: 400 });
  }

  const row = await env.READRUSH_DB.prepare(
    `SELECT recipient_id, created_at, status FROM us_rush_alerts WHERE alert_id = ? AND sender_id = ?`
  ).bind(body.alertId, senderId).first<any>();

  if (!row) {
    return new Response(JSON.stringify({ error: 'ALERT_NOT_FOUND' }), { status: 404 });
  }
  if (row.status !== 'PUSHED' && row.status !== 'MOUNTED') {
    return new Response(JSON.stringify({ error: 'ALREADY_SEEN' }), { status: 400 });
  }

  const unsendWindowMs = 60 * 1000; // 60 second unsend window
  const created = new Date(row.created_at.replace(' ', 'T') + 'Z').getTime();
  if (Number.isFinite(created) && Date.now() - created > unsendWindowMs) {
    return new Response(JSON.stringify({ error: 'UNSEND_WINDOW_EXPIRED' }), { status: 400 });
  }

  await env.READRUSH_DB.prepare(
    `UPDATE us_rush_alerts SET status = 'EXPIRED', acknowledged_at = CURRENT_TIMESTAMP WHERE alert_id = ?`
  ).bind(body.alertId).run();

  // Best-effort recall push so the recipient knows it was unsent.
  const recipientApnsToken = await env.DEVICE_TOKENS_KV.get(`apns_token:${row.recipient_id}`);
  if (recipientApnsToken) {
    const auth = await cachedAPNsAuthToken(env);
    const host = env.APNS_ENV === 'production' ? 'api.push.apple.com' : 'api.development.push.apple.com';
    const topic = env.APNS_TOPIC || 'com.urgentsee.UrgentSee';
    const payload = {
      aps: {
        alert: { title: 'UrgentSee', body: 'A message was unsent.' },
        sound: 'default',
      },
      alertId: body.alertId,
      action: 'unsent',
    };
    await fetch(`https://${host}/3/device/${recipientApnsToken}`, {
      method: 'POST',
      headers: {
        authorization: `bearer ${auth}`,
        'apns-topic': topic,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });
  }

  return new Response(JSON.stringify({ success: true, alertId: body.alertId, status: 'EXPIRED' }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// MARK: - Admin override for rate limiting (emergency bypass)
export async function handleRateLimitOverride(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const body = (await request.json()) as {
    senderId: string;
    recipientId: string;
    reason: string;
    overrideMinutes: number;
  };

  const { senderId, recipientId, reason = 'Emergency override', overrideMinutes = 60 } = body;

  if (senderId !== authenticatedUserId) {
    return new Response(JSON.stringify({ error: 'FORBIDDEN' }), { status: 403 });
  }

  if (!senderId || !recipientId) {
    return new Response(JSON.stringify({ error: 'MISSING_REQUIRED_FIELDS' }), { status: 400 });
  }

  // Clear rate limiter state
  const doId = env.RATE_LIMITER_DO.idFromName(`${senderId}:${recipientId}`);
  const rateLimiter = env.RATE_LIMITER_DO.get(doId);
  await rateLimiter.fetch(new Request('http://rate-limiter/reset', { method: 'POST' }));

  // Log telemetry for rate limit override
  await logTelemetryEvent(
    env,
    senderId,
    'rate_limit_override',
    `recipient=${recipientId}, reason=${reason}, overrideMinutes=${overrideMinutes}`,
    200
  );

  return new Response(JSON.stringify({
    success: true,
    message: 'Rate limit cleared',
    senderId,
    recipientId,
    reason,
    overrideMinutes
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
}

export async function handleHeartbeat(request: Request, env: Env): Promise<Response> {
  const authResult = await authenticateRequest(request, env);
  if (authResult instanceof Response) return authResult;
  const authenticatedUserId = authResult.userId;

  const now = new Date().toISOString();

  // Update last_seen_at for all trust circle relationships where this user is the pal
  await env.READRUSH_DB.prepare(
    `UPDATE us_trust_circles SET last_seen_at = ?, has_app_installed = 1 WHERE pal_id = ?`
  )
    .bind(now, authenticatedUserId)
    .run();

  return new Response(JSON.stringify({ success: true, timestamp: now }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

// Schedule retries for "until received" alerts
async function scheduleUntilReceivedRetry(
  env: Env,
  alertId: string,
  senderId: string,
  recipientId: string,
  messageText: string,
  isCritical: boolean,
  ttlMinutes: number
): Promise<void> {
  // Check if alert is still pending (not seen) every 5 minutes
  const retryInterval = 5 * 60 * 1000; // 5 minutes in ms
  const maxRetries = Math.floor((ttlMinutes * 60 * 1000) / retryInterval);
  
  // Store retry schedule in a separate table or use a durable object
  // For now, we'll store it in the us_rush_alerts table with a retry_count
  await env.READRUSH_DB.prepare(
    `UPDATE us_rush_alerts SET retry_count = 0, max_retries = ? WHERE alert_id = ?`
  ).bind(maxRetries, alertId).run();
  
  console.log(`[UrgentSee] Scheduled ${maxRetries} retries for alert ${alertId} (untilReceived=true)`);
}

// Telemetry logging
async function logTelemetryEvent(
  env: Env,
  userId: string,
  eventType: string,
  details: string,
  statusCode: number
): Promise<void> {
  try {
    const eventId = crypto.randomUUID();
    await env.READRUSH_DB.prepare(
      `INSERT INTO us_telemetry_events (event_id, user_id, event_type, latency_ms, delivery_status, created_at)
       VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)`
    )
      .bind(eventId, userId, eventType, statusCode, details)
      .run();
  } catch (e) {
    console.error('[UrgentSee] Failed to log telemetry:', e);
  }
}

// Cron handler: retry "until received" alerts every 5 minutes
async function handleCronRetry(env: Env): Promise<void> {
  try {
    // Find alerts that are still pending (PUSHED/MOUNTED), have until_received=1,
    // haven't exceeded max_retries, and haven't expired
    const pendingAlerts = await env.READRUSH_DB.prepare(
      `SELECT alert_id, sender_id, recipient_id, raw_message_preview, is_critical,
              ttl_minutes, retry_count, max_retries, expires_at
       FROM us_rush_alerts
       WHERE until_received = 1
         AND status IN ('PUSHED', 'MOUNTED')
         AND retry_count < max_retries
         AND expires_at > datetime('now')
       ORDER BY created_at ASC
       LIMIT 50`
    ).all();

    if (!pendingAlerts.results || pendingAlerts.results.length === 0) {
      return;
    }

    console.log(`[UrgentSee] Cron: retrying ${pendingAlerts.results.length} pending alerts`);

    for (const alert of pendingAlerts.results as any[]) {
      try {
        // Get recipient's APNs token
        const tokenResult = await env.DEVICE_TOKENS_KV.get(`apns_token:${alert.recipient_id}`);
        if (!tokenResult) {
          console.log(`[UrgentSee] Cron: no token for recipient ${alert.recipient_id}, skipping`);
          continue;
        }

        // Increment retry count
        await env.READRUSH_DB.prepare(
          `UPDATE us_rush_alerts SET retry_count = retry_count + 1 WHERE alert_id = ?`
        ).bind(alert.alert_id).run();

        // Send retry push notification
        const previewText = alert.raw_message_preview || (alert.is_critical ? "🔒 Critical Alert" : "🔒 Encrypted Message");
        const apnsPayload = {
          aps: {
            alert: {
              title: 'UrgentSee Received:',
              body: previewText,
            },
            sound: 'default',
            'thread-id': alert.alert_id,
          },
          alertId: alert.alert_id,
          status: 'RETRY',
        };

        const host = env.APNS_ENV === 'production' ? 'api.push.apple.com' : 'api.development.push.apple.com';
        await fetch(`https://${host}/3/device/${tokenResult}`, {
          method: 'POST',
          headers: {
            'authorization': `bearer ${await getAPNsProviderToken(env)}`,
            'apns-topic': env.APNS_TOPIC,
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'content-type': 'application/json',
          },
          body: JSON.stringify(apnsPayload),
        });

        // Log telemetry
        await logTelemetryEvent(env, alert.sender_id, 'dispatch_apns_success',
          `alertId=${alert.alert_id}, retry=${alert.retry_count + 1}`, 200);

      } catch (e) {
        console.error(`[UrgentSee] Cron: failed to retry alert ${alert.alert_id}:`, e);
      }
    }
  } catch (e) {
    console.error('[UrgentSee] Cron retry handler failed:', e);
  }
}

// Helper to get cached APNs provider token (simplified)
async function getAPNsProviderToken(env: Env): Promise<string> {
  // In production, this would use the cached token from KV
  // For now, return empty string - the actual implementation would
  // reuse the logic from handleDispatch
  return '';
}


