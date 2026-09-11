const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const http = require('http');

const cors = require('cors');
const express = require('express');
const jwt = require('jsonwebtoken');
const { Server } = require('socket.io');

const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || 'dev-hoomy-secret-change-me';
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const DATA_FILE =
  process.env.HOOMY_DATA_FILE || path.join(__dirname, 'data', 'hoomy.json');
const DEFAULT_MESSAGE_LIMIT = 30;
const MAX_MESSAGE_LIMIT = 50;

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: CORS_ORIGIN,
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
  },
});

app.use(cors({ origin: CORS_ORIGIN }));
app.use(express.json({ limit: '25mb' }));

let db = loadDatabase();

function loadDatabase() {
  try {
    if (fs.existsSync(DATA_FILE)) {
      return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
    }
  } catch (error) {
    console.error('Failed to read data file, starting with empty store.', error);
  }
  return {
    users: [],
    houses: [],
    memberships: [],
    alerts: [],
    reminders: [],
    messages: [],
    shortcuts: [],
    devices: [],
    resetRequests: [],
  };
}

function saveDatabase() {
  fs.mkdirSync(path.dirname(DATA_FILE), { recursive: true });
  fs.writeFileSync(DATA_FILE, JSON.stringify(db, null, 2));
}

function id(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString('hex')}`;
}

function now() {
  return new Date().toISOString();
}

function normalizeString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function normalizeNullableString(value) {
  const text = normalizeString(value);
  return text.length ? text : null;
}

function normalizePreferences(value) {
  return {
    needAlerts: value?.needAlerts !== false,
    emergencyAlerts: value?.emergencyAlerts !== false,
    chatMessages: value?.chatMessages !== false,
  };
}

function publicUser(user, relation) {
  return {
    id: user.id,
    name: user.name,
    email: user.email || null,
    phone: user.phone || null,
    childMode: user.childMode === true,
    relation: relation || user.relation || 'Member',
    outsideHouse: user.outsideHouse !== false,
    birthDate: user.birthDate || null,
    lastLocation: user.lastLocation || null,
    locationStatusUpdatedAt: user.locationStatusUpdatedAt || null,
    notificationPreferences: normalizePreferences(user.notificationPreferences),
  };
}

function publicHouse(house) {
  return {
    id: house.id,
    name: house.name,
    address: house.address || '',
    location: house.location || null,
    createdBy: house.createdBy,
    specialNumber: house.specialNumber,
  };
}

function membershipsForUser(userId) {
  return db.memberships.filter((item) => item.userId === userId);
}

function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ message: 'Missing token' });

  try {
    const payload = jwt.verify(token, JWT_SECRET);
    const user = db.users.find((item) => item.id === payload.sub);
    if (!user) return res.status(401).json({ message: 'Invalid token' });
    req.user = user;
    next();
  } catch (_) {
    res.status(401).json({ message: 'Invalid token' });
  }
}

function signToken(user) {
  return jwt.sign({ sub: user.id }, JWT_SECRET, { expiresIn: '90d' });
}

function requireHouse(req, res, next) {
  const house = db.houses.find((item) => item.id === req.params.houseId);
  if (!house) return res.status(404).json({ message: 'House not found' });

  const membership = db.memberships.find(
    (item) => item.houseId === house.id && item.userId === req.user.id,
  );
  if (!membership) return res.status(403).json({ message: 'Not a house member' });

  req.house = house;
  req.membership = membership;
  next();
}

function houseMembers(houseId) {
  return db.memberships
    .filter((item) => item.houseId === houseId)
    .map((membership) => {
      const user = db.users.find((item) => item.id === membership.userId);
      return user ? publicUser(user, membership.relation) : null;
    })
    .filter(Boolean);
}

function userHouses(userId) {
  return membershipsForUser(userId)
    .map((membership) => db.houses.find((house) => house.id === membership.houseId))
    .filter(Boolean)
    .map(publicHouse);
}

function currentHouseForUser(userId) {
  const membership = membershipsForUser(userId)[0];
  if (!membership) return null;
  return db.houses.find((house) => house.id === membership.houseId) || null;
}

function messagePage(houseId, query) {
  const limit = clampLimit(query.limit);
  const before = parseDateQuery(query.before);
  const newestFirst = db.messages
    .filter((message) => {
      if (message.houseId !== houseId) return false;
      if (!before) return true;
      return new Date(message.createdAt).getTime() < before.getTime();
    })
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, limit);

  return newestFirst.reverse().map(publicMessage);
}

function clampLimit(value) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return DEFAULT_MESSAGE_LIMIT;
  return Math.min(parsed, MAX_MESSAGE_LIMIT);
}

function parseDateQuery(value) {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

function publicAlert(alert) {
  return {
    id: alert.id,
    houseId: alert.houseId,
    title: alert.title,
    note: alert.note || '',
    quantity: alert.quantity || '',
    emergency: alert.emergency === true,
    targetMemberIds: alert.targetMemberIds || [],
    createdBy: alert.createdBy,
    createdAt: alert.createdAt,
    status: alert.status || 'open',
    bought: alert.bought || null,
  };
}

function publicReminder(reminder) {
  return {
    id: reminder.id,
    houseId: reminder.houseId,
    title: reminder.title,
    note: reminder.note || '',
    dueAt: reminder.dueAt,
    ringTimes: reminder.ringTimes || [],
    recurrence: reminder.recurrence || 'once',
    recurrenceWeekdays: reminder.recurrenceWeekdays || [],
    createdBy: reminder.createdBy,
    isBirthday: reminder.isBirthday === true,
    birthdayMemberId: reminder.birthdayMemberId || null,
  };
}

function publicMessage(message) {
  return {
    id: message.id,
    houseId: message.houseId,
    senderId: message.senderId,
    text: message.text || '',
    createdAt: message.createdAt,
    system: message.system === true,
    receivedBy: message.receivedBy || [],
    seenBy: message.seenBy || [],
    replyToMessageId: message.replyToMessageId || null,
    replyToSenderId: message.replyToSenderId || null,
    replyToText: message.replyToText || null,
    edited: message.edited === true,
    editedAt: message.editedAt || null,
    audio: message.audio === true,
    audioBase64: message.audioBase64 || null,
    audioMimeType: message.audioMimeType || null,
    audioDurationSeconds: message.audioDurationSeconds || null,
    image: message.image === true,
    imageBase64: message.imageBase64 || null,
    imageMimeType: message.imageMimeType || null,
    reactions: message.reactions || [],
  };
}

function publicShortcut(shortcut) {
  return {
    id: shortcut.id,
    houseId: shortcut.houseId,
    label: shortcut.label,
    actionType: shortcut.actionType,
    actionValue: shortcut.actionValue,
    createdBy: shortcut.createdBy,
  };
}

function houseStatePayload(user, house) {
  return {
    user: publicUser(user, membershipRelation(user.id, house.id)),
    house: publicHouse(house),
    houses: userHouses(user.id),
    members: houseMembers(house.id),
    alerts: db.alerts
      .filter((item) => item.houseId === house.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      .map(publicAlert),
    reminders: db.reminders
      .filter((item) => item.houseId === house.id)
      .sort((a, b) => new Date(a.dueAt) - new Date(b.dueAt))
      .map(publicReminder),
    messages: messagePage(house.id, { limit: DEFAULT_MESSAGE_LIMIT }),
    shortcuts: db.shortcuts
      .filter((item) => item.houseId === house.id && item.createdBy === user.id)
      .map(publicShortcut),
  };
}

function houseSummaryPayload(user, house) {
  return {
    user: publicUser(user, membershipRelation(user.id, house.id)),
    house: publicHouse(house),
    houses: userHouses(user.id),
  };
}

function membershipRelation(userId, houseId) {
  return (
    db.memberships.find((item) => item.userId === userId && item.houseId === houseId)
      ?.relation || 'Member'
  );
}

function emitHouse(houseId, event, payload) {
  io.to(houseId).emit(event, payload);
}

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.get('/app/update', (_req, res) => {
  res.json({ updateAvailable: false });
});

app.post('/auth/register', (req, res) => {
  const name = normalizeString(req.body.name) || 'Member';
  const email = normalizeNullableString(req.body.email)?.toLowerCase();
  const phone = normalizeNullableString(req.body.phone);

  const existing = db.users.find(
    (user) => (email && user.email === email) || (phone && user.phone === phone),
  );
  if (existing) {
    return res.json({
      token: signToken(existing),
      user: publicUser(existing),
      houses: userHouses(existing.id),
      ...(currentHouseForUser(existing.id)
        ? houseStatePayload(existing, currentHouseForUser(existing.id))
        : {}),
    });
  }

  const user = {
    id: id('u'),
    name,
    email,
    phone,
    password: req.body.password || null,
    childMode: req.body.childMode === true,
    relation: 'Member',
    outsideHouse: true,
    notificationPreferences: normalizePreferences(),
  };
  db.users.push(user);
  saveDatabase();

  res.status(201).json({
    token: signToken(user),
    user: publicUser(user),
    houses: [],
  });
});

app.post('/auth/login', (req, res) => {
  const email = normalizeNullableString(req.body.email)?.toLowerCase();
  const phone = normalizeNullableString(req.body.phone);
  const childName = normalizeNullableString(req.body.childName);
  const user = db.users.find(
    (item) =>
      (email && item.email === email) ||
      (phone && item.phone === phone) ||
      (childName && item.childMode && item.name.toLowerCase() === childName.toLowerCase()),
  );

  if (!user) return res.status(404).json({ message: 'User not found' });
  const house = currentHouseForUser(user.id);
  res.json({
    token: signToken(user),
    user: publicUser(user, house ? membershipRelation(user.id, house.id) : undefined),
    houses: userHouses(user.id),
    ...(house ? houseStatePayload(user, house) : {}),
  });
});

app.post('/auth/forgot-password', (req, res) => {
  db.resetRequests.push({ id: id('reset'), at: now(), email: req.body.email, phone: req.body.phone });
  saveDatabase();
  res.json({ ok: true });
});

app.post('/auth/reset-password', (req, res) => {
  const email = normalizeNullableString(req.body.email)?.toLowerCase();
  const phone = normalizeNullableString(req.body.phone);
  const user = db.users.find((item) => (email && item.email === email) || (phone && item.phone === phone));
  if (!user) return res.status(404).json({ message: 'User not found' });
  user.password = req.body.newPassword || user.password;
  saveDatabase();
  res.json({ ok: true });
});

app.get('/auth/me', requireAuth, (req, res) => {
  const house = currentHouseForUser(req.user.id);
  res.json({
    user: publicUser(req.user, house ? membershipRelation(req.user.id, house.id) : undefined),
    houses: userHouses(req.user.id),
    ...(house ? houseStatePayload(req.user, house) : {}),
  });
});

app.put('/users/me/profile', requireAuth, (req, res) => {
  if (req.body.name !== undefined) req.user.name = normalizeString(req.body.name) || req.user.name;
  if (Object.prototype.hasOwnProperty.call(req.body, 'phone')) {
    req.user.phone = normalizeNullableString(req.body.phone);
  }
  if (Object.prototype.hasOwnProperty.call(req.body, 'birthDate')) {
    req.user.birthDate = normalizeNullableString(req.body.birthDate);
  }
  saveDatabase();
  res.json(publicUser(req.user));
});

app.put('/users/me/notification-preferences', requireAuth, (req, res) => {
  req.user.notificationPreferences = normalizePreferences(req.body);
  saveDatabase();
  res.json(publicUser(req.user));
});

app.post('/devices/fcm-token', requireAuth, (req, res) => {
  const token = normalizeString(req.body.token);
  if (token && !db.devices.some((item) => item.userId === req.user.id && item.token === token)) {
    db.devices.push({ userId: req.user.id, token, createdAt: now() });
    saveDatabase();
  }
  res.json({ ok: true });
});

app.post('/houses', requireAuth, (req, res) => {
  const house = {
    id: id('h'),
    name: normalizeString(req.body.name) || 'House',
    role: normalizeString(req.body.role) || 'Member',
    address: normalizeString(req.body.address),
    location: req.body.location || null,
    createdBy: req.user.id,
    specialNumber: crypto.randomInt(100000, 999999).toString(),
    createdAt: now(),
  };
  db.houses.push(house);
  db.memberships.push({
    houseId: house.id,
    userId: req.user.id,
    relation: house.role,
    createdAt: now(),
  });
  saveDatabase();
  res.status(201).json(houseStatePayload(req.user, house));
});

app.post('/houses/join', requireAuth, (req, res) => {
  const houseCode = normalizeString(req.body.houseCode);
  const house = db.houses.find((item) => item.specialNumber === houseCode || item.id === houseCode);
  if (!house) return res.status(404).json({ message: 'House not found' });
  if (!db.memberships.some((item) => item.houseId === house.id && item.userId === req.user.id)) {
    db.memberships.push({
      houseId: house.id,
      userId: req.user.id,
      relation: normalizeString(req.body.relation) || 'Member',
      createdAt: now(),
    });
    saveDatabase();
  }
  res.json(houseStatePayload(req.user, house));
});

app.get('/houses/:houseId/state', requireAuth, requireHouse, (req, res) => {
  res.json(houseStatePayload(req.user, req.house));
});

app.get('/houses/:houseId/summary', requireAuth, requireHouse, (req, res) => {
  res.json(houseSummaryPayload(req.user, req.house));
});

app.get('/houses/:houseId/sections/members', requireAuth, requireHouse, (req, res) => {
  res.json({ members: houseMembers(req.house.id) });
});

app.get('/houses/:houseId/sections/alerts', requireAuth, requireHouse, (req, res) => {
  res.json({
    alerts: db.alerts
      .filter((item) => item.houseId === req.house.id)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
      .map(publicAlert),
  });
});

app.get('/houses/:houseId/sections/reminders', requireAuth, requireHouse, (req, res) => {
  res.json({
    reminders: db.reminders
      .filter((item) => item.houseId === req.house.id)
      .sort((a, b) => new Date(a.dueAt) - new Date(b.dueAt))
      .map(publicReminder),
  });
});

app.get('/houses/:houseId/sections/messages', requireAuth, requireHouse, (req, res) => {
  res.json({ messages: messagePage(req.house.id, req.query) });
});

app.get('/houses/:houseId/sections/shortcuts', requireAuth, requireHouse, (req, res) => {
  res.json({
    shortcuts: db.shortcuts
      .filter((item) => item.houseId === req.house.id && item.createdBy === req.user.id)
      .map(publicShortcut),
  });
});

app.put('/houses/:houseId/location', requireAuth, requireHouse, (req, res) => {
  req.house.location = req.body.location || null;
  req.house.address = normalizeString(req.body.address);
  saveDatabase();
  res.json(publicHouse(req.house));
});

app.post('/houses/:houseId/members', requireAuth, requireHouse, (req, res) => {
  const email = normalizeNullableString(req.body.email)?.toLowerCase();
  const phone = normalizeNullableString(req.body.phone);
  let user = db.users.find((item) => (email && item.email === email) || (phone && item.phone === phone));
  if (!user) {
    user = {
      id: id('u'),
      name: normalizeString(req.body.name) || 'Member',
      email,
      phone,
      password: null,
      childMode: req.body.childMode === true,
      outsideHouse: true,
      notificationPreferences: normalizePreferences(),
    };
    db.users.push(user);
  }
  let membership = db.memberships.find((item) => item.houseId === req.house.id && item.userId === user.id);
  if (!membership) {
    membership = {
      houseId: req.house.id,
      userId: user.id,
      relation: normalizeString(req.body.relation) || 'Member',
      createdAt: now(),
    };
    db.memberships.push(membership);
  }
  saveDatabase();
  const payload = { houseId: req.house.id, relation: membership.relation, user: publicUser(user, membership.relation) };
  emitHouse(req.house.id, 'memberAdded', payload);
  res.status(201).json(payload);
});

app.put('/houses/:houseId/members/me/status', requireAuth, requireHouse, (req, res) => {
  req.user.outsideHouse = req.body.outsideHouse !== false;
  req.user.lastLocation = req.body.location || null;
  req.user.locationStatusUpdatedAt = now();
  saveDatabase();
  const payload = { houseId: req.house.id, relation: req.membership.relation, user: publicUser(req.user, req.membership.relation) };
  emitHouse(req.house.id, 'memberUpdated', payload);
  res.json(payload);
});

app.post('/houses/:houseId/alerts', requireAuth, requireHouse, (req, res) => {
  const alert = {
    id: id('a'),
    houseId: req.house.id,
    title: normalizeString(req.body.title) || 'Need',
    note: normalizeString(req.body.note),
    quantity: normalizeString(req.body.quantity),
    emergency: req.body.emergency === true,
    targetMemberIds: Array.isArray(req.body.targetMemberIds) ? req.body.targetMemberIds.map(String) : [],
    createdBy: req.user.id,
    createdAt: now(),
    status: 'open',
  };
  db.alerts.push(alert);
  saveDatabase();
  const payload = publicAlert(alert);
  emitHouse(req.house.id, 'alertCreated', payload);
  res.status(201).json(payload);
});

app.post('/houses/:houseId/alerts/:alertId/bought', requireAuth, requireHouse, (req, res) => {
  const alert = db.alerts.find((item) => item.houseId === req.house.id && item.id === req.params.alertId);
  if (!alert) return res.status(404).json({ message: 'Alert not found' });
  alert.status = 'bought';
  alert.bought = {
    by: req.user.id,
    quantity: normalizeString(req.body.quantity),
    price: normalizeString(req.body.price),
    at: now(),
  };
  const message = {
    id: id('m'),
    houseId: req.house.id,
    senderId: req.user.id,
    text: `${alert.title} bought`,
    createdAt: now(),
    system: true,
    receivedBy: [req.user.id],
    seenBy: [req.user.id],
    reactions: [],
  };
  db.messages.push(message);
  saveDatabase();
  const alertPayload = publicAlert(alert);
  emitHouse(req.house.id, 'alertBought', alertPayload);
  emitHouse(req.house.id, 'messageCreated', publicMessage(message));
  res.json(alertPayload);
});

app.delete('/houses/:houseId/alerts/:alertId', requireAuth, requireHouse, (req, res) => {
  const before = db.alerts.length;
  db.alerts = db.alerts.filter((item) => !(item.houseId === req.house.id && item.id === req.params.alertId));
  if (db.alerts.length === before) return res.status(404).json({ message: 'Alert not found' });
  saveDatabase();
  emitHouse(req.house.id, 'alertDeleted', { id: req.params.alertId, houseId: req.house.id });
  res.json({ ok: true });
});

app.post('/houses/:houseId/reminders', requireAuth, requireHouse, (req, res) => {
  const reminder = upsertReminder(req, id('r'));
  const payload = publicReminder(reminder);
  emitHouse(req.house.id, 'reminderCreated', payload);
  res.status(201).json(payload);
});

app.put('/houses/:houseId/reminders/:reminderId', requireAuth, requireHouse, (req, res) => {
  const reminder = upsertReminder(req, req.params.reminderId);
  const payload = publicReminder(reminder);
  emitHouse(req.house.id, 'reminderUpdated', payload);
  res.json(payload);
});

function upsertReminder(req, reminderId) {
  let reminder = db.reminders.find((item) => item.houseId === req.house.id && item.id === reminderId);
  if (!reminder) {
    reminder = { id: reminderId, houseId: req.house.id, createdBy: req.user.id };
    db.reminders.push(reminder);
  }
  reminder.title = normalizeString(req.body.title) || 'Reminder';
  reminder.note = normalizeString(req.body.note);
  reminder.dueAt = normalizeString(req.body.dueAt) || now();
  reminder.ringTimes = Array.isArray(req.body.ringTimes) ? req.body.ringTimes.map(String) : [];
  reminder.recurrence = ['once', 'daily', 'weekly'].includes(req.body.recurrence) ? req.body.recurrence : 'once';
  reminder.recurrenceWeekdays = Array.isArray(req.body.recurrenceWeekdays)
    ? req.body.recurrenceWeekdays.map(Number).filter((day) => day >= 1 && day <= 7)
    : [];
  reminder.isBirthday = req.body.isBirthday === true;
  reminder.birthdayMemberId = normalizeNullableString(req.body.birthdayMemberId);
  saveDatabase();
  return reminder;
}

app.delete('/houses/:houseId/reminders/:reminderId', requireAuth, requireHouse, (req, res) => {
  const before = db.reminders.length;
  db.reminders = db.reminders.filter((item) => !(item.houseId === req.house.id && item.id === req.params.reminderId));
  if (db.reminders.length === before) return res.status(404).json({ message: 'Reminder not found' });
  saveDatabase();
  emitHouse(req.house.id, 'reminderDeleted', { id: req.params.reminderId, houseId: req.house.id });
  res.json({ ok: true });
});

app.post('/houses/:houseId/messages', requireAuth, requireHouse, (req, res) => {
  const replyTo = req.body.replyToMessageId
    ? db.messages.find((item) => item.houseId === req.house.id && item.id === req.body.replyToMessageId)
    : null;
  const message = {
    id: id('m'),
    houseId: req.house.id,
    senderId: req.user.id,
    text: normalizeString(req.body.text),
    createdAt: now(),
    system: false,
    receivedBy: [req.user.id],
    seenBy: [req.user.id],
    replyToMessageId: replyTo?.id || null,
    replyToSenderId: replyTo?.senderId || null,
    replyToText: replyTo?.text || null,
    edited: false,
    audio: req.body.audio === true,
    audioBase64: req.body.audioBase64 || null,
    audioMimeType: req.body.audioMimeType || null,
    audioDurationSeconds: Number.isFinite(Number(req.body.audioDurationSeconds))
      ? Number(req.body.audioDurationSeconds)
      : null,
    image: req.body.image === true,
    imageBase64: req.body.imageBase64 || null,
    imageMimeType: req.body.imageMimeType || null,
    reactions: [],
  };
  db.messages.push(message);
  saveDatabase();
  const payload = publicMessage(message);
  emitHouse(req.house.id, 'messageCreated', payload);
  res.status(201).json(payload);
});

app.put('/houses/:houseId/messages/:messageId', requireAuth, requireHouse, (req, res) => {
  const message = db.messages.find((item) => item.houseId === req.house.id && item.id === req.params.messageId);
  if (!message) return res.status(404).json({ message: 'Message not found' });
  if (message.senderId !== req.user.id) return res.status(403).json({ message: 'Cannot edit this message' });
  message.text = normalizeString(req.body.text);
  message.edited = true;
  message.editedAt = now();
  saveDatabase();
  const payload = publicMessage(message);
  emitHouse(req.house.id, 'messageUpdated', payload);
  res.json(payload);
});

app.post('/houses/:houseId/messages/:messageId/received', requireAuth, requireHouse, (req, res) => {
  const message = db.messages.find((item) => item.houseId === req.house.id && item.id === req.params.messageId);
  if (!message) return res.status(404).json({ message: 'Message not found' });
  message.receivedBy = Array.from(new Set([...(message.receivedBy || []), req.user.id]));
  saveDatabase();
  const payload = publicMessage(message);
  emitHouse(req.house.id, 'messageUpdated', payload);
  res.json(payload);
});

app.post('/houses/:houseId/messages/seen', requireAuth, requireHouse, (req, res) => {
  const updated = [];
  for (const message of db.messages.filter((item) => item.houseId === req.house.id)) {
    if (!message.seenBy?.includes(req.user.id)) {
      message.seenBy = Array.from(new Set([...(message.seenBy || []), req.user.id]));
      message.receivedBy = Array.from(new Set([...(message.receivedBy || []), req.user.id]));
      updated.push(publicMessage(message));
    }
  }
  saveDatabase();
  for (const message of updated) emitHouse(req.house.id, 'messageUpdated', message);
  res.json({ messages: updated });
});

app.put('/houses/:houseId/messages/:messageId/reaction', requireAuth, requireHouse, (req, res) => {
  const message = db.messages.find((item) => item.houseId === req.house.id && item.id === req.params.messageId);
  if (!message) return res.status(404).json({ message: 'Message not found' });
  message.reactions = (message.reactions || []).filter((item) => item.userId !== req.user.id);
  const emoji = normalizeString(req.body.emoji);
  if (emoji) message.reactions.push({ userId: req.user.id, emoji, reactedAt: now() });
  saveDatabase();
  const payload = publicMessage(message);
  emitHouse(req.house.id, 'messageUpdated', payload);
  res.json(payload);
});

app.post('/houses/:houseId/shortcuts', requireAuth, requireHouse, (req, res) => {
  const shortcut = upsertShortcut(req, id('s'));
  const payload = publicShortcut(shortcut);
  emitHouse(req.house.id, 'shortcutCreated', payload);
  res.status(201).json(payload);
});

app.put('/houses/:houseId/shortcuts/:shortcutId', requireAuth, requireHouse, (req, res) => {
  const shortcut = upsertShortcut(req, req.params.shortcutId);
  const payload = publicShortcut(shortcut);
  emitHouse(req.house.id, 'shortcutUpdated', payload);
  res.json(payload);
});

function upsertShortcut(req, shortcutId) {
  let shortcut = db.shortcuts.find(
    (item) => item.houseId === req.house.id && item.id === shortcutId && item.createdBy === req.user.id,
  );
  if (!shortcut) {
    shortcut = { id: shortcutId, houseId: req.house.id, createdBy: req.user.id };
    db.shortcuts.push(shortcut);
  }
  shortcut.label = normalizeString(req.body.label) || 'Shortcut';
  shortcut.actionType = normalizeString(req.body.actionType) || 'call';
  shortcut.actionValue = normalizeString(req.body.actionValue);
  saveDatabase();
  return shortcut;
}

app.delete('/houses/:houseId/shortcuts/:shortcutId', requireAuth, requireHouse, (req, res) => {
  const before = db.shortcuts.length;
  db.shortcuts = db.shortcuts.filter(
    (item) => !(item.houseId === req.house.id && item.id === req.params.shortcutId && item.createdBy === req.user.id),
  );
  if (db.shortcuts.length === before) return res.status(404).json({ message: 'Shortcut not found' });
  saveDatabase();
  emitHouse(req.house.id, 'shortcutDeleted', {
    id: req.params.shortcutId,
    houseId: req.house.id,
    createdBy: req.user.id,
  });
  res.json({ ok: true });
});

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token;
    const payload = jwt.verify(token, JWT_SECRET);
    const user = db.users.find((item) => item.id === payload.sub);
    if (!user) return next(new Error('Unauthorized'));
    socket.user = user;
    next();
  } catch (_) {
    next(new Error('Unauthorized'));
  }
});

io.on('connection', (socket) => {
  socket.on('joinHouse', (houseId) => {
    const isMember = db.memberships.some(
      (item) => item.houseId === houseId && item.userId === socket.user.id,
    );
    if (isMember) socket.join(houseId);
  });
});

app.use((req, res) => {
  res.status(404).json({ message: `Route not found: ${req.method} ${req.path}` });
});

server.listen(PORT, () => {
  console.log(`Hoomy backend listening on ${PORT}`);
});
