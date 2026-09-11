# Hoomy Backend

Node.js + Express + Socket.IO backend for auth, houses, alerts, reminders, shortcuts, and family chat.

Data is persisted in MongoDB when `MONGODB_URI` is set. Without `MONGODB_URI`, the backend falls back to in-memory storage for local testing only.

## Run locally

```powershell
cd backend
npm install
copy .env.example .env
npm run dev
```

Server URL: `http://localhost:8080`

## Railway when this backend folder is the whole GitHub repo

If your GitHub repo contains `package.json`, `.env.example`, and `src/server.js` at the repo root, Railway can deploy it directly:

1. Build command: `npm install`
2. Start command: `npm start`
3. Add variables:
   - `NODE_ENV=production`
   - `JWT_SECRET=<long random string>`
   - `CORS_ORIGIN=*`
   - `MONGODB_URI=<MongoDB connection string>`
   - `MONGODB_DB=hoomy`
   - `MONGODB_COLLECTION=app_state`
   - `MONGODB_DOCUMENT_ID=main`
   - `FIREBASE_SERVICE_ACCOUNT_JSON=<Firebase service account JSON on one line>`
4. Generate a public domain from the Railway service Networking tab.
5. Test `/health` on the generated domain.

## MongoDB database setup

Recommended free option: MongoDB Atlas free cluster.

1. Open [MongoDB Atlas](https://www.mongodb.com/atlas/database) and create a free M0 cluster.
2. Create a database user under Database Access. Save the username and password.
3. Open Network Access and allow Railway to connect. For simple testing, add `0.0.0.0/0`; for production, restrict this if your hosting provider gives stable outbound IPs.
4. Open your cluster, click Connect, choose Drivers, and copy the connection string.
5. Replace `<username>`, `<password>`, and database name in the string. Example:

```text
mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/hoomy?retryWrites=true&w=majority
```

6. In Railway, add that string as `MONGODB_URI`.
7. Redeploy the Railway service.
8. Visit `/health`. It should show:

```json
{
  "databaseConfigured": true,
  "databaseReady": true
}
```

The backend stores all app data in one MongoDB document by default:

- Database: `hoomy`
- Collection: `app_state`
- Document ID: `main`

You can change those with `MONGODB_DB`, `MONGODB_COLLECTION`, and `MONGODB_DOCUMENT_ID`.

## Push notifications

Closed-app notifications require Firebase Cloud Messaging.

Backend setup:

1. Create a Firebase project.
2. Open Project settings -> Service accounts.
3. Generate a new private key.
4. Put the whole JSON content into Railway as `FIREBASE_SERVICE_ACCOUNT_JSON`.

Flutter Android setup:

1. Add an Android app in Firebase with package name `com.idea.hoomy.hoomy`.
2. Download `google-services.json`.
3. Place it at `android/app/google-services.json`.
4. Rebuild and reinstall the app so it can register its FCM token.

When a member creates an alert, the backend sends an FCM notification to other house members. Emergency alerts use the `hoomy_emergency_alerts` Android notification channel and `emergency_ring.wav`.

## Main endpoints

- `POST /auth/register` creates a user. Body accepts `name`, `email`, `phone`, `password`, `childMode`.
- `POST /auth/login` logs in by `email`, `phone`, or `childName`.
- `POST /auth/forgot-password` creates a password reset request by `email` or `phone`.
- `POST /auth/reset-password` resets a non-child account password by `email` or `phone`.
- `GET /auth/me` validates the current token and returns the current user.
- `POST /devices/fcm-token` registers this device for closed-app push notifications.
- `POST /houses` creates a house.
- `POST /houses/:houseId/members` adds a family member.
- `GET /houses/:houseId/state` returns house members, alerts, reminders, shortcuts, and messages.
- `POST /houses/:houseId/alerts` creates a missing item alert.
- `POST /houses/:houseId/alerts/:alertId/bought` marks an alert as bought.
- `POST /houses/:houseId/reminders` creates a reminder.
- `PUT /houses/:houseId/reminders/:reminderId` updates a reminder.
- `DELETE /houses/:houseId/reminders/:reminderId` deletes a reminder.
- `POST /houses/:houseId/messages` sends a family chat message.
- `POST /houses/:houseId/shortcuts` creates a quick action shortcut.
- `PUT /houses/:houseId/shortcuts/:shortcutId` updates a shortcut.
- `DELETE /houses/:houseId/shortcuts/:shortcutId` deletes a shortcut.

All house endpoints require:

```text
Authorization: Bearer <token>
```

## Socket.IO events

Client connects with:

```js
io("http://localhost:8080", { auth: { token } })
```

Then emit:

```js
socket.emit("joinHouse", houseId)
```

Server broadcasts:

- `alertCreated`
- `alertBought`
- `reminderCreated`
- `reminderUpdated`
- `reminderDeleted`
- `messageCreated`
- `shortcutCreated`
- `shortcutUpdated`
- `shortcutDeleted`
- `memberAdded`

Members are matched by normalized phone or email. Child accounts are matched by unique child name.

Password reset is prototype-only: it does not send an email/SMS code yet. Connect an email/SMS provider before production.

## Free hosting recommendation

Best simple option for this project: Railway for the Node backend plus MongoDB Atlas for the database.

1. Push this repo to GitHub.
2. Create or update your Railway Web Service.
3. Build command: `npm install`
4. Start command: `npm start`
5. Add environment variables from `.env.example`.
6. Set `CORS_ORIGIN` to your Flutter web domain when deployed.
7. Add `MONGODB_URI` from MongoDB Atlas and redeploy.

Other good free options:

- [Railway](https://railway.app/) for simple Node deployments with database add-ons.
- [Fly.io](https://fly.io/) if you are comfortable with CLI deployments.

For production push notifications, use Firebase Cloud Messaging. Socket.IO is good for live in-app updates, but mobile OS notifications need FCM/APNs.
