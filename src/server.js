import 'dotenv/config';
import bcrypt from 'bcryptjs';
import cors from 'cors';
import express from 'express';
import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import http from 'node:http';
import jwt from 'jsonwebtoken';
import { MongoClient } from 'mongodb';
import { Server } from 'socket.io';
import { v4 as uuid } from 'uuid';

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: process.env.CORS_ORIGIN || '*' },
});

app.use(cors({ origin: process.env.CORS_ORIGIN || '*' }));
app.use(express.json());

const jwtSecret = process.env.JWT_SECRET || 'dev-secret';
let firebaseApp = null;
let firebaseMessaging = null;

function parseFirebaseServiceAccount() {
  const rawJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  const rawBase64 = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64?.trim();

  if (!rawJson && !rawBase64) return null;

  const candidates = [
    rawBase64
      ? {
          name: 'FIREBASE_SERVICE_ACCOUNT_BASE64',
          value: Buffer.from(rawBase64, 'base64').toString('utf8'),
        }
      : null,
    rawJson ? { name: 'FIREBASE_SERVICE_ACCOUNT_JSON', value: rawJson } : null,
  ].filter(Boolean);

  const errors = [];
  for (const candidate of candidates) {
    try {
      const serviceAccount = JSON.parse(candidate.value);
      if (serviceAccount.private_key) {
        serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
      }
      serviceAccount.__source = candidate.name;
      return serviceAccount;
    } catch (error) {
      errors.push(`${candidate.name}: ${error.message}`);
    }
  }
  throw new Error(`Could not parse Firebase service account env. ${errors.join(' | ')}`);
}

const firebaseConfigStatus = {
  hasServiceAccountJson: Boolean(process.env.FIREBASE_SERVICE_ACCOUNT_JSON),
  hasServiceAccountBase64: Boolean(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64),
  hasGoogleCredentialsPath: Boolean(process.env.GOOGLE_APPLICATION_CREDENTIALS),
};

try {
  const serviceAccount = parseFirebaseServiceAccount();
  if (serviceAccount) {
    firebaseApp = initializeApp({
      credential: cert(serviceAccount),
    });
    firebaseMessaging = getMessaging(firebaseApp);
    console.log('Firebase Admin initialized from service account env', {
      source: serviceAccount.__source,
      projectId: serviceAccount.project_id,
      clientEmail: serviceAccount.client_email,
    });
  } else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    firebaseApp = initializeApp({
      credential: applicationDefault(),
    });
    firebaseMessaging = getMessaging(firebaseApp);
    console.log('Firebase Admin initialized from GOOGLE_APPLICATION_CREDENTIALS');
  } else {
    console.warn('Firebase Admin is not configured at startup', firebaseConfigStatus);
  }
} catch (error) {
  console.warn('Firebase Admin initialization failed', {
    message: error.message,
    ...firebaseConfigStatus,
  });
}

/*
if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
  try {
    firebaseApp = initializeApp({
      credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON)),
    });
  } catch (error) {
    console.warn('Firebase Admin initialization failed:', error.message);
  }
} else if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  try {
    firebaseApp = initializeApp({
      credential: applicationDefault(),
    });
  } catch (error) {
    console.warn('Firebase Admin initialization failed:', error.message);
  }
}
*/

const db = {
  users: [],
  houses: [],
  alerts: [],
  reminders: [],
  messages: [],
  shortcuts: [],
  passwordResetRequests: [],
};

const dataStoreConfig = {
  uri: process.env.MONGODB_URI?.trim(),
  databaseName: process.env.MONGODB_DB?.trim() || 'hoomy',
  collectionName: process.env.MONGODB_COLLECTION?.trim() || 'app_state',
  documentId: process.env.MONGODB_DOCUMENT_ID?.trim() || 'main',
};
let mongoClient = null;
let dataCollection = null;
let dataStoreReady = false;
let persistTimer = null;
let persistChain = Promise.resolve();

function loadDbState(state = {}) {
  for (const key of Object.keys(db)) {
    if (Array.isArray(state[key])) {
      db[key] = state[key];
    }
  }
}

function dbSnapshot() {
  return Object.fromEntries(
    Object.keys(db).map((key) => [key, Array.isArray(db[key]) ? [...db[key]] : db[key]])
  );
}

async function connectDataStore() {
  if (!dataStoreConfig.uri) {
    console.warn('MongoDB is not configured. Data will be stored in memory only.');
    return;
  }

  mongoClient = new MongoClient(dataStoreConfig.uri);
  await mongoClient.connect();
  dataCollection = mongoClient
    .db(dataStoreConfig.databaseName)
    .collection(dataStoreConfig.collectionName);

  const saved = await dataCollection.findOne({ _id: dataStoreConfig.documentId });
  if (saved?.state) {
    loadDbState(saved.state);
    console.log('Loaded Hoomy data from MongoDB', {
      database: dataStoreConfig.databaseName,
      collection: dataStoreConfig.collectionName,
      users: db.users.length,
      houses: db.houses.length,
    });
  } else {
    await persistDbNow();
    console.log('Initialized empty Hoomy data document in MongoDB', {
      database: dataStoreConfig.databaseName,
      collection: dataStoreConfig.collectionName,
    });
  }
  dataStoreReady = true;
}

