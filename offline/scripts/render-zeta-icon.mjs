import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const script = path.join(path.dirname(fileURLToPath(import.meta.url)), 'render-zeta-icon.py');
const result = spawnSync('python3', [script], { stdio: 'inherit' });
process.exit(result.status ?? 1);
