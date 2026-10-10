import 'dotenv/config';
import fs from 'node:fs/promises';
import { createLocationCipher } from '../src/location-security.js';

const [input, output] = process.argv.slice(2);
if (!input || !output) throw new Error('Usage: node scripts/decrypt-backup.js <encrypted-backup> <private-output>');
const backup = JSON.parse(await fs.readFile(input, 'utf8'));
if (backup?.format !== 'hoomy-aes-256-gcm-v1') throw new Error('Expected an encrypted Hoomy backup');
const data = createLocationCipher().decryptBackup(backup);
// Explicit recovery only: never overwrite an existing file or print secrets.
await fs.writeFile(output, JSON.stringify(data, null, 2), { mode: 0o600, flag: 'wx' });