function persistDb() {
  if (!dataCollection) return;
  clearTimeout(persistTimer);
  persistTimer = setTimeout(() => {
    persistDbNow().catch((error) => {
      console.warn('MongoDB persistence failed', {
        message: error.message,
      });
    });
  }, 25);
}

async function persistDbNow() {
  if (!dataCollection) return;
  const state = dbSnapshot();
  persistChain = persistChain.catch(() => {}).then(() =>
    dataCollection.updateOne(
      { _id: dataStoreConfig.documentId },
      {
        $set: {
          state,
          updatedAt: new Date(),
        },
        $setOnInsert: {
          createdAt: new Date(),
        },
      },
      { upsert: true }
    )
  );
  await persistChain;
}

const defaultNotificationPreferences = {
  needAlerts: true,
  emergencyAlerts: true,
  chatMessages: true,
};

const notificationChannels = {
  emergencyAlerts: 'hoomy_emergency_alerts_alarm_v2',
  needAlerts: 'hoomy_need_alerts',
  chatMessages: 'hoomy_chat_messages_chime_v2',
  reminders: 'hoomy_reminders_alarm_v1',
};

function normalize(value) {
  return value?.toString().trim().toLowerCase() || '';
}

function publicUser(user) {
  const { passwordHash, ...safeUser } = user;
  return {
    ...safeUser,
    notificationPreferences: {
      ...defaultNotificationPreferences,
      ...(safeUser.notificationPreferences || {}),
    },
  };
}

function findUserByIdentity({ email, phone, childName }) {
  const normalizedEmail = normalize(email);
  const normalizedPhone = normalize(phone);
  const normalizedChildName = normalize(childName);

  return db.users.find((user) => {
    return (
      (normalizedEmail && normalize(user.email) === normalizedEmail) ||
      (normalizedPhone && normalize(user.phone) === normalizedPhone) ||
      (normalizedChildName && user.childMode && normalize(user.name) === normalizedChildName)
    );
  });
}

function sign(user) {
  return jwt.sign({ userId: user.id }, jwtSecret, { expiresIn: '30d' });
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ message: 'Missing token' });

  try {
    const payload = jwt.verify(token, jwtSecret);
    const user = db.users.find((item) => item.id === payload.userId);
    if (!user) return res.status(401).json({ message: 'Invalid token' });
    req.user = user;
    next();
  } catch {
    res.status(401).json({ message: 'Invalid token' });
  }
}

function requireHouseMember(req, res, next) {
  const house = db.houses.find((item) => item.id === req.params.houseId);
  if (!house) return res.status(404).json({ message: 'House not found' });

  const membership = house.members.find((item) => item.userId === req.user.id);
  if (!membership) return res.status(403).json({ message: 'Not a house member' });

  req.house = house;
  req.membership = membership;
  next();
}

function houseState(house, userId) {
  return {
    house,
    houses: housesForUser(userId),
    members: house.members.map((member) => ({
      ...member,
      user: publicUser(db.users.find((user) => user.id === member.userId) || {}),
    })),
    alerts: db.alerts.filter((item) => item.houseId === house.id),
    reminders: db.reminders.filter((item) => item.houseId === house.id),
    messages: db.messages.filter((item) => item.houseId === house.id),
    shortcuts: db.shortcuts.filter((item) => item.houseId === house.id && (!userId || item.createdBy === userId)),
  };
}

function firstHouseForUser(userId) {
  return db.houses.find((house) => house.members.some((member) => member.userId === userId));
}

function housesForUser(userId) {
  return db.houses.filter((house) => house.members.some((member) => idOf(member.userId) === idOf(userId)));
}

function authState(user, extra = {}) {
  const house = firstHouseForUser(user.id);
  return {
    ...extra,
    user: publicUser(user),
    houses: housesForUser(user.id),
    ...(house ? houseState(house, user.id) : {}),
  };
}

function createHouseMessage({ houseId, senderId, text, system = false, notify = true }) {
  const message = {
    id: uuid(),
    houseId,
    text,
    senderId,
    system,
    createdAt: new Date().toISOString(),
  };
  db.messages.push(message);
  persistDb();
  io.to(houseId).emit('messageCreated', message);
  const house = db.houses.find((item) => item.id === houseId);
  const sender = db.users.find((item) => item.id === senderId);
  if (house && notify) {
    sendMessagePush({ house, message, sender }).catch((error) => {
      console.warn('Message push failed:', error.message);
    });
  }
  return message;
}

function removeBadPushTokens(tokens, response) {
  let removedAny = false;
  response.responses.forEach((item, index) => {
    if (!item.success && item.error?.code?.includes('registration-token')) {
      const badToken = tokens[index];
      db.users.forEach((user) => {
        if ((user.fcmTokens || []).includes(badToken)) removedAny = true;
        user.fcmTokens = (user.fcmTokens || []).filter((token) => token !== badToken);
      });
    }
  });
  if (removedAny) persistDb();
}

