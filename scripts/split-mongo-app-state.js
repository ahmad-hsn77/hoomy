import 'dotenv/config';
import { MongoClient } from 'mongodb';
import { createLocationCipher } from '../src/location-security.js';
import {
  arrayDataKeys,
  objectDataKeys,
  snapshotCounts,
  storedRecord,
  writeJsonBackup,
} from './datastore-helpers.js';

const uri = process.env.MONGODB_URI?.trim();
const databaseName = process.env.MONGODB_DB?.trim() || 'hoomy';
const collectionName = process.env.MONGODB_COLLECTION?.trim() || 'app_state';
const documentId = process.env.MONGODB_DOCUMENT_ID?.trim() || 'main';
const dryRun = process.argv.includes('--dry-run');
const allowMessageCountDrop =
  process.env.ALLOW_MESSAGE_COUNT_DROP === 'true' ||
  process.argv.includes('--allow-message-count-drop');

if (!uri) {
  console.error('MONGODB_URI is required.');
  process.exit(1);
}

const client = new MongoClient(uri);
try {
  await client.connect();
  const database = client.db(databaseName);
  const legacy = await database.collection(collectionName).findOne({ _id: documentId });
  if (!legacy?.state) {
    console.error(`No state found at ${databaseName}.${collectionName}/${documentId}`);
    process.exit(1);
  }

  const backupPath = await writeJsonBackup('before-split-mongo-app-state', legacy);
  console.log('Backup written before split:', backupPath);
  console.log('Source counts:', snapshotCounts(legacy.state));
  const locationCipher = createLocationCipher();
  legacy.state = locationCipher.encryptState(locationCipher.decryptState(legacy.state));

  if (dryRun) {
    console.log('Dry run only. No collections were changed.');
    process.exit(0);
  }

  for (const key of arrayDataKeys) {
    const records = Array.isArray(legacy.state[key]) ? legacy.state[key] : [];
    const collection = database.collection(key);
    if (key === 'messages') {
      const existingCount = await collection.countDocuments();
      if (!allowMessageCountDrop && existingCount > records.length) {
        throw new Error(
          `Refusing to split ${records.length} messages over existing ${existingCount} messages. ` +
          'Pass --allow-message-count-drop only for an intentional restore.'
        );
      }
      if (records.length > 0) {
        await collection.bulkWrite(
          records.map((item, index) => {
            const record = storedRecord(key, item, index);
            return {
              updateOne: {
                filter: { _id: record._id },
                update: { $set: record },
                upsert: true,
              },
            };
          }),
          { ordered: false },
        );
      }
      console.log(`Upserted ${records.length} records to ${key}`);
      continue;
    }

    await collection.deleteMany({});
    if (records.length > 0) {
      await collection.insertMany(records.map((item, index) => storedRecord(key, item, index)));
    }
    console.log(`Wrote ${records.length} records to ${key}`);
  }

  const meta = database.collection('app_meta');
  for (const key of objectDataKeys) {
    await meta.updateOne(
      { _id: key },
      { $set: { value: legacy.state[key] || {}, updatedAt: new Date() } },
      { upsert: true },
    );
    console.log(`Wrote metadata ${key}`);
  }

  await database.collection(collectionName).updateOne({ _id: documentId }, { $set: { state: legacy.state } });
  console.log('Mongo split complete. The original app_state document was kept with encrypted locations.');
} finally {
  await client.close();
}
