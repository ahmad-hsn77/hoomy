import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { createLocationCipher } from '../src/location-security.js';

const cipher = createLocationCipher();
const directory = path.resolve('backups');
for (const entry of await fs.readdir(directory, { withFileTypes: true })) {
  if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
  const file = path.join(directory, entry.name);
  const data = JSON.parse(await fs.readFile(file, 'utf8'));
  if (data?.format === 'hoomy-aes-256-gcm-v1') {
    cipher.decryptBackup(data); // Also verify the configured key can read it.
    continue;
  }
  const encrypted = cipher.encryptBackup(data);
  const temporary = `${file}.encrypted.tmp`;
  await fs.writeFile(temporary, JSON.stringify(encrypted, null, 2), { mode: 0o600, flag: 'wx' });
  await fs.rename(temporary, file);
  console.log('Encrypted backup:', entry.name);
}