function idOf(value) {
  return value == null ? '' : value.toString();
}

function tokensForUsers(users) {
  return users.flatMap((user) =>
    (user.fcmTokens || []).map((token) => ({
      token,
      userId: idOf(user.id),
      userName: user.name,
    }))
  );
}

function logPushResult(type, response, extra = {}) {
  console.log(`${type} push result`, {
    successCount: response.successCount,
    failureCount: response.failureCount,
    ...extra,
  });
}

function logPushFailures(type, response, tokenOwners) {
  response.responses.forEach((item, index) => {
    if (item.success) return;
    const owner = tokenOwners[index] || {};
    console.warn(`${type} push token failed`, {
      userId: owner.userId,
      userName: owner.userName,
      tokenPrefix: owner.token ? owner.token.slice(0, 12) : '',
      code: item.error?.code,
      message: item.error?.message,
    });
  });
}

function pushData(values) {
  return Object.fromEntries(
    Object.entries(values).map(([key, value]) => [
      key,
      value == null ? '' : String(value),
    ])
  );
}

function logPushError(type, error, extra = {}) {
  console.warn(`${type} push failed`, {
    code: error.code,
    message: error.message,
    stack: error.stack,
    ...extra,
  });
}

async function sendMessagePush({ house, message, sender }) {
  if (!firebaseMessaging) {
    console.warn('Message push skipped: Firebase Admin is not configured');
    return;
  }

  const recipientIds = house.members
    .map((member) => idOf(member.userId))
    .filter((userId) => userId !== idOf(message.senderId));
  const recipients = db.users.filter((user) =>
    recipientIds.includes(idOf(user.id)) &&
    (user.notificationPreferences?.chatMessages ?? true)
  );
  const tokenOwners = tokensForUsers(recipients);
  const tokens = tokenOwners.map((item) => item.token);
  if (tokens.length === 0) {
    console.warn('Message push skipped: no recipient FCM tokens', {
      houseId: house.id,
      recipientIds,
      recipientCount: recipients.length,
    });
    return;
  }

  const senderName = sender?.name || 'Family';
  const title = message.system ? 'Family update' : `${senderName} in family chat`;
  const body = message.text || 'New family message';
  try {
    const response = await firebaseMessaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: pushData({
        type: 'messageCreated',
        messageId: message.id,
        houseId: house.id,
        senderId: message.senderId,
        title,
        body,
        system: message.system ? 'true' : 'false',
      }),
      android: {
        priority: 'high',
        notification: {
          channelId: notificationChannels.chatMessages,
          icon: 'ic_notification_house',
          sound: 'message_chime',
          priority: 'high',
          visibility: 'public',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: 'message_chime.wav',
          },
        },
      },
    });

    removeBadPushTokens(tokens, response);
    logPushFailures('Message', response, tokenOwners);
    logPushResult('Message', response, {
      houseId: house.id,
      tokenCount: tokens.length,
      messageId: message.id,
    });
  } catch (error) {
    logPushError('Message', error, {
      houseId: house.id,
      tokenCount: tokens.length,
      messageId: message.id,
    });
    throw error;
  }
}

function alertRecipientUserIds({ house, alert, creatorId }) {
  const memberIds = house.members.map((member) => idOf(member.userId));
  const hasExplicitTargets = Array.isArray(alert.targetMemberIds) && alert.targetMemberIds.length > 0;
  const requestedIds = hasExplicitTargets ? alert.targetMemberIds.map(idOf) : memberIds;

  const filteredIds = [...new Set(requestedIds.map(idOf))].filter((userId) => memberIds.includes(userId));
  if (hasExplicitTargets) return filteredIds;
  return filteredIds.filter((userId) => userId !== idOf(creatorId));
}

