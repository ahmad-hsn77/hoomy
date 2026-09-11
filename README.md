# Hoomy

Hoomy is a Flutter app for family house needs, reminders, alerts, simple chat, and quick phone shortcuts.

## What is included

- Auth screen that accepts phone, email, or child mode without contact details.
- House onboarding for one member to create a house and invite/add family members by relationship.
- Home dashboard with urgent alerts, reminders, quick shortcuts, and family status.
- Alerts for missing items with optional emergency mode, quantity/price, selected recipients, and a bought button that notifies the family.
- Calendar screen that shows alerts, reminders, and member events in a simple month view.
- Family chat screen prepared for real-time socket messages.
- Settings screen for managing shortcuts, house details, and future expansion.
- `backend/` folder with a Node.js REST + Socket.IO backend.

## Frontend setup

The local Flutter command did not respond while this project was generated, so the app was scaffolded directly.

1. Install Flutter 3.22 or newer.
2. From this folder, run:

```powershell
flutter pub get
flutter create --platforms android,ios,web .
flutter run
```

If `flutter create` asks about overwriting files, keep the existing `lib/`, `pubspec.yaml`, `assets/`, `README.md`, and `backend/` files.

## Flutter structure

The Flutter app uses a lightweight MVVM structure:

- `lib/models/` contains plain domain models.
- `lib/view_models/` owns screen state and user actions.
- `lib/views/` contains screens and feature-specific widgets.
- `lib/widgets/` contains shared UI widgets.
- `lib/services/` contains backend/API/socket integration.
- `lib/core/` contains constants, theme, and utility helpers.

## Flutter backend URL

The app points to the Railway backend by default:

```text
https://hoomy-production.up.railway.app
```

To run against another backend, pass:

```powershell
flutter run --dart-define=HOOMY_API_URL=https://your-api-url
```

House location uses the device location permission through `geolocator`. When platform folders are generated, add the normal Android/iOS location permission strings before release.

## Backend setup

See [backend/README.md](backend/README.md).

## Render deploy

This repo includes `render.yaml` for Render Blueprint deployment.

1. Push the project to GitHub.
2. In Render, choose New -> Blueprint.
3. Select this repository.
4. Render will create the `hoomy-backend` web service from `backend/`.
5. Keep the free plan selected.

`JWT_SECRET` is generated automatically by Render from `render.yaml`. Change `CORS_ORIGIN` from `*` to your Flutter web/app domain before production.

## Railway deploy

This repo includes `railway.json` so Railway deploys the Node backend from `backend/`.

After connecting the GitHub repo:

1. Open the Railway service created from the repo.
2. Go to `Variables`.
3. Add:
   - `NODE_ENV=production`
   - `JWT_SECRET=<long random string>`
   - `CORS_ORIGIN=*`
4. Go to `Settings` -> `Networking`.
5. Click `Generate Domain`.
6. Test `https://your-domain.up.railway.app/health`.

## Suggested next production steps

1. Replace in-memory app state with API calls and persisted auth tokens.
2. Add Firebase Cloud Messaging or OneSignal for real push notifications.
3. Add geofencing/location consent flow so alerts can prioritize members outside the house.
4. Add role permissions for parent, child, guest, and admin.
5. Add multi-house support after the first-house flow is stable.
