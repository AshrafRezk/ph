/**
 * Post-cap-sync patches for iOS OAuth:
 * - CFBundleURLTypes for com.osr.offline://
 * - packageClassList entry for OsrOAuthPlugin
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const plistPath = path.join(root, 'ios/App/App/Info.plist');
const capConfigPath = path.join(root, 'ios/App/App/capacitor.config.json');

function patchPlist() {
  if (!fs.existsSync(plistPath)) {
    console.log('[ios-oauth] No Info.plist — skip');
    return;
  }
  let plist = fs.readFileSync(plistPath, 'utf8');
  if (plist.includes('com.osr.offline')) {
    console.log('[ios-oauth] URL scheme already present');
    return;
  }
  const snippet = `\t<key>CFBundleURLTypes</key>
\t<array>
\t\t<dict>
\t\t\t<key>CFBundleURLName</key>
\t\t\t<string>com.osr.offline.oauth</string>
\t\t\t<key>CFBundleURLSchemes</key>
\t\t\t<array>
\t\t\t\t<string>com.osr.offline</string>
\t\t\t</array>
\t\t</dict>
\t</array>
`;
  const updated = plist.replace('\n</dict>\n</plist>', `\n${snippet}</dict>\n</plist>`);
  if (updated === plist) {
    console.warn('[ios-oauth] Could not patch Info.plist');
    return;
  }
  fs.writeFileSync(plistPath, updated);
  console.log('[ios-oauth] Registered com.osr.offline URL scheme');
}

function patchCapConfig() {
  if (!fs.existsSync(capConfigPath)) {
    console.log('[ios-oauth] No capacitor.config.json — skip plugin list');
    return;
  }
  const json = JSON.parse(fs.readFileSync(capConfigPath, 'utf8'));
  const list = Array.isArray(json.packageClassList) ? [...json.packageClassList] : [];
  if (list.includes('OsrOAuthPlugin')) {
    console.log('[ios-oauth] OsrOAuthPlugin already in packageClassList');
    return;
  }
  list.push('OsrOAuthPlugin');
  json.packageClassList = list;
  fs.writeFileSync(capConfigPath, `${JSON.stringify(json, null, '\t')}\n`);
  console.log('[ios-oauth] Added OsrOAuthPlugin to packageClassList');
}

patchPlist();
patchCapConfig();