async function sendAlertPush({ house, alert, creator }) {
  if (!firebaseMessaging) {
    console.warn('Alert push skipped: Firebase Admin is not configured');
    return;
  }

  const recipientIds = alertRecipientUserIds({ house, alert, creatorId: creator.id });
  const emergency = alert.emergency === true;
  const recipients = db.users.filter((user) =>
    recipientIds.includes(idOf(user.id)) &&
    (emergency
      ? (user.notificationPreferences?.emergencyAlerts ?? true)
      : (user.notificationPreferences?.needAlerts ?? true))
  );
  const tokenOwners = tokensForUsers(recipients);
  const tokens = tokenOwners.map((item) => item.token);
  if (tokens.length === 0) {
    console.warn('Alert push skipped: no recipient FCM tokens', {
      houseId: house.id,
      alertId: alert.id,
      recipientIds,
      recipientCount: recipients.length,
    });
    return;
  }

  const title = emergency ? `Emergency need: ${alert.title}` : `House need: ${alert.title}`;
  const body = alert.note || `${creator.name} added a house need.`;
  try {
    const payload = {
      tokens,
      data: pushData({
        type: 'alertCreated',
        alertId: alert.id,
        houseId: house.id,
        title: alert.title,
        body,
        createdBy: creator.id,
        emergency: emergency ? 'true' : 'false',
        targetMemberIds: alert.targetMemberIds.join(','),
      }),
      android: {
        priority: 'high',
      },
      fcmOptions: {
        analyticsLabel: emergency ? 'emergency_alert' : 'need_alert',
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: emergency ? 'emergency_ring.wav' : 'default',
            interruptionLevel: emergency ? 'time-sensitive' : 'active',
          },
        },
      },
    };

    payload.notification = { title, body };
    payload.android.notification = {
      channelId: emergency ? notificationChannels.emergencyAlerts : notificationChannels.needAlerts,
      icon: 'ic_notification_house',
      sound: emergency ? 'emergency_ring' : 'default',
      priority: emergency ? 'max' : 'high',
      visibility: 'public',
    };

    const response = await firebaseMessaging.sendEachForMulticast(payload);
    removeBadPushTokens(tokens, response);
    logPushFailures('Alert', response, tokenOwners);
    logPushResult('Alert', response, {
      houseId: house.id,
      alertId: alert.id,
      tokenCount: tokens.length,
      emergency,
    });
  } catch (error) {
    logPushError('Alert', error, {
      houseId: house.id,
      alertId: alert.id,
      tokenCount: tokens.length,
      emergency,
    });
    throw error;
  }
}

async function sendReminderPush({ house, reminder, creator }) {
  if (!firebaseMessaging) {
    console.warn('Reminder push skipped: Firebase Admin is not configured');
    return;
  }

  const recipientIds = house.members
    .map((member) => idOf(member.userId))
    .filter((userId) => userId !== idOf(creator.id));
  const recipients = db.users.filter((user) => recipientIds.includes(idOf(user.id)));
  const tokenOwners = tokensForUsers(recipients);
  const tokens = tokenOwners.map((item) => item.token);
  if (tokens.length === 0) {
    console.warn('Reminder push skipped: no recipient FCM tokens', {
      houseId: house.id,
      reminderId: reminder.id,
      recipientIds,
      recipientCount: recipients.length,
    });
    return;
  }

  const title = `Family reminder: ${reminder.title}`;
  const body = reminder.note || `${creator.name} added a reminder.`;
  try {
    const response = await firebaseMessaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: pushData({
        type: 'reminderCreated',
        reminderId: reminder.id,
        houseId: house.id,
        title: reminder.title,
        body,
        dueAt: reminder.dueAt,
        createdBy: creator.id,
        isBirthday: reminder.isBirthday ? 'true' : 'false',
        birthdayMemberId: reminder.birthdayMemberId || '',
      }),
      android: {
        priority: 'high',
        notification: {
          channelId: notificationChannels.reminders,
          icon: 'ic_notification_house',
          sound: 'reminder_ring',
          priority: 'max',
          visibility: 'public',
        },
      },
      fcmOptions: {
        analyticsLabel: 'family_reminder',
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: 'reminder_ring.wav',
            interruptionLevel: 'time-sensitive',
          },
        },
      },
    });

    removeBadPushTokens(tokens, response);
    logPushFailures('Reminder', response, tokenOwners);
    logPushResult('Reminder', response, {
      houseId: house.id,
      reminderId: reminder.id,
      tokenCount: tokens.length,
    });
  } catch (error) {
    logPushError('Reminder', error, {
      houseId: house.id,
      reminderId: reminder.id,
      tokenCount: tokens.length,
    });
    throw error;
  }
}

function createHouseCode({ id, name, createdAt }) {
  const namePart = normalize(name)
    .replace(/[^a-z0-9]+/g, '')
    .slice(0, 8)
    .toUpperCase() || 'HOUSE';
  const timePart = new Date(createdAt).getTime().toString(36).toUpperCase();
  const idPart = id.replace(/-/g, '').slice(0, 6).toUpperCase();
  return `${namePart}-${timePart}-${idPart}`;
}

app.get('/health', (_req, res) => {
  res.json({
    ok: true,
    name: 'hoomy-backend',
    firebaseAdminConfigured: Boolean(firebaseMessaging),
    firebaseConfigStatus,
    databaseConfigured: Boolean(dataStoreConfig.uri),
    databaseReady: dataStoreReady,
  });
});

app.get('/app/update', (req, res) => {
  const latestVersion = process.env.APP_LATEST_VERSION?.trim() || '0.1.0';
  const minimumSupportedVersion =
    process.env.APP_MIN_SUPPORTED_VERSION?.trim() || '';
  const updateUrl = process.env.APP_UPDATE_URL?.trim() || '';
  const releaseNotes = process.env.APP_UPDATE_NOTES?.trim() || '';
  const currentVersion = req.query.currentVersion?.toString() || '';

  res.json({
    latestVersion,
    minimumSupportedVersion,
    updateUrl,
    releaseNotes,
    currentVersion,
  });
});

