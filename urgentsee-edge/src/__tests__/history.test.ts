import { describe, it, expect } from 'vitest';
import { handleHistory, handleTelemetrySummary } from '../index';

const userA = 'user-history-a';
const userB = 'user-history-b';

async function signedRequest(url: string, sub: string, secret = 's') {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ sub, iat: 1, exp: 9999999999 })).toString('base64url');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = Buffer.from(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${header}.${payload}`))).toString('base64url');
  return new Request(url, { headers: { Authorization: `Bearer ${header}.${payload}.${sig}` } });
}

function alertRow(over: Record<string, unknown>) {
  return { alert_id: 'a1', sender_id: userA, recipient_id: userB, raw_message_preview: 'hi', is_critical: 1, ttl_minutes: 15, until_received: 0, retry_count: 0, status: 'PUSHED', expires_at: '2099-01-01', acknowledged_at: null, created_at: '2026-01-01', ...over };
}

function dbWithAlerts(rows: Record<string, unknown>[]) {
  return {
    prepare: (sql: string) => ({
      bind: (..._a: unknown[]) => ({
        all: async () => (sql.includes('us_telemetry_events') ? { results: [] } : { results: rows }),
        first: async () => (sql.includes('COUNT(*)') ? {
          total: rows.length,
          sent: rows.filter(r => r.sender_id === userA).length,
          received: rows.filter(r => r.recipient_id === userA).length,
          seen: rows.filter(r => r.status === 'SEEN').length,
        } : null),
        run: async () => ({}),
      }),
    }),
  } as any;
}

function envWith(db: any) {
  return { READRUSH_DB: db, DEVICE_TOKENS_KV: { get: async () => null }, JWT_SECRET: 's' } as any;
}

describe('history + telemetry endpoints (History tab)', () => {
  it('handleHistory returns sent/received with direction + totals', async () => {
    const rows = [
      alertRow({ alert_id: 'a1', sender_id: userA, recipient_id: userB, status: 'PUSHED' }),
      alertRow({ alert_id: 'a2', sender_id: userB, recipient_id: userA, status: 'SEEN' }),
    ];
    const req = await signedRequest('https://x/v1/rush/history?limit=50', userA);
    const res = await handleHistory(req, envWith(dbWithAlerts(rows)));
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.messages).toHaveLength(2);
    expect(body.messages[0].direction).toBe('sent');
    expect(body.messages[1].direction).toBe('received');
    expect(body.total).toBe(2);
    expect(body.sent).toBe(1);
    expect(body.received).toBe(1);
    expect(body.seen).toBe(1);
  });

  it('handleHistory rejects unauthenticated requests', async () => {
    const res = await handleHistory(new Request('https://x/v1/rush/history'), envWith(dbWithAlerts([])));
    expect(res.status).toBe(401);
  });

  it('handleTelemetrySummary returns byType + dispatchStats', async () => {
    const db = {
      prepare: (sql: string) => ({
        bind: (..._a: unknown[]) => ({
          all: async () =>
            sql.includes('GROUP BY')
              ? { results: [{ event_type: 'dispatch_apns_success', count: 3 }] }
              : { results: [{ event_id: 'e1', event_type: 'dispatch_apns_success', latency_ms: 200, delivery_status: 'ok', created_at: '2026-01-01' }] },
          first: async () => ({ totalDispatched: 5, seen: 4, critical: 2, avgRetries: 1.5 }),
          run: async () => ({}),
        }),
      }),
    } as any;
    const req = await signedRequest('https://x/v1/telemetry/summary', userA);
    const res = await handleTelemetrySummary(req, envWith(db));
    expect(res.status).toBe(200);
    const body = (await res.json()) as any;
    expect(body.byType[0].count).toBe(3);
    expect(body.recent).toHaveLength(1);
    expect(body.dispatchStats.totalDispatched).toBe(5);
    expect(body.dispatchStats.seen).toBe(4);
  });
});
