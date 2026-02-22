// netlify\functions\livekit-token.js
const admin = require("firebase-admin");
const { AccessToken } = require("livekit-server-sdk");

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(statusCode, payload) {
  return {
    statusCode,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  };
}

function readServiceAccountFromEnv() {
  const raw =
    process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
    process.env.GOOGLE_CREDENTIALS_JSON ||
    "";
  if (!raw) {
    return null;
  }

  let jsonText = raw.trim();
  if (!jsonText.startsWith("{")) {
    jsonText = Buffer.from(jsonText, "base64").toString("utf8");
  }
  const parsed = JSON.parse(jsonText);
  if (typeof parsed.private_key === "string") {
    parsed.private_key = parsed.private_key.replace(/\\n/g, "\n");
  }
  return parsed;
}

function initializeFirebaseIfNeeded() {
  if (admin.apps.length > 0) {
    return;
  }
  const serviceAccount = readServiceAccountFromEnv();
  if (!serviceAccount) {
    admin.initializeApp();
    return;
  }
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: corsHeaders, body: "" };
  }
  if (event.httpMethod !== "POST") {
    return json(405, { error: "Method Not Allowed" });
  }

  const liveKitUrl = process.env.LIVEKIT_URL || "";
  const liveKitApiKey = process.env.LIVEKIT_API_KEY || "";
  const liveKitApiSecret = process.env.LIVEKIT_API_SECRET || "";
  if (!liveKitUrl || !liveKitApiKey || !liveKitApiSecret) {
    return json(500, {
      error:
        "LiveKit environment is not configured. Set LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET.",
    });
  }

  try {
    initializeFirebaseIfNeeded();

    const authHeader =
      event.headers.authorization || event.headers.Authorization || "";
    if (!authHeader.startsWith("Bearer ")) {
      return json(401, { error: "Missing Authorization bearer token." });
    }

    const firebaseIdToken = authHeader.slice("Bearer ".length).trim();
    if (!firebaseIdToken) {
      return json(401, { error: "Firebase ID token is empty." });
    }

    const decoded = await admin.auth().verifyIdToken(firebaseIdToken, true);
    const uid = decoded.uid;
    if (!uid) {
      return json(401, { error: "Invalid Firebase user." });
    }

    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (_) {
      return json(400, { error: "Invalid JSON body." });
    }

    const sessionId = String(body.sessionId || "").trim();
    if (!sessionId) {
      return json(400, { error: "sessionId is required." });
    }

    const roomName = `mindnest_live_${sessionId}`;
    const accessToken = new AccessToken(liveKitApiKey, liveKitApiSecret, {
      identity: uid,
      name: String(decoded.name || decoded.email || "MindNest Member"),
      ttl: "2h",
    });
    accessToken.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await accessToken.toJwt();
    return json(200, {
      serverUrl: liveKitUrl,
      roomName,
      token,
      canPublishAudio: true,
    });
  } catch (error) {
    console.error("[netlify-livekit-token] error", error);
    const message = String(error?.message || "");
    const code = String(error?.code || "");

    if (code.startsWith("auth/")) {
      return json(401, { error: `Invalid auth token: ${code}` });
    }
    if (
      message.includes("Could not load the default credentials") ||
      message.includes("Failed to determine project ID")
    ) {
      return json(500, {
        error:
          "Firebase Admin credentials are missing. Set FIREBASE_SERVICE_ACCOUNT_JSON.",
      });
    }
    return json(500, { error: "Unable to create audio token." });
  }
};