app.get('/', (_req, res) => {
  res.json({
    ok: true,
    name: 'hoomy-backend',
    message: 'Hoomy backend is running',
    health: '/health',
  });
});

app.post('/auth/register', async (req, res) => {
  const { name, email, phone, password, childMode = false } = req.body;
  const normalizedName = name?.toString().trim();
  if (!normalizedName) return res.status(400).json({ message: 'Name is required' });
  if (!childMode && !email && !phone) {
    return res.status(400).json({ message: 'Email or phone is required unless child mode is enabled' });
  }

  const duplicate = findUserByIdentity({ email, phone, childName: childMode ? normalizedName : null });
  if (duplicate) return res.status(409).json({ message: 'User already exists' });

  const user = {
    id: uuid(),
    name: normalizedName,
    email: email?.toString().trim() || null,
    phone: phone?.toString().trim() || null,
    childMode,
    outsideHouse: true,
    passwordHash: childMode ? null : await bcrypt.hash(password || '123456', 10),
    notificationPreferences: { ...defaultNotificationPreferences },
    createdAt: new Date().toISOString(),
  };
  db.users.push(user);
  persistDb();
  res.status(201).json({ token: sign(user), user: publicUser(user) });
});

app.post('/auth/login', async (req, res) => {
  const { email, phone, childName, password } = req.body;
  const user = findUserByIdentity({ email, phone, childName });
  if (!user) return res.status(401).json({ message: 'Invalid credentials' });

  if (!user.childMode) {
    const ok = await bcrypt.compare(password || '', user.passwordHash);
    if (!ok) return res.status(401).json({ message: 'Invalid credentials' });
  }

  res.json(authState(user, { token: sign(user) }));
});

app.post('/auth/forgot-password', (req, res) => {
  const { email, phone } = req.body;
  const user = findUserByIdentity({ email, phone });
  if (!user || user.childMode) {
    return res.status(404).json({ message: 'Account not found' });
  }

  const resetRequest = {
    id: uuid(),
    userId: user.id,
    contact: user.email || user.phone,
    createdAt: new Date().toISOString(),
    usedAt: null,
  };
  db.passwordResetRequests.push(resetRequest);
  persistDb();

  // Prototype behavior: no email/SMS provider is connected yet, so the app can proceed to reset.
  res.json({
    ok: true,
    message: 'Password reset request created',
    resetRequestId: resetRequest.id,
  });
});

app.post('/auth/reset-password', async (req, res) => {
  const { email, phone, newPassword } = req.body;
  if (!newPassword || newPassword.toString().length < 4) {
    return res.status(400).json({ message: 'New password must be at least 4 characters' });
  }

  const user = findUserByIdentity({ email, phone });
  if (!user || user.childMode) {
    return res.status(404).json({ message: 'Account not found' });
  }

  user.passwordHash = await bcrypt.hash(newPassword.toString(), 10);
  const request = [...db.passwordResetRequests].reverse().find((item) => item.userId === user.id && !item.usedAt);
  if (request) request.usedAt = new Date().toISOString();
  persistDb();

  res.json({ ok: true, message: 'Password reset successfully' });
});

app.get('/auth/me', requireAuth, (req, res) => {
  res.json(authState(req.user));
});

app.put('/users/me/profile', requireAuth, (req, res) => {
  if (Object.prototype.hasOwnProperty.call(req.body, 'name')) {
    const name = req.body.name?.toString().trim();
    if (!name) return res.status(400).json({ message: 'Name is required' });
    if (req.user.childMode) {
      const duplicate = db.users.find(
        (user) => user.id !== req.user.id && user.childMode && normalize(user.name) === normalize(name)
      );
      if (duplicate) return res.status(409).json({ message: 'A child account with this name already exists' });
    }
    req.user.name = name;
  }

  if (Object.prototype.hasOwnProperty.call(req.body, 'phone')) {
    const phone = req.body.phone?.toString().trim() || null;
    if (!req.user.childMode && !phone && !req.user.email) {
      return res.status(400).json({ message: 'Phone or email is required' });
    }
    if (phone) {
      const duplicate = db.users.find(
        (user) => user.id !== req.user.id && normalize(user.phone) === normalize(phone)
      );
      if (duplicate) return res.status(409).json({ message: 'Account with this phone number already exists' });
    }
    req.user.phone = phone;
  }

  if (Object.prototype.hasOwnProperty.call(req.body, 'birthDate')) {
    req.user.birthDate = req.body.birthDate ? req.body.birthDate.toString() : null;
  }
  persistDb();
  res.json({ user: publicUser(req.user) });
});

app.post('/devices/fcm-token', requireAuth, (req, res) => {
  const token = req.body.token?.toString().trim();
  if (!token) return res.status(400).json({ message: 'FCM token is required' });

  req.user.fcmTokens = req.user.fcmTokens || [];
  if (!req.user.fcmTokens.includes(token)) req.user.fcmTokens.push(token);
  persistDb();

  res.json({ ok: true, tokenCount: req.user.fcmTokens.length });
});

