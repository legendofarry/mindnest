import { randomUUID } from 'crypto';

import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
} from '@simplewebauthn/server';
import { isoUint8Array } from '@simplewebauthn/server/helpers';

const PASSKEY_CREDENTIALS_COLLECTION = 'passkey_credentials';
const PASSKEY_SESSIONS_COLLECTION = 'passkey_sessions';
const PASSKEY_SESSION_TTL_MS = 10 * 60 * 1000;

export function registerPasskeyRoutes({ app, db, admin, authenticate }) {
  app.post('/passkeys/register/start', authenticate, async (req, res) => {
    try {
      const origin = _resolveOrigin(req);
      const rpId = _resolveRpId(origin);
      const userId = req.user?.uid || '';
      if (!userId) {
        return res.status(401).json({ error: 'Missing user identity.' });
      }

      const [authUser, profileSnapshot, existingPasskeys] = await Promise.all([
        admin.auth().getUser(userId),
        db.collection('users').doc(userId).get(),
        _loadPasskeysForUser(db, userId),
      ]);

      const profile = profileSnapshot.exists ? profileSnapshot.data() : null;
      const profileEmail = typeof profile?.email === 'string'
        ? profile.email
        : '';
      const userEmail = _normalizeEmail(profileEmail || authUser.email || '');
      if (!userEmail) {
        return res.status(400).json({
          error: 'This account needs an email address before passkeys can be enabled.',
        });
      }

      const profileName = typeof profile?.name === 'string'
        ? profile.name
        : '';
      const userLabel = _trimToEmpty(profileName || authUser.displayName || '') ||
        userEmail;

      const options = await generateRegistrationOptions({
        rpName: 'MindNest',
        rpID: rpId,
        userID: isoUint8Array.fromUTF8String(userId),
        userName: userLabel,
        userDisplayName: userLabel,
        attestationType: 'none',
        excludeCredentials: existingPasskeys.map((credential) => ({
          id: credential.credentialId,
          transports: credential.transports,
        })),
        authenticatorSelection: {
          residentKey: 'required',
          userVerification: 'required',
          authenticatorAttachment: 'platform',
        },
      });

      const sessionId = randomUUID();
      await db.collection(PASSKEY_SESSIONS_COLLECTION).doc(sessionId).set({
        type: 'register',
        userId,
        userEmail,
        userLabel,
        origin,
        rpId,
        challenge: options.challenge,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAtMs: Date.now() + PASSKEY_SESSION_TTL_MS,
      });

      return res.json({ sessionId, options });
    } catch (error) {
      return _handleError(res, error, 'Unable to prepare passkey registration.');
    }
  });

  app.post('/passkeys/register/finish', authenticate, async (req, res) => {
    try {
      const sessionId = _trimToEmpty(req.body?.sessionId);
      const response = _normalizeCredentialResponse(req.body?.response ?? req.body);
      if (!sessionId) {
        return res.status(400).json({ error: 'sessionId is required.' });
      }
      if (!response) {
        return res.status(400).json({ error: 'Passkey response is required.' });
      }

      const sessionRef = db.collection(PASSKEY_SESSIONS_COLLECTION).doc(sessionId);
      const sessionSnapshot = await sessionRef.get();
      if (!sessionSnapshot.exists) {
        return res.status(404).json({ error: 'Passkey session not found.' });
      }

      const session = sessionSnapshot.data() || {};
      _assertSessionKind(session, 'register');
      _assertSessionStillValid(session);
      _assertSessionUserMatches(session, req.user?.uid || '');

      const verification = await verifyRegistrationResponse({
        response,
        expectedChallenge: session.challenge,
        expectedOrigin: session.origin,
        expectedRPID: session.rpId,
        requireUserVerification: true,
      });

      if (!verification.verified || !verification.registrationInfo) {
        return res.status(400).json({ verified: false });
      }

      const { credential, credentialDeviceType, credentialBackedUp } =
        verification.registrationInfo;
      const credentialId = credential.id;
      const credentialRef = db
        .collection(PASSKEY_CREDENTIALS_COLLECTION)
        .doc(credentialId);
      const credentialPayload = {
        credentialId,
        userId: session.userId,
        userEmail: session.userEmail,
        userLabel: session.userLabel,
        publicKey: Buffer.from(credential.publicKey).toString('base64url'),
        counter: credential.counter,
        transports: credential.transports ?? [],
        deviceType: credentialDeviceType,
        backedUp: credentialBackedUp,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await credentialRef.set(credentialPayload, { merge: true });
      await sessionRef.delete().catch(() => {});

      return res.json({
        verified: true,
        credentialId,
        userId: session.userId,
      });
    } catch (error) {
      return _handleError(res, error, 'Unable to finish passkey registration.');
    }
  });

  app.post('/passkeys/login/start', async (req, res) => {
    try {
      const origin = _resolveOrigin(req);
      const rpId = _resolveRpId(origin);

      const options = await generateAuthenticationOptions({
        rpID: rpId,
        allowCredentials: [],
        userVerification: 'required',
      });

      const sessionId = randomUUID();
      await db.collection(PASSKEY_SESSIONS_COLLECTION).doc(sessionId).set({
        type: 'login',
        origin,
        rpId,
        challenge: options.challenge,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAtMs: Date.now() + PASSKEY_SESSION_TTL_MS,
      });

      return res.json({ sessionId, options });
    } catch (error) {
      return _handleError(res, error, 'Unable to prepare passkey login.');
    }
  });

  app.post('/passkeys/login/finish', async (req, res) => {
    try {
      const sessionId = _trimToEmpty(req.body?.sessionId);
      const response = _normalizeCredentialResponse(req.body?.response ?? req.body);
      if (!sessionId) {
        return res.status(400).json({ error: 'sessionId is required.' });
      }
      if (!response) {
        return res.status(400).json({ error: 'Passkey response is required.' });
      }

      const sessionRef = db.collection(PASSKEY_SESSIONS_COLLECTION).doc(sessionId);
      const sessionSnapshot = await sessionRef.get();
      if (!sessionSnapshot.exists) {
        return res.status(404).json({ error: 'Passkey session not found.' });
      }

      const session = sessionSnapshot.data() || {};
      _assertSessionKind(session, 'login');
      _assertSessionStillValid(session);

      const credentialId = _trimToEmpty(response.id);
      if (!credentialId) {
        return res.status(400).json({ error: 'Passkey response missing credential id.' });
      }

      const credentialSnapshot = await db
        .collection(PASSKEY_CREDENTIALS_COLLECTION)
        .doc(credentialId)
        .get();
      if (!credentialSnapshot.exists) {
        return res.status(404).json({ error: 'Passkey not found.' });
      }

      const credentialData = credentialSnapshot.data() || {};
      const publicKeyEncoded = _trimToEmpty(credentialData.publicKey);
      if (!publicKeyEncoded) {
        return res.status(500).json({
          error: 'Passkey credential is missing public key material.',
        });
      }

      const credential = {
        id: credentialId,
        publicKey: Buffer.from(publicKeyEncoded, 'base64url'),
        counter: Number(credentialData.counter ?? 0),
        transports: Array.isArray(credentialData.transports)
          ? credentialData.transports
          : [],
      };

      const verification = await verifyAuthenticationResponse({
        response,
        expectedChallenge: session.challenge,
        expectedOrigin: session.origin,
        expectedRPID: session.rpId,
        credential,
        requireUserVerification: true,
      });

      if (!verification.verified) {
        return res.status(400).json({ verified: false });
      }

      const newCounter = Number(
        verification.authenticationInfo?.newCounter ?? credential.counter,
      );
      await credentialSnapshot.ref.set(
        {
          counter: newCounter,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      await sessionRef.delete().catch(() => {});

      const userId = _trimToEmpty(credentialData.userId);
      if (!userId) {
        return res.status(500).json({
          error: 'Passkey credential is missing a user binding.',
        });
      }

      const customToken = await admin.auth().createCustomToken(userId, {
        authMethod: 'passkey',
        passkeyCredentialId: credentialId,
      });

      return res.json({
        verified: true,
        customToken,
        userId,
      });
    } catch (error) {
      return _handleError(res, error, 'Unable to finish passkey login.');
    }
  });

  app.get('/passkeys/me', authenticate, async (req, res) => {
    try {
      const userId = req.user?.uid || '';
      const passkeys = await _loadPasskeysForUser(db, userId);
      return res.json({
        count: passkeys.length,
        hasPasskeys: passkeys.length > 0,
        passkeys: passkeys.map((credential) => credential.toJson()),
      });
    } catch (error) {
      return _handleError(res, error, 'Unable to load passkeys.');
    }
  });

  app.delete('/passkeys/me', authenticate, async (req, res) => {
    try {
      const userId = req.user?.uid || '';
      const passkeys = await _loadPasskeysForUser(db, userId);
      if (passkeys.length === 0) {
        return res.json({ deleted: 0 });
      }

      const batch = db.batch();
      for (const credential of passkeys) {
        batch.delete(
          db.collection(PASSKEY_CREDENTIALS_COLLECTION).doc(
            credential.credentialId,
          ),
        );
      }
      await batch.commit();
      return res.json({ deleted: passkeys.length });
    } catch (error) {
      return _handleError(res, error, 'Unable to delete passkeys.');
    }
  });

  app.delete('/passkeys/me/:credentialId', authenticate, async (req, res) => {
    try {
      const userId = req.user?.uid || '';
      const credentialId = _trimToEmpty(req.params.credentialId);
      if (!credentialId) {
        return res.status(400).json({ error: 'credentialId is required.' });
      }

      const credentialRef = db
        .collection(PASSKEY_CREDENTIALS_COLLECTION)
        .doc(credentialId);
      const snapshot = await credentialRef.get();
      if (!snapshot.exists) {
        return res.json({ deleted: 0 });
      }

      const data = snapshot.data() || {};
      if (_trimToEmpty(data.userId) !== userId) {
        return res.status(403).json({ error: 'You do not own this passkey.' });
      }

      await credentialRef.delete();
      return res.json({ deleted: 1 });
    } catch (error) {
      return _handleError(res, error, 'Unable to delete passkey.');
    }
  });
}

async function _loadPasskeysForUser(db, userId) {
  if (!userId) {
    return [];
  }
  const snapshot = await db
    .collection(PASSKEY_CREDENTIALS_COLLECTION)
    .where('userId', '==', userId)
    .get();

  return snapshot.docs.map((doc) => {
    const data = doc.data() || {};
    return {
      credentialId: doc.id,
      userId: _trimToEmpty(data.userId),
      userEmail: _trimToEmpty(data.userEmail),
      userLabel: _trimToEmpty(data.userLabel),
      publicKey: _trimToEmpty(data.publicKey),
      counter: Number(data.counter ?? 0),
      transports: Array.isArray(data.transports) ? data.transports : [],
      deviceType: _trimToEmpty(data.deviceType),
      backedUp: Boolean(data.backedUp),
      createdAt: data.createdAt ?? null,
      updatedAt: data.updatedAt ?? null,
      lastUsedAt: data.lastUsedAt ?? null,
      toJson() {
        return {
          credentialId: this.credentialId,
          userId: this.userId,
          userEmail: this.userEmail,
          userLabel: this.userLabel,
          counter: this.counter,
          transports: this.transports,
          deviceType: this.deviceType,
          backedUp: this.backedUp,
          createdAt: _serializeDate(this.createdAt),
          updatedAt: _serializeDate(this.updatedAt),
          lastUsedAt: _serializeDate(this.lastUsedAt),
        };
      },
    };
  });
}

function _normalizeCredentialResponse(value) {
  if (!value) {
    return null;
  }
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return _normalizeCredentialResponse(parsed);
    } catch (_) {
      return null;
    }
  }
  if (typeof value !== 'object') {
    return null;
  }
  return value;
}

function _resolveOrigin(req) {
  const origin = _trimToEmpty(req.header('origin'));
  if (!origin) {
    throw new Error('Missing request origin.');
  }
  const url = new URL(origin);
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error('Unsupported request origin.');
  }
  return url.origin;
}

function _resolveRpId(origin) {
  return new URL(origin).hostname;
}

function _assertSessionKind(session, kind) {
  if ((session?.type || '').trim() !== kind) {
    throw new Error('Passkey session type mismatch.');
  }
}

function _assertSessionStillValid(session) {
  const expiresAtMs = Number(session?.expiresAtMs ?? 0);
  if (!expiresAtMs || Date.now() > expiresAtMs) {
    throw new Error('Passkey session expired.');
  }
}

function _assertSessionUserMatches(session, userId) {
  const expectedUserId = _trimToEmpty(session?.userId);
  if (expectedUserId && expectedUserId !== _trimToEmpty(userId)) {
    throw new Error('Passkey session user mismatch.');
  }
}

function _trimToEmpty(value) {
  return (value ?? '').toString().trim();
}

function _normalizeEmail(value) {
  const normalized = _trimToEmpty(value).toLowerCase();
  return normalized.includes('@') ? normalized : '';
}

function _serializeDate(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === 'string') {
    return value;
  }
  return null;
}

function _handleError(res, error, fallbackMessage) {
  const message = error instanceof Error ? error.message : fallbackMessage;
  return res.status(400).json({
    error: message || fallbackMessage,
  });
}
