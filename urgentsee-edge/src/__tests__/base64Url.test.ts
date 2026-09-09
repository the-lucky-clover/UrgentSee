import { describe, it, expect } from 'vitest';
import { base64UrlDecode } from '../index';

describe('base64UrlDecode - Extended Tests', () => {
  // Round-trip test: encode then decode
  describe('round-trip encoding/decoding', () => {
    it('should correctly round-trip simple ASCII', () => {
      const original = 'Hello, World!';
      const encoded = btoa(original).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = new TextDecoder().decode(base64UrlDecode(encoded));
      expect(decoded).toBe(original);
    });

    it('should correctly round-trip JSON data', () => {
      const original = JSON.stringify({ sub: 'user123', iat: 1700000000, exp: 1700003600 });
      const encoded = btoa(original).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = new TextDecoder().decode(base64UrlDecode(encoded));
      expect(decoded).toBe(original);
    });

    it('should correctly round-trip binary data', () => {
      const original = new Uint8Array([0, 1, 2, 127, 128, 254, 255]);
      let binary = '';
      for (let i = 0; i < original.length; i++) binary += String.fromCharCode(original[i]);
      const encoded = btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = new Uint8Array(base64UrlDecode(encoded));
      expect(decoded).toEqual(original);
    });
  });

  describe('edge cases', () => {
    it('should handle string with no padding needed (length divisible by 4)', () => {
      const input = 'YWJj'; // "abc" - no padding needed
      const result = new TextDecoder().decode(base64UrlDecode(input));
      expect(result).toBe('abc');
    });

    it('should handle string needing one padding character', () => {
      const input = 'YWI'; // "ab" - would need == padding
      const result = new TextDecoder().decode(base64UrlDecode(input));
      expect(result).toBe('ab');
    });

    it('should handle string needing two padding characters', () => {
      const input = 'YQ'; // "a" - would need = padding
      const result = new TextDecoder().decode(base64UrlDecode(input));
      expect(result).toBe('a');
    });

    it('should handle long strings', () => {
      const original = 'a'.repeat(1000);
      const encoded = btoa(original).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = new TextDecoder().decode(base64UrlDecode(encoded));
      expect(decoded).toBe(original);
    });

    it('should handle JWT header format', () => {
      const header = { alg: 'HS256', typ: 'JWT' };
      const encoded = btoa(JSON.stringify(header)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = JSON.parse(new TextDecoder().decode(base64UrlDecode(encoded)));
      expect(decoded).toEqual(header);
    });

    it('should handle JWT payload format with exp claim', () => {
      const payload = { sub: 'user123', iat: 1700000000, exp: 1700003600 };
      const encoded = btoa(JSON.stringify(payload)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
      const decoded = JSON.parse(new TextDecoder().decode(base64UrlDecode(encoded)));
      expect(decoded).toEqual(payload);
    });
  });

  describe('URL-safe character handling', () => {
    it('should decode dash (-) as plus (+)', () => {
      // Standard: "+" has value 62, so "+" in base64 represents value 62
      // "-" in url-safe also represents value 62
      // The string "-A" in url-safe = "+A" in standard
      // "+A" with padding "+A==" decodes to byte 0xF8
      const input = '-A';
      const result = base64UrlDecode(input);
      expect(new Uint8Array(result).length).toBeGreaterThan(0);
    });

    it('should decode underscore (_) as slash (/)', () => {
      // "/" has value 63, so "_" in url-safe represents value 63
      // The string "_A" in url-safe = "/A" in standard
      // "/A" with padding "/A==" decodes to byte 0xFC
      const input = '_A';
      const result = base64UrlDecode(input);
      expect(new Uint8Array(result).length).toBeGreaterThan(0);
    });

    it('should handle mixed URL-safe characters', () => {
      // String with both - and _
      const input = '-_';
      const result = base64UrlDecode(input);
      expect(new Uint8Array(result).length).toBeGreaterThan(0);
    });
  });
});
