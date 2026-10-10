import fs from 'node:fs/promises';
import path from 'node:path';
import { createLocationCipher } from '../src/location-security.js';

export const arrayDataKeys = [
  'users',
  'houses',
  'alerts',
  'reminders',
  'messages',
  'shortcuts',
  'passwordResetRequests',
  'adminAuditLogs',
  'notificationLogs',
  'adminUsers',
];

export const objectDataKeys = ['appVersionPolicy'];

export function recordIdFor(key, item, index) {
  return item?.id?.toString() || item?._id?.toString() || `${key}-${index}`;
}

export function storedRecord(key, item, index) {
  return {
    ...item,
    _id: recordIdFor(key, item, index),
    __order: index,
  };
}

export function publicStoredRecord(item) {
  const { _id: _storedId, __order: _order, ...record } = item;
  return record;
}

export function snapshotCounts(state) {
  return Object.fromEntries(
    arrayDataKeys.map((key) => [key, Array.isArray(state[key]) ? state[key].length : 0]),
  );
}

export async function writeJsonBackup(name, data) {
  const encrypted = createLocationCipher().encryptBackup(data);
  const backupDir = path.resolve('backups');
  await fs.mkdir(backupDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(backupDir, `${stamp}-${name}.json`);
  await fs.writeFile(filePath, JSON.stringify(encrypted, null, 2), { mode: 0o600 });
  return filePath;
}
