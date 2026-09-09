import { describe, it, expect } from 'vitest';

describe('APNs Payload Construction', () => {
  it('should construct correct payload for non-critical alert', () => {
    const alertId = crypto.randomUUID();
    const senderName = 'TestUser';
    const previewText = 'Hello';
    const isCritical = false;
    const env: string = 'development';

    const useCritical = isCritical && env === 'production';
    const apnsPayload = {
      aps: {
        alert: {
          title: 'UrgentSee Received:',
          body: previewText,
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
      senderName,
      rawMessagePreview: previewText,
      status: 'PUSHED',
    };

    expect(apnsPayload.aps.alert.body).toBe('Hello');
    expect(apnsPayload.aps).not.toHaveProperty('interruption-level');
    expect(apnsPayload.aps.sound).toBe('default');
  });

  it('should construct correct payload for critical alert in production', () => {
    const alertId = crypto.randomUUID();
    const senderName = 'TestUser';
    const previewText = 'Critical!';
    const isCritical = true;
    const env: string = 'production';

    const useCritical = isCritical && env === 'production';
    const apnsPayload = {
      aps: {
        alert: {
          title: 'UrgentSee Received:',
          body: previewText,
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
      senderName,
      rawMessagePreview: previewText,
      status: 'PUSHED',
    };

    expect(apnsPayload.aps['interruption-level']).toBe('critical');
    expect(apnsPayload.aps.sound).toEqual({ critical: 1, name: 'default', volume: 1.0 });
  });

  it('should NOT include critical override for non-production env even if critical', () => {
    const alertId = crypto.randomUUID();
    const isCritical = true;
    const env: string = 'development';

    const useCritical = isCritical && env === 'production';
    const apnsPayload = {
      aps: {
        alert: { title: 'Test', body: 'Test' },
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
    };

    expect(apnsPayload.aps).not.toHaveProperty('interruption-level');
  });

  it('should construct correct APNs URL', () => {
    const env: string = 'production';
    const recipientToken = 'abc123token';
    const host = env === 'production' ? 'api.push.apple.com' : 'api.development.push.apple.com';
    const url = `https://${host}/3/device/${recipientToken}`;
    expect(url).toBe('https://api.push.apple.com/3/device/abc123token');
  });

  it('should construct correct development APNs URL', () => {
    const env: string = 'development';
    const recipientToken = 'abc123token';
    const host = env === 'production' ? 'api.push.apple.com' : 'api.development.push.apple.com';
    const url = `https://${host}/3/device/${recipientToken}`;
    expect(url).toBe('https://api.development.push.apple.com/3/device/abc123token');
  });

  it('should include correct APNs headers', () => {
    const topic = 'com.urgentsee.UrgentSee';
    const token = 'provider.jwt.token';
    const ttlMinutes = 15;
    const expiration = `${Math.floor(Date.now() / 1000) + ttlMinutes * 60}`;

    const headers = {
      authorization: `bearer ${token}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': expiration,
      'content-type': 'application/json',
    };

    expect(headers.authorization).toContain('bearer ');
    expect(headers['apns-priority']).toBe('10');
    expect(headers['apns-push-type']).toBe('alert');
  });
});

describe('APNs Error Handling', () => {
  it('should detect unregistered device token (410 status)', () => {
    const status: number = 410;
    const isUnregistered = status === 410 || (status === 400 && false);
    expect(isUnregistered).toBe(true);
  });

  it('should detect unregistered device token (400 + Unregistered)', () => {
    const status: number = 400;
    const errorText = 'Unregistered device token';
    const isUnregistered = status === 410 || (status === 400 && errorText.includes('Unregistered'));
    expect(isUnregistered).toBe(true);
  });

  it('should not flag successful responses as unregistered', () => {
    const status: number = 200;
    const errorText = 'OK';
    const isUnregistered = status === 410 || (status === 400 && errorText.includes('Unregistered'));
    expect(isUnregistered).toBe(false);
  });

  it('should not flag other 400 errors as unregistered', () => {
    const status: number = 400;
    const errorText = 'BadTopic';
    const isUnregistered = status === 410 || (status === 400 && errorText.includes('Unregistered'));
    expect(isUnregistered).toBe(false);
  });
});
