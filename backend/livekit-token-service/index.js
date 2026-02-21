const cors = require('cors');
const express = require('express');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

admin.initializeApp();

const db = admin.firestore();
const app = express();

app.use(express.json({ limit: '64kb' }));
app.use(
  cors({
    origin: true,
    methods: ['POST', 'OPTIONS', 'GET'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }),
);

const LIVEKIT_URL = process.env.LIVEKIT_URL || '';
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || '';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || '';

function hasLiveKitEnv() {
  return Boolean(LIVEKIT_URL && LIVEKIT_API_KEY && LIVEKIT_API_SECRET);
}

function badRequest(res, message) {
  return res.status(400).json({ error: message });
}

function unauthorized(res, message) {
  return res.status(401).json({ error: message });
}

function forbidden(res, message) {
  return res.status(403).json({ error: message });
}

app.get('/healthz', (_req, res) => {
  res.status(200).json({
    status: 'ok',
    livekitEnvConfigured: hasLiveKitEnv(),
  });
});

app.post('/livekit/token', async (req, res) => {
  try {
    if (!hasLiveKitEnv()) {
      return res.status(500).json({
        error:
          'LiveKit environment is not configured. Set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.',
      });
    }

    const authHeader = req.headers.authorization || '';
    if (!authHeader.startsWith('Bearer ')) {
      return unauthorized(res, 'Missing Authorization bearer token.');
    }

    const firebaseIdToken = authHeader.slice('Bearer '.length).trim();
    if (!firebaseIdToken) {
      return unauthorized(res, 'Firebase ID token is empty.');
    }

    const decoded = await admin.auth().verifyIdToken(firebaseIdToken, true);
    const uid = decoded.uid;
    if (!uid) {
      return unauthorized(res, 'Invalid Firebase user.');
    }

    const sessionId = String(req.body?.sessionId || '').trim();
    if (!sessionId) {
      return badRequest(res, 'sessionId is required.');
    }

    const userRef = db.collection('users').doc(uid);
    const sessionRef = db.collection('live_sessions').doc(sessionId);
    const participantRef = sessionRef.collection('participants').doc(uid);
    const [userSnap, sessionSnap, participantSnap] = await Promise.all([
      userRef.get(),
      sessionRef.get(),
      participantRef.get(),
    ]);

    if (!userSnap.exists || !sessionSnap.exists) {
      return forbidden(res, 'User or live session not found.');
    }

    const userData = userSnap.data() || {};
    const sessionData = sessionSnap.data() || {};

    const userInstitutionId = userData.institutionId || null;
    const sessionInstitutionId = sessionData.institutionId || null;
    if (!userInstitutionId || userInstitutionId !== sessionInstitutionId) {
      return forbidden(
        res,
        'This live session is not in your institution.',
      );
    }

    const role = String(userData.role || 'other');
    const createdBy = String(sessionData.createdBy || '');
    const isHost = createdBy === uid;

    const allowedRoles = Array.isArray(sessionData.allowedRoles)
      ? sessionData.allowedRoles.map((item) => String(item))
      : [];

    if (!isHost && !allowedRoles.includes(role)) {
      return forbidden(res, 'Your role is not allowed in this live session.');
    }

    const status = String(sessionData.status || 'ended');
    if (status !== 'live' && status !== 'paused') {
      return forbidden(res, 'This live session is not active.');
    }

    const participant = participantSnap.exists ? participantSnap.data() || {} : {};
    if (participant.removed === true) {
      return forbidden(res, 'You were removed from this live.');
    }

    let canPublishAudio = false;
    if (isHost) {
      canPublishAudio = status === 'live';
    } else if (participantSnap.exists) {
      const canSpeak = participant.canSpeak === true;
      const mutedByHost = participant.mutedByHost === true;
      canPublishAudio = status === 'live' && canSpeak && !mutedByHost;
    }

    const roomName = String(sessionData.roomName || `mindnest_live_${sessionId}`);
    const userName = String(
      userData.name || decoded.name || decoded.email || 'MindNest Member',
    );

    const accessToken = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
      identity: uid,
      name: userName,
      ttl: '2h',
    });
    accessToken.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: canPublishAudio,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await accessToken.toJwt();
    return res.status(200).json({
      serverUrl: LIVEKIT_URL,
      roomName,
      token,
      canPublishAudio,
    });
  } catch (error) {
    console.error('[livekit-token] error', error);
    return res.status(500).json({
      error: 'Unable to create audio token.',
    });
  }
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`mindnest-livekit-token-service listening on ${port}`);
});
