// Copies the Care Coach Co-pilot and Meetings LWCs from the ZetaPharma project
// (workspace root force-app) into lwc-external/ so Netlify, which only
// clones this repo, can compile them. No-op when the source is absent.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.resolve(root, '../../force-app/main/default/lwc');
const resources = path.resolve(root, '../../force-app/main/default/staticresources');
const target = path.resolve(root, 'lwc-external');
const PREFIX = 'careCoach';
const MEETING_BUNDLES = [
    'meetingHome',
    'meetingWorkspace',
    'meetingScanner',
    'meetingAccountingQueue',
    'meetingQrCode',
    'meetingQrLib',
    'meetingUtils',
    'meetingStyles'
];
// Static resources the meeting LWCs load, served from public/vendor/meeting.
const MEETING_RESOURCES = ['MeetingJsQR.js', 'ZetaBlueZ.png'];

if (!fs.existsSync(source)) {
    console.log('[sync-care-coach-lwc] source not found, keeping committed copy');
    process.exit(0);
}

const synced = (name) => name.startsWith(PREFIX) || MEETING_BUNDLES.includes(name);

const bundles = fs
    .readdirSync(source, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && synced(entry.name))
    .map((entry) => entry.name);

fs.mkdirSync(target, { recursive: true });
fs.readdirSync(target, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && synced(entry.name) && !bundles.includes(entry.name))
    .forEach((entry) => fs.rmSync(path.join(target, entry.name), { recursive: true, force: true }));

bundles.forEach((name) => {
    const from = path.join(source, name);
    const to = path.join(target, name);
    fs.rmSync(to, { recursive: true, force: true });
    fs.mkdirSync(to, { recursive: true });
    fs.readdirSync(from)
        .filter((file) => !file.endsWith('.js-meta.xml') && !file.startsWith('__'))
        .forEach((file) => fs.copyFileSync(path.join(from, file), path.join(to, file)));
});

const vendor = path.resolve(root, 'public/vendor/meeting');
fs.mkdirSync(vendor, { recursive: true });
MEETING_RESOURCES.filter((file) => fs.existsSync(path.join(resources, file))).forEach((file) =>
    fs.copyFileSync(path.join(resources, file), path.join(vendor, file))
);

console.log(`[sync-care-coach-lwc] synced ${bundles.length} bundles`);
