import 'dotenv/config';
import { MongoClient } from 'mongodb';
import { snapshotCounts, writeJsonBackup } from './datastore-helpers.js';

const uri = process.env.MONGODB_URI?.trim();
const databaseName = process.env.MONGODB_DB?.trim() || 'hoomy';
const collectionName = process.env.MONGODB_COLLECTION?.trim() || 'app_state';
const documentId = process.env.MONGODB_DOCUMENT_ID?.trim() || 'main';

if (!uri) {
  console.error('MONGODB_URI is required.');
  process.exit(1);
}

const client = new MongoClient(uri);
try {
  await client.connect();
  const collection = client.db(databaseName).collection(collectionName);
  const document = await collection.findOne({ _id: documentId });
  if (!document?.state) {
    console.error(`No state found at ${databaseName}.${collectionName}/${documentId}`);
    process.exit(1);
  }

  const filePath = await writeJsonBackup('mongo-app-state', document);
  console.log('Mongo app_state backup written:', filePath);
  console.log('Counts:', snapshotCounts(document.state));
} finally {
  await client.close();
}
