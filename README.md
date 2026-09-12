# Exchenge Mobile — Narail Express Exchange

Flutter Android admin app for the Narail Express Exchange system.

## Features

- Token login (Laravel Sanctum)
- Dashboard summary (pending / approved / canceled / bank balance)
- Pending for Review with Approve / Cancel
- Exchanges list with status filter + detail
- Users list, search, detail, Received / Paid due payment
- Banks with balance + NPSB / DB2B daily limits
- Expenses list

## API base

Default: `https://exchenge.narailexpress.net`

Override at build time:

```bash
flutter build apk --release --dart-define=API_BASE=https://your-host
```

## Build APK in the cloud (no local setup)

1. Push this folder to a GitHub repository.
2. The workflow `.github/workflows/build-apk.yml` runs automatically.
3. Download the `exchenge-mobile-apk` artifact from the workflow run.

## Run locally (optional, needs Flutter SDK)

```bash
flutter create --project-name exchenge_mobile --platforms=android .
flutter pub get
flutter run
```