app.post('/devices/test-notification', requireAuth, async (req, res) => {
  if (!firebaseMessaging) {
    return res.status(503).json({ message: 'Firebase Admin is not configured' });
  }

  const tokenOwners = tokensForUsers([req.user]);
  const tokens = tokenOwners.map((item) => item.token);
  if (tokens.length === 0) {
    return res.status(400).json({ message: 'No FCM token registered for this user' });
  }

  const title = req.body.title?.toString() || 'Hoomy alert test';
  const body = req.body.body?.toString() || 'Backend push notifications are connected.';
  let response;
  try {
    response = await firebaseMessaging.sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: pushData({
        type: 'alertCreated',
        alertId: `test-${Date.now()}`,
        houseId: firstHouseForUser(req.user.id)?.id || '',
        title: 'Backend test',
        body,
        createdBy: req.user.id,
        emergency: req.body.emergency === true ? 'true' : 'false',
        targetMemberIds: req.user.id,
      }),
      android: {
        priority: 'high',
        notification: {
          channelId: req.body.emergency === true ? 'hoomy_emergency_alerts_alarm_v2' : 'hoomy_need_alerts',
          icon: 'ic_notification_house',
          sound: req.body.emergency === true ? 'emergency_ring' : 'default',
          priority: req.body.emergency === true ? 'max' : 'high',
          visibility: 'public',
        },
      },
      apns: {
        headers: {
          'apns-priority': '10',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: req.body.emergency === true ? 'emergency_ring.wav' : 'default',
            interruptionLevel: req.body.emergency === true ? 'time-sensitive' : 'active',
          },
        },
      },
    });
  } catch (error) {
    logPushError('Test alert', error, { userId: req.user.id, tokenCount: tokens.length });
    return res.status(500).json({
      message: 'Firebase test notification failed',
      code: error.code,
      error: error.message,
    });
  }

  removeBadPushTokens(tokens, response);
  logPushFailures('Test alert', response, tokenOwners);
  logPushResult('Test alert', response, { userId: req.user.id, tokenCount: tokens.length });
  res.json({
    ok: response.failureCount === 0,
    successCount: response.successCount,
    failureCount: response.failureCount,
    errors: response.responses.flatMap((item, index) => {
      if (item.success) return [];
      return [{
        tokenPrefix: tokens[index]?.slice(0, 12) || '',
        code: item.error?.code,
        message: item.error?.message,
      }];
    }),
  });
});

app.put('/users/me/notification-preferences', requireAuth, (req, res) => {
  const current = {
    ...defaultNotificationPreferences,
    ...(req.user.notificationPreferences || {}),
  };
  req.user.notificationPreferences = {
    needAlerts: req.body.needAlerts ?? current.needAlerts,
    emergencyAlerts: req.body.emergencyAlerts ?? current.emergencyAlerts,
    chatMessages: req.body.chatMessages ?? current.chatMessages,
  };
  persistDb();
  res.json({ user: publicUser(req.user) });
});

app.post('/houses', requireAuth, (req, res) => {
  const { name, address, location, role = 'Parent' } = req.body;
  if (!name) return res.status(400).json({ message: 'House name is required' });

  const createdAt = new Date().toISOString();
  const house = {
    id: uuid(),
    name,
    address: address || '',
    location: location || null,
    createdBy: req.user.id,
    members: [{ userId: req.user.id, role, relation: role, admin: true }],
    createdAt,
    visibility: 'private',
  };
  house.specialNumber = createHouseCode(house);
  db.houses.push(house);
  if (location) req.user.outsideHouse = false;
  persistDb();
  res.status(201).json(houseState(house, req.user.id));
});

app.put('/houses/:houseId/location', requireAuth, requireHouseMember, (req, res) => {
  const location = req.body.location;
  if (
    !location ||
    typeof location.lat !== 'number' ||
    typeof location.lng !== 'number'
  ) {
    return res.status(400).json({ message: 'Valid house location is required' });
  }

  req.house.location = { lat: location.lat, lng: location.lng };
  req.house.address = req.body.address?.toString() || req.house.address || '';
  persistDb();

  res.json(houseState(req.house, req.user.id));
});

app.post('/houses/join', requireAuth, (req, res) => {
  const houseCode = normalize(req.body.houseCode).replace(/[^a-z0-9]/g, '');
  const relation = req.body.relation || 'Member';
  if (!houseCode) return res.status(400).json({ message: 'House special number is required' });

  const house = db.houses.find((item) => normalize(item.specialNumber).replace(/[^a-z0-9]/g, '') === houseCode);
  if (!house) return res.status(404).json({ message: 'House not found' });

  const membership = house.members.find((item) => idOf(item.userId) === idOf(req.user.id));
  if (membership) {
    membership.relation = relation;
    membership.role = relation;
    persistDb();
    io.to(house.id).emit('memberUpdated', { houseId: house.id, user: publicUser(req.user), relation });
    return res.json(houseState(house, req.user.id));
  }

  house.members.push({ userId: req.user.id, role: relation, relation, admin: false });
  persistDb();
  io.to(house.id).emit('memberAdded', { houseId: house.id, user: publicUser(req.user), relation });
  res.status(201).json(houseState(house, req.user.id));
});

