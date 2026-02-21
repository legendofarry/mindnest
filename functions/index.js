const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { AccessToken } = require('livekit-server-sdk');

admin.initializeApp();

exports.createLivekitToken = onCall(async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }

  const sessionId = (request.data?.sessionId || '').toString().trim();
  const canPublishAudio = Boolean(request.data?.canPublishAudio);
  if (!sessionId) {
    throw new HttpsError('invalid-argument', 'sessionId is required.');
  }

  const apiKey = process.env.LIVEKIT_API_KEY;
  const apiSecret = process.env.LIVEKIT_API_SECRET;
  const serverUrl = process.env.LIVEKIT_URL;
  if (!apiKey || !apiSecret || !serverUrl) {
    throw new HttpsError('failed-precondition', 'LiveKit environment variables are missing.');
  }

  const db = admin.firestore();
  const userSnap = await db.collection('users').doc(request.auth.uid).get();
  const sessionSnap = await db.collection('live_sessions').doc(sessionId).get();

  if (!userSnap.exists || !sessionSnap.exists) {
    throw new HttpsError('not-found', 'User or session not found.');
  }

  const userData = userSnap.data() || {};
  const sessionData = sessionSnap.data() || {};
  const institutionId = userData.institutionId || null;
  if (!institutionId || institutionId !== sessionData.institutionId) {
    throw new HttpsError('permission-denied', 'Session is not in your institution.');
  }

  const role = userData.role || 'other';
  const allowedRoles = Array.isArray(sessionData.allowedRoles)
    ? sessionData.allowedRoles
    : [];
  if (!allowedRoles.includes(role)) {
    throw new HttpsError('permission-denied', 'Role not allowed for this session.');
  }

  const roomName = (sessionData.roomName || `mindnest_live_${sessionId}`).toString();
  const identity = request.auth.uid;
  const userName = (userData.name || request.auth.token.email || 'Member').toString();

  const accessToken = new AccessToken(apiKey, apiSecret, {
    identity,
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

  return {
    serverUrl,
    roomName,
    token: await accessToken.toJwt(),
  };
});
