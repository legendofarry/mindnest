import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';

import admin from 'firebase-admin';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, '..', '..');
const DEFAULT_CONFIG_PATH = path.join(
  scriptDir,
  'reviewer-accounts.config.local.json'
);
const EXAMPLE_CONFIG_PATH = path.join(
  scriptDir,
  'reviewer-accounts.config.example.json'
);
const JOIN_CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

let db;
let auth;

function parseArgs(argv) {
  const parsed = { _positionals: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      parsed._positionals.push(token);
      continue;
    }
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      parsed[token] = true;
      continue;
    }
    parsed[token] = next;
    i += 1;
  }
  return parsed;
}

function normalizeEmail(email) {
  return String(email ?? '').trim().toLowerCase();
}

function normalizePhoneE164(phone) {
  let normalized = String(phone ?? '')
    .trim()
    .replace(/[\s\-()]/g, '');
  if (normalized.startsWith('00')) {
    normalized = `+${normalized.slice(2)}`;
  }
  if (!normalized.startsWith('+')) {
    throw new Error(
      `Phone number "${phone}" must use E.164 format such as +2547...`
    );
  }
  if (!/^\+[1-9][0-9]{7,14}$/.test(normalized)) {
    throw new Error(`Phone number "${phone}" is not a valid E.164 value.`);
  }
  return normalized;
}

function normalizeOptionalPhoneE164(phone) {
  const trimmed = String(phone ?? '').trim();
  if (!trimmed) return null;
  return normalizePhoneE164(trimmed);
}

function buildPhoneCandidates(primaryPhone, additionalPhone) {
  const values = new Set([primaryPhone, primaryPhone.slice(1)]);
  if (additionalPhone) {
    values.add(additionalPhone);
    values.add(additionalPhone.slice(1));
  }
  return [...values];
}

function phoneRegistryDocId(phoneE164) {
  return phoneE164.replace(/[^0-9]/g, '');
}

