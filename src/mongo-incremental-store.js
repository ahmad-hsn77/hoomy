// Keep the last successfully written snapshot. Compare plaintext before
// encryption: AES-GCM uses random IVs, so ciphertext cannot detect changes.
export function createMongoIncrementalStore({ encryptState, recordIdFor, allowMessageCountDrop = false }) {
  let previous = null;

  async function persist(state, { document, database, documentId }) {
    const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const next = structuredClone(state);
    const oldCount = previous?.messages?.length;
    if (!allowMessageCountDrop && (previous === null || next.messages.length < oldCount)) {
      const currentCount = document
        ? (await document.aggregate([
            { $match: { _id: documentId } },
            { $project: { count: { $size: { $ifNull: ['$state.messages', []] } } } },
          ]).toArray())[0]?.count || 0
        : await database.collection('messages').countDocuments();
      if (currentCount > next.messages.length) {
        throw new Error(`Refusing to persist fewer messages (${next.messages.length}) than currently stored (${currentCount}).`);
      }
    }

    if (document) {
      const set = {};
      for (const [key, value] of Object.entries(next)) {
        if (key === 'messages') continue;
        if (same(value, previous?.[key])) continue;
        // A shrinking array must be replaced to remove its trailing entries.
        // Appends and edits use individual indices, avoiding chat retransfers.
        if (!previous || !Array.isArray(value) || value.length < previous[key].length) {
          set[`state.${key}`] = encryptState(value);
        } else {
          value.forEach((record, index) => {
            if (!same(record, previous[key][index])) {
              set[`state.${key}.${index}`] = encryptState(record);
            }
          });
        }
      }
      if (Object.keys(set).length) {
        await document.updateOne({ _id: documentId }, {
          $set: { ...set, updatedAt: new Date() },
          $setOnInsert: { createdAt: new Date() },
        }, { upsert: true });
      }
      const beforeMessages = new Map((previous?.messages || []).map((message) => [message.id, message]));
      let messageOperations = [];
      const flushMessages = async () => {
        if (!messageOperations.length) return;
        await document.bulkWrite(messageOperations, { ordered: true });
        messageOperations = [];
      };
      for (const message of next.messages) {
        if (!message.id) throw new Error('Cannot persist a message without an ID');
        if (same(message, beforeMessages.get(message.id))) continue;
        const encrypted = encryptState(message);
        // Atomic conditional append: overlapping deployments must not replace
        // a message at an array index or append the same ID twice.
        messageOperations.push({ updateOne: {
          filter: { _id: documentId, 'state.messages.id': { $ne: message.id } },
          update: { $push: { 'state.messages': encrypted } },
        } }, { updateOne: {
          filter: { _id: documentId, 'state.messages.id': message.id },
          update: { $set: { 'state.messages.$[message]': encrypted } },
          arrayFilters: [{ 'message.id': message.id }],
        } });
        if (messageOperations.length >= 500) await flushMessages();
      }
      await flushMessages();
    } else {
      for (const [key, value] of Object.entries(next)) {
        if (same(value, previous?.[key])) continue;
        if (!Array.isArray(value)) {
          await database.collection('app_meta').updateOne({ _id: key }, {
            $set: { value: encryptState(value), updatedAt: new Date() },
          }, { upsert: true });
          continue;
        }
        const before = new Map((previous?.[key] || []).map((record, index) =>
          [recordIdFor(key, record, index), { record, index }]));
        const operations = [];
        value.forEach((record, index) => {
          const id = recordIdFor(key, record, index);
          const saved = before.get(id);
          if (!saved || saved.index !== index || !same(saved.record, record)) {
            operations.push({ replaceOne: {
              filter: { _id: id },
              replacement: { ...encryptState(record), _id: id, __order: index },
              upsert: true,
            } });
          }
          before.delete(id);
        });
        // A stale snapshot is never authorization to remove chat history.
        if (key !== 'messages') {
          for (const id of before.keys()) operations.push({ deleteOne: { filter: { _id: id } } });
        }
        if (operations.length) await database.collection(key).bulkWrite(operations, { ordered: true });
      }
    }
    // Advance only after every operation succeeds. Partial failures can be
    // retried safely; later snapshots include changes from failed attempts.
    previous = next;
  }
  return { persist };
}
