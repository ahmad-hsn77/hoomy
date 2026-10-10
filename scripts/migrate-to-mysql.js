import 'dotenv/config';
import { MongoClient } from 'mongodb';
import mysql from 'mysql2/promise';
import { createLocationCipher } from '../src/location-security.js';
import {
  arrayDataKeys,
  objectDataKeys,
  publicStoredRecord,
  recordIdFor,
  snapshotCounts,
  writeJsonBackup,
} from './datastore-helpers.js';

const mongoUri = process.env.MONGODB_URI?.trim();
const mysqlUrl = process.env.MYSQL_URL?.trim() || process.env.DATABASE_URL?.trim();
const databaseName = process.env.MONGODB_DB?.trim() || 'hoomy';
const collectionName = process.env.MONGODB_COLLECTION?.trim() || 'app_state';
const documentId = process.env.MONGODB_DOCUMENT_ID?.trim() || 'main';
const dryRun = process.argv.includes('--dry-run');

if (!mongoUri) {
  console.error('MONGODB_URI is required so data can be copied from MongoDB.');
  process.exit(1);
}

if (!mysqlUrl) {
  console.error('MYSQL_URL or DATABASE_URL is required.');
  process.exit(1);
}

async function readMongoState() {
  const client = new MongoClient(mongoUri);
  try {
    await client.connect();
    const database = client.db(databaseName);
    const legacy = await database.collection(collectionName).findOne({ _id: documentId });
    if (legacy?.state) return legacy.state;

    const state = {};
    for (const key of arrayDataKeys) {
      const rows = await database
        .collection(key)
        .find({})
        .sort({ __order: 1, createdAt: 1 })
        .toArray();
      state[key] = rows.map(publicStoredRecord);
    }
    for (const key of objectDataKeys) {
      const meta = await database.collection('app_meta').findOne({ _id: key });
      state[key] = meta?.value || {};
    }
    return state;
  } finally {
    await client.close();
  }
}

async function ensureMysqlSchema(connection) {
  for (const key of arrayDataKeys) {
    await connection.execute(`
      CREATE TABLE IF NOT EXISTS \`${key}\` (
        id VARCHAR(191) NOT NULL PRIMARY KEY,
        sort_order INT NOT NULL DEFAULT 0,
        data JSON NOT NULL,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
  }
  await connection.execute(`
    CREATE TABLE IF NOT EXISTS app_meta (
      id VARCHAR(191) NOT NULL PRIMARY KEY,
      data JSON NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

const locationCipher = createLocationCipher();
const state = locationCipher.encryptState(locationCipher.decryptState(await readMongoState()));
const backupPath = await writeJsonBackup('before-mysql-migration-state', state);
console.log('Backup written before MySQL migration:', backupPath);
console.log('Source counts:', snapshotCounts(state));

if (dryRun) {
  console.log('Dry run only. MySQL was not changed.');
  process.exit(0);
}

const connection = await mysql.createConnection(mysqlUrl);
try {
  await ensureMysqlSchema(connection);
  await connection.beginTransaction();
  for (const key of arrayDataKeys) {
    await connection.query(`DELETE FROM \`${key}\``);
    const records = Array.isArray(state[key]) ? state[key] : [];
    for (let index = 0; index < records.length; index += 1) {
      await connection.execute(
        `INSERT INTO \`${key}\` (id, sort_order, data) VALUES (?, ?, ?)`,
        [recordIdFor(key, records[index], index), index, JSON.stringify(records[index])],
      );
    }
    console.log(`Copied ${records.length} records to MySQL table ${key}`);
  }
  for (const key of objectDataKeys) {
    await connection.execute(
      'REPLACE INTO app_meta (id, data) VALUES (?, ?)',
      [key, JSON.stringify(state[key] || {})],
    );
  }
  await connection.commit();
  console.log('MySQL migration complete.');
} catch (error) {
  await connection.rollback();
  throw error;
} finally {
  await connection.end();
}
