import { describe, it, expect, vi, beforeEach } from 'vitest';
import { base64UrlDecode } from '../index';

describe('base64UrlDecode', () => {
  it('should decode a standard base64url string', () => {
    const input = 'SGVsbG8gV29ybGQ'; // "Hello World" in base64url
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes).toEqual(new Uint8Array([72, 101, 108, 108, 111, 32, 87, 111, 114, 108, 100]));
  });

  it('should handle padding', () => {
    const input = 'SGVsbG8='; // "Hello" with padding
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes).toEqual(new Uint8Array([72, 101, 108, 108, 111]));
  });

  it('should convert URL-safe chars', () => {
    const input = 'SGVsbG8gV29ybGQ_'; // Contains _ which should become /
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes.length).toBeGreaterThan(0);
  });
});