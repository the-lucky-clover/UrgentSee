import { describe, it, expect } from 'vitest';
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

  it('should handle empty string', () => {
    const result = base64UrlDecode('');
    const bytes = new Uint8Array(result);
    expect(bytes.length).toBe(0);
  });

  it('should handle base64url with underscore (URL-safe char for /)', () => {
    // 0xFF 0xFF 0xFF -> "////" in standard, "____" in url-safe
    const input = '____';
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes).toEqual(new Uint8Array([0xFF, 0xFF, 0xFF]));
  });

  it('should handle base64url with dash (URL-safe char for +)', () => {
    // 0x00 0x00 -> "AAA" in standard base64, needs padding "AAA="
    // Testing a string with dash: "9g" decodes byte 0xF6
    // "-g" in url-safe means "+g" in standard which decodes to byte 0xFE
    const input = '-g';
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes.length).toBeGreaterThan(0);
  });

  it('should handle base64 without padding needed', () => {
    // "abc" -> "YWJj" (length 4, no padding needed)
    const input = 'YWJj';
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes).toEqual(new Uint8Array([97, 98, 99]));
  });

  it('should handle single character without padding', () => {
    // "a" -> "YQ" (url-safe, no padding)
    const input = 'YQ';
    const result = base64UrlDecode(input);
    const bytes = new Uint8Array(result);
    expect(bytes).toEqual(new Uint8Array([97]));
  });

  it('should decode JSON payload correctly', () => {
    // {"sub":"user123"} -> eyJzdWIiOiJ1c2VyMTIzIn0
    const input = 'eyJzdWIiOiJ1c2VyMTIzIn0';
    const result = base64UrlDecode(input);
    const decoded = new TextDecoder().decode(result);
    expect(JSON.parse(decoded)).toEqual({ sub: 'user123' });
  });
});