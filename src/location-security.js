import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const protectedFields = new Set(['location', 'lastLocation', 'address']);
const format = 'hoomy-aes-256-gcm-v1';

// Keys belong in the deployment secret manager, never in a DB or backup.
export function createLocationCipher(env = process.env, { required = true } = {}) {
  const activeKeyId = env.LOCATION_ENCRYPTION_ACTIVE_KEY || 'v1';
  const configured = env.LOCATION_ENCRYPTION_KEYS;
  if (!configured && required) {
    throw new Error('LOCATION_ENCRYPTION_KEYS is required for persistent location storage');
  }
  const entries = configured ? JSON.parse(configured) : { [activeKeyId]: randomBytes(32).toString('base64') };
  const keys = new Map(Object.entries(entries).map(([id, value]) => {
    const key = Buffer.from(value, 'base64');
    if (key.length !== 32) throw new Error(`Location encryption key ${id} must be 32 bytes (base64)`);
    return [id, key];
  }));
  if (!keys.has(activeKeyId)) throw new Error('Active location encryption key is missing');

  function encrypt(value, purpose) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', keys.get(activeKeyId), iv);
    cipher.setAAD(Buffer.from(purpose));
    const data = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
    return { format, keyId: activeKeyId, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') };
  }

  function decrypt(value, purpose) {
    if (value?.format !== format) return value; // Existing records are migrated on the next write.
    const key = keys.get(value.keyId);
    if (!key) throw new Error(`Missing location decryption key ${value.keyId}`);
    const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(value.iv, 'base64'));
    decipher.setAAD(Buffer.from(purpose));
    decipher.setAuthTag(Buffer.from(value.tag, 'base64'));
    return JSON.parse(Buffer.concat([decipher.update(Buffer.from(value.data, 'base64')), decipher.final()]).toString('utf8'));
  }

  function transform(value, encrypting) {
    if (Array.isArray(value)) return value.map((item) => transform(item, encrypting));
    if (!value || typeof value !== 'object' || value instanceof Date) return value;
    return Object.fromEntries(Object.entries(value).map(([key, item]) => [key,
      protectedFields.has(key) && item != null
        ? (encrypting ? encrypt(item, `location:${key}`) : decrypt(item, `location:${key}`))
        : transform(item, encrypting),
    ]));
  }

  return {
    encryptState: (state) => transform(state, true),
    decryptState: (state) => transform(state, false),
    encryptBackup: (data) => encrypt(data, 'hoomy:backup'),
    decryptBackup: (data) => decrypt(data, 'hoomy:backup'),
  };
}

export function redactLocation(value) {
  if (Array.isArray(value)) return value.map(redactLocation);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(Object.entries(value)
    .filter(([key]) => !protectedFields.has(key))
    .map(([key, item]) => [key, redactLocation(item)]));
}

export function validLocation(value) {
  return value != null && Number.isFinite(value.lat) && Number.isFinite(value.lng)
    && value.lat >= -90 && value.lat <= 90 && value.lng >= -180 && value.lng <= 180;
}

export function isSecureTransport(req, trustedProxy = false) {
  return Boolean(req.socket?.encrypted) || (trustedProxy && req.headers['x-forwarded-proto'] === 'https');
}

export function canReceiveHouseLocation({ userId, expiresAt }, house, users, now = Date.now()) {
  return typeof expiresAt === 'number' && expiresAt > now
    && users.some((user) => user.id === userId && !['suspended', 'disabled', 'deleted'].includes(user.status))
    && Boolean(house?.members.some((member) => member.userId === userId));
}