app.get('/houses/:houseId/state', requireAuth, requireHouseMember, (req, res) => {
  res.json(houseState(req.house, req.user.id));
});

app.post('/houses/:houseId/members', requireAuth, requireHouseMember, (req, res) => {
  const { name, relation, phone, childMode = false } = req.body;
  const normalizedName = name?.toString().trim();
  const normalizedPhone = phone?.toString().trim();
  if (childMode && !normalizedName) return res.status(400).json({ message: 'Child account name is required' });
  if (!childMode && !normalizedPhone) return res.status(400).json({ message: 'Phone number is required' });

  const user = childMode
    ? findUserByIdentity({ childName: normalizedName })
    : findUserByIdentity({ phone: normalizedPhone });

  if (!user) {
    return res.status(404).json({ message: childMode ? 'Child account not found' : 'Account with this phone number was not found' });
  }

  if (user.id === req.user.id) {
    return res.status(400).json({ message: 'You cannot add your own account as a family member' });
  }

  if (req.house.members.some((item) => item.userId === user.id)) {
    return res.status(409).json({ message: 'This account is already a member of this house' });
  }

  req.house.members.push({ userId: user.id, role: relation || 'Member', relation: relation || 'Member', admin: false });
  persistDb();

  io.to(req.house.id).emit('memberAdded', { houseId: req.house.id, user: publicUser(user), relation });
  res.status(201).json(houseState(req.house, req.user.id));
});

app.put('/houses/:houseId/members/me/status', requireAuth, requireHouseMember, (req, res) => {
  req.user.outsideHouse = Boolean(req.body.outsideHouse);
  req.user.lastLocation = req.body.location || null;
  req.user.locationStatusUpdatedAt = new Date().toISOString();
  persistDb();

  const payload = {
    houseId: req.house.id,
    user: publicUser(req.user),
    relation: req.membership.relation || req.membership.role || 'Member',
  };
  io.to(req.house.id).emit('memberUpdated', payload);
  res.json(payload);
});

app.post('/houses/:houseId/alerts', requireAuth, requireHouseMember, (req, res) => {
  const targetMemberIds = Array.isArray(req.body.targetMemberIds)
    ? [...req.body.targetMemberIds]
    : [];

  const alert = {
    id: uuid(),
    houseId: req.house.id,
    title: req.body.title,
    note: req.body.note || '',
    emergency: Boolean(req.body.emergency),
    quantity: req.body.quantity || null,
    targetMemberIds,
    createdBy: req.user.id,
    status: 'open',
    bought: null,
    createdAt: new Date().toISOString(),
  };
  db.alerts.push(alert);
  persistDb();
  io.to(req.house.id).emit('alertCreated', alert);
  createHouseMessage({
    houseId: req.house.id,
    senderId: req.user.id,
    text: alert.emergency ? `Emergency need: ${alert.title}` : `Need added: ${alert.title}`,
    system: true,
    notify: false,
  });
  sendAlertPush({ house: req.house, alert, creator: req.user }).catch((error) => {
    console.warn('Alert push failed:', error.message);
  });
  res.status(201).json(alert);
});

app.post('/houses/:houseId/alerts/:alertId/bought', requireAuth, requireHouseMember, (req, res) => {
  const alert = db.alerts.find((item) => item.id === req.params.alertId && item.houseId === req.house.id);
  if (!alert) return res.status(404).json({ message: 'Alert not found' });

  alert.status = 'bought';
  alert.bought = {
    by: req.user.id,
    quantity: req.body.quantity || null,
    price: req.body.price || null,
    at: new Date().toISOString(),
  };
  persistDb();

  io.to(req.house.id).emit('alertBought', alert);
  createHouseMessage({
    houseId: req.house.id,
    senderId: req.user.id,
    text: `${req.user.name} bought ${alert.title}${req.body.price ? ` for ${req.body.price}` : ''}.`,
    system: true,
  });
  res.json(alert);
});

app.post('/houses/:houseId/reminders', requireAuth, requireHouseMember, (req, res) => {
  const isBirthday = req.body.isBirthday === true;
  const birthdayMemberId = req.body.birthdayMemberId ? idOf(req.body.birthdayMemberId) : null;
  if (isBirthday) {
    if (!birthdayMemberId) {
      return res.status(400).json({ message: 'Choose the birthday family member' });
    }
    const isHouseMember = req.house.members.some((member) => idOf(member.userId) === birthdayMemberId);
    if (!isHouseMember) {
      return res.status(400).json({ message: 'Birthday member is not in this house' });
    }
  }
  const reminder = {
    id: uuid(),
    houseId: req.house.id,
    title: req.body.title,
    note: req.body.note || '',
    dueAt: req.body.dueAt,
    createdBy: req.user.id,
    isBirthday,
    birthdayMemberId: isBirthday ? birthdayMemberId : null,
    createdAt: new Date().toISOString(),
  };
  db.reminders.push(reminder);
  persistDb();
  io.to(req.house.id).emit('reminderCreated', reminder);
  sendReminderPush({ house: req.house, reminder, creator: req.user }).catch((error) => {
    console.warn('Reminder push failed:', error.message);
  });
  res.status(201).json(reminder);
});

