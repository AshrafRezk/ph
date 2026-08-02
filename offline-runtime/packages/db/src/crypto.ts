/** Lightweight token/payload obfuscation helpers — swap for Cap Secure Storage + SQLCipher in production */

export function xorObfuscate(plain: string, key = 'osr-dev-key'): string {
  const out: number[] = [];
  for (let i = 0; i < plain.length; i++) {
    out.push(plain.charCodeAt(i) ^ key.charCodeAt(i % key.length));
  }
  return btoa(String.fromCharCode(...out));
}

export function xorDeobfuscate(encoded: string, key = 'osr-dev-key'): string {
  const raw = atob(encoded);
  let out = '';
  for (let i = 0; i < raw.length; i++) {
    out += String.fromCharCode(raw.charCodeAt(i) ^ key.charCodeAt(i % key.length));
  }
  return out;
}

export const ENCRYPTION_NOTES = {
  tokens: 'Store OAuth tokens via @capacitor/preferences with biometric lock when available',
  database: 'Enable SQLCipher on @capacitor-community/sqlite for field devices',
  files: 'Store ContentVersion blobs under Capacitor Filesystem Directory.Data'
} as const;
