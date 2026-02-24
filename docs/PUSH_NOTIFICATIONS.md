# Push Notifications Setup

This project now supports:
- Permission prompt for notifications
- Foreground notification popups with sound + vibration
- Background/terminated push via FCM (when backend dispatch endpoint is configured)

## 1) Flutter Runtime Define

Run/build with:

```bash
--dart-define=PUSH_DISPATCH_ENDPOINT=https://<your-domain>/push/dispatch
```

If this define is missing, in-app notification documents still work, but remote push delivery is skipped.

## 2) Deploy Push Dispatch Backend

Service folder:

`backend/push-dispatch`

Env vars required:
- `FIREBASE_SERVICE_ACCOUNT_JSON`
- `PORT` (optional, defaults to `8080`)

Start:

```bash
cd backend/push-dispatch
npm install
npm start
```

Health endpoint:

`GET /health`

Dispatch endpoint:

`POST /push/dispatch`

Auth:
- `Authorization: Bearer <Firebase ID token>`

Body:

```json
{
  "notifications": [
    {
      "userId": "uid_target",
      "institutionId": "institution_id",
      "title": "Session confirmed",
      "body": "Your counselor confirmed your upcoming session.",
      "type": "booking_confirmed",
      "relatedAppointmentId": "appt_123"
    }
  ]
}
```

## 3) Platform Notes

### Android
- `POST_NOTIFICATIONS` permission is added.
- Notification channel id used for sound/vibration:
  - `mindnest_alerts`

### iOS
- Remote notification background mode is enabled in `Info.plist`.
- App asks for alert/sound/badge permission at startup.

## 4) Firestore Rules

Collection used for device tokens:
- `user_push_tokens`

Only token owner can read/write token docs.
