# MindNest LiveKit Token Service

Standalone backend for minting LiveKit JWTs without Firebase Functions.

## What It Does

- Verifies Firebase ID token from `Authorization: Bearer <token>`.
- Checks Firestore user/session access rules:
  - same institution
  - role allowed (or host)
  - session active
  - not removed participant
- Signs and returns LiveKit token for room join.

## Endpoints

- `GET /healthz`
- `POST /livekit/token`
  - body: `{ "sessionId": "<live_session_id>" }`
  - headers:
    - `Authorization: Bearer <firebase_id_token>`
    - `Content-Type: application/json`

Response:

```json
{
  "serverUrl": "wss://...",
  "roomName": "mindnest_live_xxx",
  "token": "<livekit_jwt>",
  "canPublishAudio": false
}
```

## Environment Variables

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON` (required on Render/VPS; JSON string or base64 JSON)
- `PORT` (optional, default `8080`)

## Local Run

```bash
cd backend/livekit-token-service
npm install
npm start
```

## Cloud Run Deploy (Example)

```bash
gcloud run deploy mindnest-livekit-token \
  --source backend/livekit-token-service \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars LIVEKIT_URL=wss://...,LIVEKIT_API_KEY=...,LIVEKIT_API_SECRET=...,FIREBASE_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
```

## Render Notes

In Render service environment settings, set:

- `LIVEKIT_URL`
- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`
- `FIREBASE_SERVICE_ACCOUNT_JSON`

`FIREBASE_SERVICE_ACCOUNT_JSON` should be a full Firebase service account JSON from Firebase Console -> Project Settings -> Service Accounts.

## Flutter App Config

Run/build Flutter with:

```bash
--dart-define=LIVEKIT_TOKEN_ENDPOINT=https://<your-service-domain>/livekit/token
```

That endpoint is consumed by `LiveRepository.createLiveKitJoinCredentials()`.