app.put('/houses/:houseId/reminders/:reminderId', requireAuth, requireHouseMember, (req, res) => {
  const reminder = db.reminders.find((item) => item.id === req.params.reminderId && item.houseId === req.house.id);
  if (!reminder) return res.status(404).json({ message: 'Reminder not found' });
  const isBirthday = req.body.isBirthday === true;
  const birthdayMemberId = req.body.birthdayMemberId ? idOf(req.body.birthdayMemberId) : null;
  if (isBirthday) {
    if (!birthdayMemberId) {
      return res.status(400).json({ message: 'Choose the birthday family member' });
    }
    const isHouseMember = req.house.members.some((member) => idOf(member.userId) === birthdayMemberId);
    if (!isHouseMember) {
      return res.status(400).json({ message: 'Birthday member is not in this house' });
    }
  }

  reminder.title = req.body.title || reminder.title;
  reminder.note = req.body.note ?? reminder.note;
  reminder.dueAt = req.body.dueAt || reminder.dueAt;
  reminder.isBirthday = isBirthday;
  reminder.birthdayMemberId = isBirthday ? birthdayMemberId : null;
  persistDb();

  io.to(req.house.id).emit('reminderUpdated', reminder);
  res.json(reminder);
});

app.delete('/houses/:houseId/reminders/:reminderId', requireAuth, requireHouseMember, (req, res) => {
  const index = db.reminders.findIndex((item) => item.id === req.params.reminderId && item.houseId === req.house.id);
  if (index === -1) return res.status(404).json({ message: 'Reminder not found' });

  const [reminder] = db.reminders.splice(index, 1);
  persistDb();
  io.to(req.house.id).emit('reminderDeleted', { id: reminder.id, houseId: req.house.id });
  res.json({ ok: true, id: reminder.id });
});

app.post('/houses/:houseId/messages', requireAuth, requireHouseMember, (req, res) => {
  const message = createHouseMessage({
    houseId: req.house.id,
    senderId: req.user.id,
    text: req.body.text,
  });
  res.status(201).json(message);
});

app.post('/houses/:houseId/shortcuts', requireAuth, requireHouseMember, (req, res) => {
  const shortcut = {
    id: uuid(),
    houseId: req.house.id,
    label: req.body.label,
    actionType: req.body.actionType,
    actionValue: req.body.actionValue,
    createdBy: req.user.id,
  };
  db.shortcuts.push(shortcut);
  persistDb();
  io.to(req.house.id).emit('shortcutCreated', shortcut);
  res.status(201).json(shortcut);
});

app.put('/houses/:houseId/shortcuts/:shortcutId', requireAuth, requireHouseMember, (req, res) => {
  const shortcut = db.shortcuts.find((item) => item.id === req.params.shortcutId && item.houseId === req.house.id && item.createdBy === req.user.id);
  if (!shortcut) return res.status(404).json({ message: 'Shortcut not found' });

  shortcut.label = req.body.label || shortcut.label;
  shortcut.actionType = req.body.actionType || shortcut.actionType;
  shortcut.actionValue = req.body.actionValue || shortcut.actionValue;
  persistDb();

  io.to(req.house.id).emit('shortcutUpdated', shortcut);
  res.json(shortcut);
});

app.delete('/houses/:houseId/shortcuts/:shortcutId', requireAuth, requireHouseMember, (req, res) => {
  const index = db.shortcuts.findIndex((item) => item.id === req.params.shortcutId && item.houseId === req.house.id && item.createdBy === req.user.id);
  if (index === -1) return res.status(404).json({ message: 'Shortcut not found' });

  const [shortcut] = db.shortcuts.splice(index, 1);
  persistDb();
  io.to(req.house.id).emit('shortcutDeleted', { id: shortcut.id, houseId: req.house.id, createdBy: req.user.id });
  res.json({ ok: true, id: shortcut.id });
});

io.use((socket, next) => {
  try {
    const payload = jwt.verify(socket.handshake.auth?.token || '', jwtSecret);
    socket.userId = payload.userId;
    next();
  } catch {
    next(new Error('Unauthorized'));
  }
});

io.on('connection', (socket) => {
  socket.on('joinHouse', (houseId) => {
    const house = db.houses.find((item) => item.id === houseId);
    if (house?.members.some((member) => member.userId === socket.userId)) {
      socket.join(houseId);
    }
  });
});

const port = Number(process.env.PORT || 8080);
await connectDataStore().catch((error) => {
  console.warn('MongoDB connection failed. Data will be stored in memory only.', {
    message: error.message,
  });
});

server.listen(port, () => {
  console.log(`Hoomy backend listening on ${port}`);
});
