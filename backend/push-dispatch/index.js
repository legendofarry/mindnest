import cors from 'cors';
import express from 'express';
import admin from 'firebase-admin';
import { registerPasskeyRoutes } from './passkeys.js';

const app = express();

const corsOptions = {
  origin(origin, callback) {
    if (!origin || _isAllowedOrigin(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error('Not allowed by CORS.'));
  },
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '1mb' }));

const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!serviceAccountJson) {
  throw new Error(
    'Missing FIREBASE_SERVICE_ACCOUNT_JSON env var for push-dispatch service.'
  );
}

const serviceAccount = JSON.parse(serviceAccountJson);
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const db = admin.firestore();
const messaging = admin.messaging();

async function authenticate(req, res, next) {
  try {
    const authHeader = req.header('authorization') || '';
    if (!authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Missing Bearer token.' });
    }
    const idToken = authHeader.substring('Bearer '.length).trim();
    const decoded = await admin.auth().verifyIdToken(idToken);
    req.user = decoded;
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid auth token.' });
  }
}

function _isAllowedOrigin(origin) {
  try {
    const parsed = new URL(origin);
    const hostname = parsed.hostname.toLowerCase();
    if (
      hostname === 'localhost' ||
      hostname === '127.0.0.1' ||
      hostname === '::1'
    ) {
      return true;
    }

    const configuredOrigins = [
      process.env.PASSKEY_ALLOWED_ORIGINS,
      process.env.WEB_APP_ORIGIN,
    ]
      .flatMap((value) =>
        (value || '')
          .split(',')
          .map((item) => item.trim())
          .filter(Boolean),
      )
      .map((value) => {
        try {
          return new URL(value).origin;
        } catch (_) {
          return value;
        }
      });

    if (configuredOrigins.includes(parsed.origin)) {
      return true;
    }

    return hostname === 'mindnestke.netlify.app';
  } catch (_) {
    return false;
  }
}

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.post('/push/dispatch', authenticate, async (req, res) => {
  const notifications = Array.isArray(req.body?.notifications)
    ? req.body.notifications
    : [];

  if (notifications.length === 0) {
    return res.status(400).json({ error: 'notifications[] is required.' });
  }

  const senderUid = req.user?.uid;
  const senderDoc = await db.collection('users').doc(senderUid).get();
  const senderInstitutionId = senderDoc.data()?.institutionId || null;

  const accepted = [];
  for (const item of notifications) {
    if (
      !item ||
      typeof item.userId !== 'string' ||
      typeof item.title !== 'string' ||
      typeof item.body !== 'string'
    ) {
      continue;
    }
    // Prevent cross-institution push abuse from client calls.
    if (
      senderInstitutionId &&
      item.institutionId &&
      item.institutionId !== senderInstitutionId
    ) {
      continue;
    }
    accepted.push({
      userId: item.userId,
      title: item.title.trim(),
      body: item.body.trim(),
      type: (item.type || '').toString(),
      relatedAppointmentId: (item.relatedAppointmentId || '').toString(),
    });
  }

  if (accepted.length === 0) {
    return res.json({ sent: 0, skipped: notifications.length });
  }

  const userIds = [...new Set(accepted.map((entry) => entry.userId))];
  const tokenByUser = new Map();

  for (const userId of userIds) {
    const snap = await db
      .collection('user_push_tokens')
      .where('userId', '==', userId)
      .limit(25)
      .get();
    tokenByUser.set(
      userId,
      snap.docs
        .map((doc) => doc.data())
        .filter((data) => data?.isEnabled !== false)
        .map((data) => data?.token)
        .filter((token) => typeof token === 'string' && token.length > 0)
    );
  }

  const messages = [];
  for (const item of accepted) {
    const tokens = tokenByUser.get(item.userId) || [];
    for (const token of tokens) {
      messages.push({
        token,
        notification: {
          title: item.title,
          body: item.body,
        },
        data: {
          type: item.type,
          relatedAppointmentId: item.relatedAppointmentId,
          userId: item.userId,
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'mindnest_alerts',
            sound: 'default',
            defaultVibrateTimings: true,
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      });
    }
  }

  if (messages.length === 0) {
    return res.json({ sent: 0, skipped: accepted.length });
  }

  const response = await messaging.sendEach(messages);
  return res.json({
    requested: notifications.length,
    accepted: accepted.length,
    dispatched: messages.length,
    success: response.successCount,
    failure: response.failureCount,
  });
});

registerPasskeyRoutes({
  app,
  db,
  admin,
  authenticate,
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`push-dispatch listening on :${port}`);
});