function normalizeInstitutionName(name) {
  return String(name ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
}

function institutionNameRegistryDocId(normalizedName) {
  return Buffer.from(normalizedName, 'utf8').toString('base64url');
}

function sanitizeInstitutionId(catalogId) {
  const raw = String(catalogId ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return raw ? `review-${raw}` : db.collection('institutions').doc().id;
}

function generateJoinCode(length = 8) {
  let value = '';
  for (let i = 0; i < length; i += 1) {
    value += JOIN_CODE_ALPHABET[Math.floor(Math.random() * JOIN_CODE_ALPHABET.length)];
  }
  return value;
}

function requireString(value, label) {
  const trimmed = String(value ?? '').trim();
  if (!trimmed) {
    throw new Error(`Missing required value: ${label}`);
  }
  return trimmed;
}

function makeTimestamp(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

async function readJson(filePath) {
  const raw = await fs.readFile(filePath, 'utf8');
  return JSON.parse(raw);
}

async function resolveServiceAccount(args) {
  const explicitPath = args['--service-account'] || args._positionals?.[1];
  const envPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
  const googleAppCreds = process.env.GOOGLE_APPLICATION_CREDENTIALS;

  if (explicitPath || envPath || googleAppCreds) {
    const selectedPath = path.resolve(
      scriptDir,
      String(explicitPath || envPath || googleAppCreds)
    );
    const raw = await fs.readFile(selectedPath, 'utf8');
    return JSON.parse(raw);
  }

  const inlineJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (inlineJson) {
    return JSON.parse(inlineJson);
  }

  throw new Error(
    'Missing Firebase admin credentials.\nProvide one of these:\n- --service-account C:\\path\\to\\service-account.json\n- FIREBASE_SERVICE_ACCOUNT_PATH\n- GOOGLE_APPLICATION_CREDENTIALS\n- FIREBASE_SERVICE_ACCOUNT_JSON'
  );
}

async function onboardingVersion() {
  const bankPath = path.join(
    repoRoot,
    'lib',
    'features',
    'onboarding',
    'data',
    'onboarding_question_bank.dart'
  );
  try {
    const raw = await fs.readFile(bankPath, 'utf8');
    const match = raw.match(/static const int version = (\d+);/);
    return match ? Number(match[1]) : 4;
  } catch (_) {
    return 4;
  }
}

function roleLabel(roleKey) {
  switch (roleKey) {
    case 'institutionAdmin':
      return 'Institution Admin';
    case 'counselor':
      return 'Counselor';
    case 'student':
      return 'Student';
    case 'staff':
      return 'Staff';
    default:
      return roleKey;
  }
}

function buildDefaultOnboardingAnswers(roleKey) {
  if (roleKey === 'student') {
    return {
      focus_areas: ['academic_pressure', 'stress'],
      today_mood: 'good',
      wellbeing_drivers: ['routine'],
      support_preference: ['talk_to_counselor'],
      reminder_frequency: 'weekly',
    };
  }
  return {
    focus_areas: ['work_pressure', 'stress'],
    today_mood: 'good',
    wellbeing_drivers: ['routine'],
    support_preference: ['talk_to_counselor'],
    reminder_frequency: 'weekly',
  };
}

async function ensureAuthUser({ email, password, name }) {
  const normalizedEmail = normalizeEmail(email);
  try {
    const existing = await auth.getUserByEmail(normalizedEmail);
    await auth.updateUser(existing.uid, {
      password,
      displayName: name,
      emailVerified: true,
      disabled: false,
    });
    return auth.getUser(existing.uid);
  } catch (error) {
    if (error.code !== 'auth/user-not-found') {
      throw error;
    }
    return auth.createUser({
      email: normalizedEmail,
      password,
      displayName: name,
      emailVerified: true,
      disabled: false,
    });
  }
}

async function ensureSafeExistingProfile({
  uid,
  email,
  targetRole,
  institutionId,
}) {
  const snapshot = await db.collection('users').doc(uid).get();
  if (!snapshot.exists) {
    return null;
  }
  const data = snapshot.data() ?? {};
  const existingInstitutionId = String(data.institutionId ?? '').trim();
  if (existingInstitutionId && existingInstitutionId !== institutionId) {
    throw new Error(
      `${email} already belongs to another institution (${existingInstitutionId}). Use a dedicated review account instead of reusing this user.`
    );
  }

  const existingRole = String(data.role ?? '').trim();
  if (
    existingRole &&
    existingRole !== targetRole &&
    existingRole !== 'individual' &&
    existingRole !== 'other'
  ) {
    throw new Error(
      `${email} already has role "${existingRole}". Use a dedicated review account or reset that user before seeding review data.`
    );
  }
  return data;
}

async function ensureInstitutionCatalogAvailable(catalogId, institutionId) {
  const snapshot = await db
    .collection('institution_catalog_registry')
    .doc(catalogId)
    .get();
  if (!snapshot.exists) {
    return;
  }
  const claimedInstitutionId = String(snapshot.data()?.institutionId ?? '').trim();
  if (claimedInstitutionId && claimedInstitutionId !== institutionId) {
    throw new Error(
      `Institution catalog ID "${catalogId}" is already claimed by ${claimedInstitutionId}.`
    );
  }
}

async function ensurePhoneRegistry(uid, primaryPhone, additionalPhone) {
  for (const phone of [primaryPhone, additionalPhone].filter(Boolean)) {
    const docId = phoneRegistryDocId(phone);
    const ref = db.collection('phone_number_registry').doc(docId);
    const snapshot = await ref.get();
    if (snapshot.exists) {
      const claimedUid = String(snapshot.data()?.uid ?? '').trim();
      if (claimedUid && claimedUid !== uid) {
        throw new Error(
          `Phone number ${phone} is already linked to another account (${claimedUid}).`
        );
      }
    }
    await ref.set(
      {
        uid,
        phoneNumber: phone,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }
}

async function upsertInstitution({
  institutionId,
  institutionName,
  institutionCatalogId,
  joinCode,
  adminUser,
  adminPhone,
  additionalAdminPhone,
}) {
  await ensureInstitutionCatalogAvailable(institutionCatalogId, institutionId);

  const normalizedName = normalizeInstitutionName(institutionName);
  const institutionRef = db.collection('institutions').doc(institutionId);
  const existing = await institutionRef.get();
  const existingJoinCode = String(existing.data()?.joinCode ?? '')
    .trim()
    .toUpperCase();
  const activeJoinCode = (joinCode || existingJoinCode || generateJoinCode(8))
    .trim()
    .toUpperCase();
  const now = new Date();

  await institutionRef.set(
    {
      name: institutionName,
      nameNormalized: normalizedName,
      institutionCatalogId,
      status: 'approved',
      createdBy: adminUser.uid,
      adminPhoneNumber: adminPhone,
      additionalAdminPhoneNumber: additionalAdminPhone,
      contactPhone: adminPhone,
      counselorDirectoryEnabled: true,
      counselorReassignmentEnabled: true,
      joinCode: activeJoinCode,
      joinCodeCreatedAt: makeTimestamp(now),
      joinCodeExpiresAt: makeTimestamp(
        new Date(now.getTime() + 24 * 60 * 60 * 1000)
      ),
      joinCodeUsageCount: 3,
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      review: {
        reviewedBy: adminUser.uid,
        reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
        decision: 'approved',
        declineReason: null,
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(existing.exists
        ? {}
        : { createdAt: admin.firestore.FieldValue.serverTimestamp() }),
    },
    { merge: true }
  );

  await db
    .collection('institution_catalog_registry')
    .doc(institutionCatalogId)
    .set(
      {
        institutionId,
        institutionCatalogId,
        institutionName,
        status: 'approved',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  await db
    .collection('institution_name_registry')
    .doc(institutionNameRegistryDocId(normalizedName))
    .set(
      {
        institutionId,
        institutionName,
        normalizedName,
        status: 'approved',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  return activeJoinCode;
}

async function upsertUserProfile({
  userRecord,
  account,
  role,
  institutionId,
  institutionName,
  institutionCatalogId,
  onboardingVersionValue,
}) {
  const normalizedPrimaryPhone = normalizePhoneE164(account.phoneNumber);
  const normalizedAdditionalPhone = normalizeOptionalPhoneE164(
    account.additionalPhoneNumber
  );
  const phoneNumbers = buildPhoneCandidates(
    normalizedPrimaryPhone,
    normalizedAdditionalPhone
  );
  await ensureSafeExistingProfile({
    uid: userRecord.uid,
    email: account.email,
    targetRole: role,
    institutionId,
  });
  await ensurePhoneRegistry(
    userRecord.uid,
    normalizedPrimaryPhone,
    normalizedAdditionalPhone
  );

  const completedRoles =
    role === 'student' || role === 'staff'
      ? { [role]: onboardingVersionValue }
      : {};

  const payload = {
    email: normalizeEmail(account.email),
    name: account.name.trim(),
    role,
    onboardingCompletedRoles: completedRoles,
    counselorSetupCompleted: role === 'counselor',
    counselorSetupData:
      role === 'counselor'
        ? {
            institutionId,
            displayName: account.name.trim(),
            title: account.title ?? 'Licensed Counselor',
            specialization: account.specialization ?? 'Student wellbeing',
            yearsExperience: Number(account.yearsExperience ?? 6),
            sessionMode: account.sessionMode ?? 'virtual',
            timezone: account.timezone ?? 'Africa/Nairobi',
            bio:
              account.bio ??
              'Microsoft Store review counselor account for MindNest.',
            languages: Array.isArray(account.languages)
              ? account.languages
              : ['English', 'Swahili'],
            ratingAverage: 4.8,
            ratingCount: 3,
            isActive: true,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        : {},
    counselorPreferences:
      role === 'counselor'
        ? {
            defaultSessionMinutes: 50,
            breakBetweenSessionsMins: 10,
            allowDirectBooking: true,
            autoApproveFollowUps: false,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        : {},
    aiAssistantPreferences: {},
    institutionId,
    institutionName,
    phoneNumber: normalizedPrimaryPhone,
    additionalPhoneNumber: normalizedAdditionalPhone,
    phoneNumbers,
    registrationIntent: null,
    institutionWelcomePending: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(role === 'institutionAdmin'
      ? { institutionCatalogId }
      : {}),
    ...(role === 'counselor' ? { counselorApprovalStatus: 'approved' } : {}),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection('users').doc(userRecord.uid).set(payload, { merge: true });

  if (role === 'counselor') {
    await db.collection('counselor_profiles').doc(userRecord.uid).set(
      {
        institutionId,
        displayName: account.name.trim(),
        title: account.title ?? 'Licensed Counselor',
        specialization: account.specialization ?? 'Student wellbeing',
        yearsExperience: Number(account.yearsExperience ?? 6),
        sessionMode: account.sessionMode ?? 'virtual',
        timezone: account.timezone ?? 'Africa/Nairobi',
        bio:
          account.bio ??
          'Microsoft Store review counselor account for MindNest.',
        languages: Array.isArray(account.languages)
          ? account.languages
          : ['English', 'Swahili'],
        ratingAverage: 4.8,
        ratingCount: 3,
        isActive: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  if (role === 'student' || role === 'staff') {
    await db
      .collection('onboarding_responses')
      .doc(`${userRecord.uid}_${role}_v${onboardingVersionValue}`)
      .set(
        {
          userId: userRecord.uid,
          role,
          version: onboardingVersionValue,
          answers: buildDefaultOnboardingAnswers(role),
          submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
  }

  return {
    primaryPhone: normalizedPrimaryPhone,
    additionalPhone: normalizedAdditionalPhone,
    phoneNumbers,
  };
}

async function upsertMembership({
  institutionId,
  userRecord,
  account,
  role,
  inviteId,
}) {
  const ref = db.collection('institution_members').doc(`${institutionId}_${userRecord.uid}`);
  await ref.set(
    {
      institutionId,
      userId: userRecord.uid,
      role,
      userName: account.name.trim(),
      email: normalizeEmail(account.email),
      phoneNumber: normalizePhoneE164(account.phoneNumber),
      ...(account.additionalPhoneNumber
        ? { additionalPhoneNumber: normalizeOptionalPhoneE164(account.additionalPhoneNumber) }
        : {}),
      joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'active',
      ...(inviteId
        ? {
            joinedVia: 'invite',
            inviteId,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        : {
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }),
    },
    { merge: true }
  );
}

async function upsertAcceptedInvite({
  institutionId,
  institutionName,
  joinCode,
  adminUid,
  userRecord,
  account,
  role,
}) {
  const inviteId = `${institutionId}_${role}_review`;
  await db.collection('user_invites').doc(inviteId).set(
    {
      institutionId,
      institutionName,
      inviteeUid: userRecord.uid,
      inviteePhoneE164: normalizePhoneE164(account.phoneNumber),
      invitedName: account.name.trim(),
      invitedEmail: normalizeEmail(account.email),
      intendedRole: role,
      status: 'accepted',
      invitedBy: adminUid,
      acceptedByUid: userRecord.uid,
      acceptedWithCode: joinCode,
      oneTimeUse: true,
      deliveryChannel: 'in_app',
      expiresAt: makeTimestamp(
        new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
      ),
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  return inviteId;
}

function buildPartnerCenterNotes({
  institutionName,
  joinCode,
  accounts,
}) {
  return `Certification accounts for review:

Institution: ${institutionName}
Institution code: ${joinCode}

Institution Admin
Email: ${accounts.institutionAdmin.email}
Password: ${accounts.institutionAdmin.password}

Counselor
Email: ${accounts.counselor.email}
Password: ${accounts.counselor.password}

Student
Email: ${accounts.student.email}
Password: ${accounts.student.password}

Staff
Email: ${accounts.staff.email}
Password: ${accounts.staff.password}

Review steps:
1. Launch MindNest and sign in with the Institution Admin account first.
2. Review the institution admin workspace, member list, and invite composer.
3. Sign out and sign in with the Counselor account to review the counselor workspace.
4. Sign out and sign in with the Student account to review the student dashboard, appointments, and counselor directory.
5. Sign out and sign in with the Staff account to review the staff role experience.

Notes:
- MindNest is role-based, so four dedicated accounts are provided instead of one shared account.
- All review accounts belong to the same approved institution for end-to-end testing.
- The counselor, student, and staff accounts are already linked to the institution through accepted invite data.`;
}

async function writePartnerCenterNotes(notesPath, notesText) {
  const resolved = path.resolve(scriptDir, notesPath);
  await fs.mkdir(path.dirname(resolved), { recursive: true });
  await fs.writeFile(resolved, notesText, 'utf8');
  return resolved;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const serviceAccount = await resolveServiceAccount(args);
  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
  db = admin.firestore();
  auth = admin.auth();

  const configPath = path.resolve(
    scriptDir,
    String(args['--config'] || args._positionals?.[0] || DEFAULT_CONFIG_PATH)
  );

  let config;
  try {
    config = await readJson(configPath);
  } catch (error) {
    if (error.code === 'ENOENT') {
      throw new Error(
        `Reviewer config not found at ${configPath}.\nCopy ${EXAMPLE_CONFIG_PATH} to reviewer-accounts.config.local.json, fill in real values, then rerun.`
      );
    }
    throw error;
  }

  const institutionName = requireString(config?.institution?.name, 'institution.name');
  const institutionCatalogId = requireString(
    config?.institution?.catalogId,
    'institution.catalogId'
  );

  const roleKeys = ['institutionAdmin', 'counselor', 'student', 'staff'];
  const normalizedAccounts = {};
  const seenEmails = new Set();
  const seenPhones = new Set();
  for (const roleKey of roleKeys) {
    const raw = config?.accounts?.[roleKey] ?? {};
    const normalizedEmail = normalizeEmail(requireString(raw.email, `${roleKey}.email`));
    const normalizedPhone = normalizePhoneE164(
      requireString(raw.phoneNumber, `${roleKey}.phoneNumber`)
    );
    if (seenEmails.has(normalizedEmail)) {
      throw new Error(`Duplicate reviewer email detected: ${normalizedEmail}`);
    }
    if (seenPhones.has(normalizedPhone)) {
      throw new Error(`Duplicate reviewer phone number detected: ${normalizedPhone}`);
    }
    seenEmails.add(normalizedEmail);
    seenPhones.add(normalizedPhone);
    normalizedAccounts[roleKey] = {
      ...raw,
      email: normalizedEmail,
      password: requireString(raw.password, `${roleKey}.password`),
      name: requireString(raw.name, `${roleKey}.name`),
      phoneNumber: normalizedPhone,
      additionalPhoneNumber: normalizeOptionalPhoneE164(raw.additionalPhoneNumber),
    };
  }

  const adminAccount = normalizedAccounts.institutionAdmin;
  const adminAuthUser = await ensureAuthUser({
    email: adminAccount.email,
    password: adminAccount.password,
    name: adminAccount.name,
  });

  const adminProfileSnapshot = await db.collection('users').doc(adminAuthUser.uid).get();
  const existingInstitutionId = String(
    adminProfileSnapshot.data()?.institutionId ?? ''
  ).trim();
  const institutionId =
    requireString(
      config?.institution?.id || existingInstitutionId || sanitizeInstitutionId(institutionCatalogId),
      'institution.id'
    );

  const joinCode = await upsertInstitution({
    institutionId,
    institutionName,
    institutionCatalogId,
    joinCode: String(config?.institution?.joinCode ?? '').trim().toUpperCase(),
    adminUser: adminAuthUser,
    adminPhone: adminAccount.phoneNumber,
    additionalAdminPhone: adminAccount.additionalPhoneNumber,
  });

  const onboardingVersionValue = await onboardingVersion();

  await upsertUserProfile({
    userRecord: adminAuthUser,
    account: adminAccount,
    role: 'institutionAdmin',
    institutionId,
    institutionName,
    institutionCatalogId,
    onboardingVersionValue,
  });
  await upsertMembership({
    institutionId,
    userRecord: adminAuthUser,
    account: adminAccount,
    role: 'institutionAdmin',
    inviteId: null,
  });

  for (const roleKey of ['counselor', 'student', 'staff']) {
    const account = normalizedAccounts[roleKey];
    const userRecord = await ensureAuthUser({
      email: account.email,
      password: account.password,
      name: account.name,
    });
    await upsertUserProfile({
      userRecord,
      account,
      role: roleKey,
      institutionId,
      institutionName,
      institutionCatalogId,
      onboardingVersionValue,
    });
    const inviteId = await upsertAcceptedInvite({
      institutionId,
      institutionName,
      joinCode,
      adminUid: adminAuthUser.uid,
      userRecord,
      account,
      role: roleKey,
    });
    await upsertMembership({
      institutionId,
      userRecord,
      account,
      role: roleKey,
      inviteId,
    });
  }

  const notesText = buildPartnerCenterNotes({
    institutionName,
    joinCode,
    accounts: normalizedAccounts,
  });
  const outputPath = await writePartnerCenterNotes(
    config?.output?.partnerCenterNotesPath ||
      '../../docs/windows_store_review_notes.local.txt',
    notesText
  );

  console.log('');
  console.log('MindNest reviewer accounts are ready.');
  console.log(`Institution ID: ${institutionId}`);
  console.log(`Institution name: ${institutionName}`);
  console.log(`Join code: ${joinCode}`);
  console.log(`Partner Center notes: ${outputPath}`);
  console.log('');
  console.log('Seeded accounts:');
  for (const roleKey of roleKeys) {
    console.log(
      `- ${roleLabel(roleKey)}: ${normalizedAccounts[roleKey].email}`
    );
  }
}

main().catch((error) => {
  console.error('');
  console.error('Failed to prepare MindNest reviewer accounts.');
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
