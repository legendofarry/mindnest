// features/institutions/data/institution_repository.dart
import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/core/data/windows_firestore_rest_client.dart';
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';
import 'package:mindnest/features/onboarding/data/onboarding_question_bank.dart';

class InAppInviteDraft {
  const InAppInviteDraft({
    required this.inviteId,
    required this.inviteeUid,
    required this.inviteePhoneE164,
    required this.invitedEmail,
    required this.invitedName,
    required this.institutionId,
    required this.institutionName,
    required this.role,
    required this.expiresAtUtc,
    required this.joinCode,
    required this.whatsAppDeepLink,
    required this.whatsAppMessage,
  });

  final String inviteId;
  final String inviteeUid;
  final String inviteePhoneE164;
  final String invitedEmail;
  final String invitedName;
  final String institutionId;
  final String institutionName;
  final UserRole role;
  final DateTime expiresAtUtc;
  final String joinCode;
  final String whatsAppDeepLink;
  final String whatsAppMessage;
}

class InstitutionRepository {
  InstitutionRepository({
    required FirebaseFirestore Function()? firestoreFactory,
    required AppAuthClient auth,
    required http.Client httpClient,
    required WindowsFirestoreRestClient windowsRest,
  }) : _firestoreFactory = firestoreFactory,
       _auth = auth,
       _httpClient = httpClient,
       _windowsRest = windowsRest;

  static const Duration _joinCodeValidity = Duration(hours: 24);
  static const Duration _inviteValidity = Duration(days: 7);
  static const Duration _windowsPollInterval = Duration(seconds: 15);
  static const int _joinCodeMaxUses = 50;
  static const String _joinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const String _pushDispatchEndpointFromDefine = String.fromEnvironment(
    'PUSH_DISPATCH_ENDPOINT',
    defaultValue: '',
  );
  static const String _pushDispatchEndpointFromSource =
      'https://mindnest-0o6x.onrender.com/push/dispatch';
  static String get _pushDispatchEndpoint =>
      _pushDispatchEndpointFromDefine.isNotEmpty
      ? _pushDispatchEndpointFromDefine
      : _pushDispatchEndpointFromSource;

  final FirebaseFirestore Function()? _firestoreFactory;
  FirebaseFirestore? _cachedFirestore;
  final AppAuthClient _auth;
  final http.Client _httpClient;
  final WindowsFirestoreRestClient _windowsRest;
  final Random _random = Random.secure();
  int _windowsRestIdCounter = 0;

  bool get _useWindowsPollingWorkaround =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  FirebaseFirestore get _firestore => _cachedFirestore ??=
      _firestoreFactory?.call() ??
      (throw StateError(
        'Native Firestore is disabled for Windows REST auth flows.',
      ));

  String _windowsDocId(String prefix) {
    _windowsRestIdCounter += 1;
    return '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_$_windowsRestIdCounter';
  }

  Future<AppAuthUser> _ensureWindowsAuthenticatedAfterSignUp({
    required String email,
    required String password,
    required AppAuthUser fallbackUser,
  }) async {
    if (!kUseWindowsRestAuth) {
      return fallbackUser;
    }

    AppAuthUser currentUser = _auth.currentUser ?? fallbackUser;

    Future<void> refreshSession() async {
      await _auth.reloadCurrentUser();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser != null) {
        currentUser = refreshedUser;
      }
    }

    Future<void> signInAgain() async {
      final signIn = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      currentUser = signIn.user;
    }

    await refreshSession();
    var idToken = await _auth.getIdToken(forceRefresh: true);
    if ((idToken ?? '').trim().isEmpty) {
      await signInAgain();
      await refreshSession();
      idToken = await _auth.getIdToken(forceRefresh: true);
    }

    if ((idToken ?? '').trim().isEmpty) {
      throw Exception(
        'We could not activate the new account on Windows. Please try again.',
      );
    }

    if (currentUser.uid.isNotEmpty && currentUser.uid != fallbackUser.uid) {
      throw Exception(
        'We could not activate the newly created institution account. Please try again.',
      );
    }

    return currentUser;
  }

  Stream<UserInvite?> pendingInviteForUid(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Stream<UserInvite?>.value(null);
    }
    if (kUseWindowsRestAuth) {
      return _buildWindowsPollingStream<UserInvite?>(
        load: () => getPendingInviteForUid(normalizedUid),
        signature: (invite) => invite == null
            ? 'null'
            : '${invite.id}|${invite.status.name}|${invite.expiresAt?.toIso8601String() ?? ''}',
      );
    }
    return _firestore
        .collection('user_invites')
        .where('inviteeUid', isEqualTo: normalizedUid)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }
          for (final doc in snapshot.docs) {
            final invite = UserInvite.fromMap(doc.id, doc.data());
            if (invite.isExpired) {
              continue;
            }
            final revokedAt = _asUtcDate(doc.data()['revokedAt']);
            if (revokedAt != null) {
              continue;
            }
            return invite;
          }
          return null;
        });
  }

  Future<UserInvite?> getPendingInviteForUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'user_invites',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('inviteeUid', normalizedUid),
          WindowsFirestoreFieldFilter.equal(
            'status',
            UserInviteStatus.pending.name,
          ),
        ],
      );
      for (final doc in documents) {
        final invite = UserInvite.fromMap(doc.id, doc.data);
        if (invite.isExpired) {
          continue;
        }
        final revokedAt = _asUtcDate(doc.data['revokedAt']);
        if (revokedAt != null) {
          continue;
        }
        return invite;
      }
      return null;
    }

    final snapshot = await _firestore
        .collection('user_invites')
        .where('inviteeUid', isEqualTo: normalizedUid)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    for (final doc in snapshot.docs) {
      final invite = UserInvite.fromMap(doc.id, doc.data());
      if (invite.isExpired) {
        continue;
      }
      final revokedAt = _asUtcDate(doc.data()['revokedAt']);
      if (revokedAt != null) {
        continue;
      }
      return invite;
    }

    return null;
  }

  /// Returns all active (pending and not expired/revoked) invites for a user.
  Stream<List<UserInvite>> pendingInvitesForUid(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Stream<List<UserInvite>>.value(const []);
    }
    if (kUseWindowsRestAuth) {
      return _buildWindowsPollingStream<List<UserInvite>>(
        load: () => getPendingInvitesForUid(normalizedUid),
        signature: (invites) => invites
            .map(
              (invite) =>
                  '${invite.id}|${invite.status.name}|${invite.expiresAt?.toIso8601String() ?? ''}',
            )
            .join(';'),
      );
    }
    return _firestore
        .collection('user_invites')
        .where('inviteeUid', isEqualTo: normalizedUid)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .snapshots()
        .map((snapshot) {
          final invites = <UserInvite>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final invite = UserInvite.fromMap(doc.id, data);
            if (!invite.isPending) {
              continue;
            }
            final revokedAt = _asUtcDate(data['revokedAt']);
            if (revokedAt != null) {
              continue;
            }
            invites.add(invite);
          }
          return invites;
        });
  }

  Future<List<UserInvite>> getPendingInvitesForUid(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return const <UserInvite>[];
    }
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'user_invites',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('inviteeUid', normalizedUid),
          WindowsFirestoreFieldFilter.equal(
            'status',
            UserInviteStatus.pending.name,
          ),
        ],
      );
      final invites = <UserInvite>[];
      for (final doc in documents) {
        final invite = UserInvite.fromMap(doc.id, doc.data);
        if (!invite.isPending) {
          continue;
        }
        final revokedAt = _asUtcDate(doc.data['revokedAt']);
        if (revokedAt != null) {
          continue;
        }
        invites.add(invite);
      }
      return invites;
    }

    final snapshot = await _firestore
        .collection('user_invites')
        .where('inviteeUid', isEqualTo: normalizedUid)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .get();

    final invites = <UserInvite>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final invite = UserInvite.fromMap(doc.id, data);
      if (!invite.isPending) {
        continue;
      }
      final revokedAt = _asUtcDate(data['revokedAt']);
      if (revokedAt != null) {
        continue;
      }
      invites.add(invite);
    }
    return invites;
  }

  Stream<UserInvite?> pendingInviteByIdForUid({
    required String inviteId,
    required String uid,
  }) {
    final normalizedUid = uid.trim();
    if (kUseWindowsRestAuth) {
      return _buildWindowsPollingStream<UserInvite?>(
        load: () =>
            getPendingInviteByIdForUid(inviteId: inviteId, uid: normalizedUid),
        signature: (invite) => invite == null
            ? 'null'
            : '${invite.id}|${invite.status.name}|${invite.expiresAt?.toIso8601String() ?? ''}',
      );
    }
    return _firestore.collection('user_invites').doc(inviteId).snapshots().map((
      snapshot,
    ) {
      final data = snapshot.data();
      if (data == null) {
        return null;
      }
      final invite = UserInvite.fromMap(snapshot.id, data);
      if (!invite.isPending) {
        return null;
      }
      if (invite.inviteeUid != normalizedUid) {
        return null;
      }
      final revokedAt = _asUtcDate(data['revokedAt']);
      if (revokedAt != null) {
        return null;
      }
      return invite;
    });
  }

  Future<UserInvite?> getPendingInviteByIdForUid({
    required String inviteId,
    required String uid,
  }) async {
    final normalizedUid = uid.trim();
    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('user_invites/$inviteId'))?.data
        : (await _firestore.collection('user_invites').doc(inviteId).get())
              .data();
    if (data == null) {
      return null;
    }
    final invite = UserInvite.fromMap(inviteId, data);
    if (!invite.isPending) {
      return null;
    }
    if (invite.inviteeUid != normalizedUid) {
      return null;
    }
    final revokedAt = _asUtcDate(data['revokedAt']);
    if (revokedAt != null) {
      return null;
    }
    return invite;
  }

  Future<UserInvite?> getInviteById(String inviteId) async {
    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('user_invites/$inviteId'))?.data
        : (await _firestore.collection('user_invites').doc(inviteId).get())
              .data();
    if (data == null) {
      return null;
    }
    return UserInvite.fromMap(inviteId, data);
  }

  Future<bool> isInstitutionCatalogIdAvailable(
    String institutionCatalogId,
  ) async {
    final normalizedCatalogId = institutionCatalogId.trim();
    if (normalizedCatalogId.isEmpty) {
      return false;
    }
    if (kUseWindowsRestAuth) {
      final registrySnapshot = await _windowsRest.getDocument(
        _institutionCatalogRegistryPath(normalizedCatalogId),
        allowUnauthenticated: _auth.currentUser == null,
      );
      return registrySnapshot == null;
    }

    final registrySnapshot = await _institutionCatalogRegistryRef(
      normalizedCatalogId,
    ).get();
    return !registrySnapshot.exists;
  }

  Future<void> createInstitutionAdminAccount({
    required String adminName,
    required String adminEmail,
    required String adminPhoneNumber,
    String? additionalAdminPhoneNumber,
    required String password,
    required String institutionCatalogId,
    required String institutionName,
  }) async {
    final trimmedName = adminName.trim();
    final trimmedInstitutionCatalogId = institutionCatalogId.trim();
    final trimmedInstitutionName = institutionName.trim();
    final normalizedAdminPhone = _normalizePhoneE164(adminPhoneNumber);
    final normalizedAdditionalAdminPhone = _normalizeOptionalPhoneE164(
      additionalAdminPhoneNumber,
    );
    if (normalizedAdditionalAdminPhone == normalizedAdminPhone) {
      throw Exception(
        'Additional mobile number must be different from primary mobile number.',
      );
    }
    final phoneCandidates = _buildPhoneCandidates(
      primaryPhone: normalizedAdminPhone,
      additionalPhone: normalizedAdditionalAdminPhone,
    );
    final normalizedEmail = adminEmail.trim().toLowerCase();
    final normalizedInstitutionName = _normalizeInstitutionName(
      trimmedInstitutionName,
    );
    if (trimmedName.length < 2 ||
        trimmedInstitutionCatalogId.isEmpty ||
        trimmedInstitutionName.length < 2) {
      throw Exception('Name, institution name, and phone number are required.');
    }

    await _assertInstitutionCatalogIdAvailable(trimmedInstitutionCatalogId);

    if (kUseWindowsRestAuth) {
      final institutionId = _windowsDocId('institution');
      final catalogRegistryPath = _institutionCatalogRegistryPath(
        trimmedInstitutionCatalogId,
      );
      final nameRegistryPath = _institutionNameRegistryPath(
        normalizedInstitutionName,
      );

      AppAuthUser? user;
      try {
        final credential = await _auth.createUserWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
          displayName: trimmedName,
        );
        user = await _ensureWindowsAuthenticatedAfterSignUp(
          email: normalizedEmail,
          password: password,
          fallbackUser: credential.user,
        );
        final createdUser = user;
        final now = DateTime.now().toUtc();

        await _auth.sendEmailVerification();

        for (final path in _phoneRegistryPathsForRegistration(
          primaryPhoneNumber: normalizedAdminPhone,
          additionalPhoneNumber: normalizedAdditionalAdminPhone,
        )) {
          final registryPhoneSnapshot = await _windowsRest.getDocument(path);
          if (registryPhoneSnapshot == null) {
            continue;
          }
          final ownerUid = (registryPhoneSnapshot.data['uid'] as String?) ?? '';
          if (ownerUid != createdUser.uid) {
            final claimedPhone =
                (registryPhoneSnapshot.data['phoneNumber'] as String?) ??
                '+${registryPhoneSnapshot.id}';
            throw _PhoneNumberAlreadyInUseException(
              'The mobile number $claimedPhone is already linked to another account.',
            );
          }
        }

        final registrySnapshot = await _windowsRest.getDocument(
          catalogRegistryPath,
        );
        if (registrySnapshot != null) {
          final claimedInstitutionId =
              (registrySnapshot.data['institutionId'] as String?) ?? '';
          if (claimedInstitutionId != institutionId) {
            throw const _InstitutionDuplicationException(
              'This institution already exists or is pending approval.',
            );
          }
        }

        await _windowsRest.setDocument('institutions/$institutionId', {
          'name': trimmedInstitutionName,
          'nameNormalized': normalizedInstitutionName,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'status': 'pending',
          'createdBy': createdUser.uid,
          'adminPhoneNumber': normalizedAdminPhone,
          'additionalAdminPhoneNumber': normalizedAdditionalAdminPhone,
          'contactPhone': normalizedAdminPhone,
          'createdAt': now,
          'updatedAt': now,
          'review': const <String, dynamic>{
            'reviewedBy': null,
            'reviewedAt': null,
            'decision': null,
            'declineReason': null,
          },
        });
        await _windowsRest.setDocument('users/${createdUser.uid}', {
          'email': createdUser.email,
          'name': trimmedName,
          'role': UserRole.institutionAdmin.name,
          'onboardingCompletedRoles': const <String, int>{},
          'institutionId': institutionId,
          'institutionName': trimmedInstitutionName,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'institutionWelcomePending': true,
          'phoneNumber': normalizedAdminPhone,
          'additionalPhoneNumber': normalizedAdditionalAdminPhone,
          'phoneNumbers': phoneCandidates,
          'createdAt': now,
          'updatedAt': now,
        });
        await _windowsRest.setDocument(
          'institution_members/${institutionId}_${createdUser.uid}',
          {
            'institutionId': institutionId,
            'userId': createdUser.uid,
            'role': UserRole.institutionAdmin.name,
            'userName': trimmedName,
            'email': createdUser.email,
            'phoneNumber': normalizedAdminPhone,
            'additionalPhoneNumber': normalizedAdditionalAdminPhone,
            'joinedAt': now,
            'status': 'active',
            'updatedAt': now,
          },
        );
        for (final key in _phoneRegistryKeysForRegistration(
          primaryPhoneNumber: normalizedAdminPhone,
          additionalPhoneNumber: normalizedAdditionalAdminPhone,
        )) {
          await _windowsRest.setDocument('phone_number_registry/$key', {
            'uid': createdUser.uid,
            'phoneNumber': '+$key',
            'createdAt': now,
            'updatedAt': now,
          });
        }
        await _windowsRest.setDocument(catalogRegistryPath, {
          ...(await _windowsRest.getDocument(catalogRegistryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'institutionName': trimmedInstitutionName,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
        await _windowsRest.setDocument(nameRegistryPath, {
          ...(await _windowsRest.getDocument(nameRegistryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionName': trimmedInstitutionName,
          'normalizedName': normalizedInstitutionName,
          'status': 'pending',
          'createdAt': now,
          'updatedAt': now,
        });
      } on _PhoneNumberAlreadyInUseException catch (error) {
        if (user != null) {
          try {
            await _auth.deleteCurrentUser();
          } catch (_) {}
        }
        throw Exception(error.message);
      } on _InstitutionDuplicationException {
        if (user != null) {
          try {
            await _auth.deleteCurrentUser();
          } catch (_) {}
        }
        throw Exception(
          'This institution already exists or is pending approval.',
        );
      }

      final ownerUserId = await _resolveOwnerUserId();
      if (ownerUserId != null) {
        await _createNotifications([
          _notificationPayload(
            userId: ownerUserId,
            institutionId: institutionId,
            type: 'institution_request_submitted',
            title: 'New institution approval request',
            body: '$trimmedInstitutionName was submitted for approval.',
          ),
        ]);
      }

      await _createNotifications([
        _notificationPayload(
          userId: user.uid,
          institutionId: institutionId,
          type: 'institution_request_pending',
          title: 'Institution submitted',
          body:
              'Your institution request is pending review. Approval usually takes about 30 minutes.',
        ),
      ]);
      return;
    }

    final institutionRef = _firestore.collection('institutions').doc();
    final catalogRegistryRef = _institutionCatalogRegistryRef(
      trimmedInstitutionCatalogId,
    );

    AppAuthUser? user;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
        displayName: trimmedName,
      );
      user = credential.user;
      final createdUser = user;

      await _auth.sendEmailVerification();

      final membershipRef = _firestore
          .collection('institution_members')
          .doc('${institutionRef.id}_${createdUser.uid}');

      await _firestore.runTransaction((transaction) async {
        final phoneRegistryRefs = _phoneRegistryRefsForRegistration(
          primaryPhoneNumber: normalizedAdminPhone,
          additionalPhoneNumber: normalizedAdditionalAdminPhone,
        );
        for (final ref in phoneRegistryRefs) {
          final registryPhoneSnapshot = await transaction.get(ref);
          if (!registryPhoneSnapshot.exists) {
            continue;
          }
          final ownerUid =
              (registryPhoneSnapshot.data()?['uid'] as String?) ?? '';
          if (ownerUid != createdUser.uid) {
            final claimedPhone =
                (registryPhoneSnapshot.data()?['phoneNumber'] as String?) ??
                '+${ref.id}';
            throw _PhoneNumberAlreadyInUseException(
              'The mobile number $claimedPhone is already linked to another account.',
            );
          }
        }

        final registrySnapshot = await transaction.get(catalogRegistryRef);
        if (registrySnapshot.exists) {
          final claimedInstitutionId =
              (registrySnapshot.data()?['institutionId'] as String?) ?? '';
          if (claimedInstitutionId != institutionRef.id) {
            throw const _InstitutionDuplicationException(
              'This institution already exists or is pending approval.',
            );
          }
        }

        transaction.set(institutionRef, {
          'name': trimmedInstitutionName,
          'nameNormalized': normalizedInstitutionName,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'status': 'pending',
          'createdBy': createdUser.uid,
          'adminPhoneNumber': normalizedAdminPhone,
          'additionalAdminPhoneNumber': normalizedAdditionalAdminPhone,
          'contactPhone': normalizedAdminPhone,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'review': <String, dynamic>{
            'reviewedBy': null,
            'reviewedAt': null,
            'decision': null,
            'declineReason': null,
          },
        });
        transaction.set(_firestore.collection('users').doc(createdUser.uid), {
          'email': createdUser.email,
          'name': trimmedName,
          'role': UserRole.institutionAdmin.name,
          'onboardingCompletedRoles': <String, int>{},
          'institutionId': institutionRef.id,
          'institutionName': trimmedInstitutionName,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'institutionWelcomePending': true,
          'phoneNumber': normalizedAdminPhone,
          'additionalPhoneNumber': normalizedAdditionalAdminPhone,
          'phoneNumbers': phoneCandidates,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(membershipRef, {
          'institutionId': institutionRef.id,
          'userId': createdUser.uid,
          'role': UserRole.institutionAdmin.name,
          'userName': trimmedName,
          'email': createdUser.email,
          'phoneNumber': normalizedAdminPhone,
          'additionalPhoneNumber': normalizedAdditionalAdminPhone,
          'joinedAt': FieldValue.serverTimestamp(),
          'status': 'active',
        });
        for (final ref in phoneRegistryRefs) {
          transaction.set(ref, {
            'uid': createdUser.uid,
            'phoneNumber': '+${ref.id}',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        transaction.set(catalogRegistryRef, {
          'institutionId': institutionRef.id,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'institutionName': trimmedInstitutionName,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(
          _institutionNameRegistryRef(normalizedInstitutionName),
          {
            'institutionId': institutionRef.id,
            'institutionName': trimmedInstitutionName,
            'normalizedName': normalizedInstitutionName,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } on _PhoneNumberAlreadyInUseException catch (error) {
      if (user != null) {
        try {
          await _auth.deleteCurrentUser();
        } catch (_) {
          // Keep rollback resilient.
        }
      }
      throw Exception(error.message);
    } on _InstitutionDuplicationException {
      if (user != null) {
        try {
          await _auth.deleteCurrentUser();
        } catch (_) {
          // Keep error handling resilient if user cleanup fails.
        }
      }
      throw Exception(
        'This institution already exists or is pending approval.',
      );
    }

    final ownerUserId = await _resolveOwnerUserId();
    if (ownerUserId != null) {
      await _createNotifications([
        _notificationPayload(
          userId: ownerUserId,
          institutionId: institutionRef.id,
          type: 'institution_request_submitted',
          title: 'New institution approval request',
          body: '$trimmedInstitutionName was submitted for approval.',
        ),
      ]);
    }

    final createdUserId = user.uid;

    await _createNotifications([
      _notificationPayload(
        userId: createdUserId,
        institutionId: institutionRef.id,
        type: 'institution_request_pending',
        title: 'Institution submitted',
        body:
            'Your institution request is pending review. Approval usually takes about 30 minutes.',
      ),
    ]);
  }

  Future<InAppInviteDraft> createRoleInvite({
    required String inviteePhoneNumber,
    required UserRole role,
  }) async {
    if (role != UserRole.student &&
        role != UserRole.staff &&
        role != UserRole.counselor) {
      throw Exception('Invite role must be Student, Staff, or Counselor.');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final profile = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can create invites.');
    }

    final institutionId = (profile['institutionId'] as String?) ?? '';
    final institutionName = (profile['institutionName'] as String?) ?? '';
    final inviterName =
        (profile['name'] as String?)?.trim() ??
        (currentUser.displayName?.trim().isNotEmpty == true
            ? currentUser.displayName!.trim()
            : 'Institution Admin');
    if (institutionId.isEmpty || institutionName.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final normalizedPhone = _normalizePhoneE164(inviteePhoneNumber);
    late final String inviteeUserId;
    late final Map<String, dynamic> inviteeData;
    if (kUseWindowsRestAuth) {
      final inviteeUser = await _resolveInviteeByPhoneWindows(normalizedPhone);
      inviteeUserId = inviteeUser.id;
      inviteeData = inviteeUser.data;
    } else {
      final inviteeSnapshot = await _resolveInviteeByPhone(normalizedPhone);
      inviteeUserId = inviteeSnapshot.id;
      inviteeData = inviteeSnapshot.data();
    }
    if (inviteeUserId == currentUser.uid) {
      throw Exception('You cannot invite your own account.');
    }
    if (role == UserRole.counselor) {
      final inviteeRole = (inviteeData['role'] as String?) ?? '';
      final registrationIntent =
          (inviteeData['registrationIntent'] as String?) ?? '';
      final hasCounselorIntent =
          registrationIntent == UserProfile.counselorRegistrationIntent;
      final isCounselor = inviteeRole == UserRole.counselor.name;
      if (!hasCounselorIntent && !isCounselor) {
        throw Exception(
          'This user is not set up as a counselor. Ask them to register using "I am a counselor" first, then invite again.',
        );
      }
    }
    final invitedName =
        ((inviteeData['name'] as String?) ?? '').trim().isNotEmpty
        ? ((inviteeData['name'] as String?) ?? '').trim()
        : 'MindNest user';
    final invitedEmail = ((inviteeData['email'] as String?) ?? '')
        .trim()
        .toLowerCase();

    await _assertInviteeNotAlreadyMember(
      targetInstitutionId: institutionId,
      inviteeUid: inviteeUserId,
      inviteeInstitutionId: (inviteeData['institutionId'] as String?) ?? '',
    );

    await _assertNoActivePendingInvite(
      institutionId: institutionId,
      inviteeUid: inviteeUserId,
      role: role,
    );

    final institutionData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('institutions/$institutionId'))?.data
        : (await _firestore.collection('institutions').doc(institutionId).get())
              .data();
    final activeJoinCode = (institutionData?['joinCode'] as String? ?? '')
        .trim()
        .toUpperCase();
    if (activeJoinCode.isEmpty) {
      throw Exception(
        'No active institution code is available. Regenerate code and retry.',
      );
    }

    final nowUtc = DateTime.now().toUtc();
    final expiresAtUtc = nowUtc.add(_inviteValidity);
    final inviteId = kUseWindowsRestAuth
        ? _windowsDocId('invite')
        : _firestore.collection('user_invites').doc().id;

    if (kUseWindowsRestAuth) {
      await _windowsRest.setDocument('user_invites/$inviteId', {
        'institutionId': institutionId,
        'institutionName': institutionName,
        'inviteeUid': inviteeUserId,
        'inviteePhoneE164': normalizedPhone,
        'invitedName': invitedName,
        'invitedEmail': invitedEmail,
        'intendedRole': role.name,
        'status': UserInviteStatus.pending.name,
        'invitedBy': currentUser.uid,
        'oneTimeUse': true,
        'deliveryChannel': 'in_app',
        'expiresAt': expiresAtUtc,
        'createdAt': nowUtc,
        'updatedAt': nowUtc,
      });
    } else {
      await _firestore.collection('user_invites').doc(inviteId).set({
        'institutionId': institutionId,
        'institutionName': institutionName,
        'inviteeUid': inviteeUserId,
        'inviteePhoneE164': normalizedPhone,
        'invitedName': invitedName,
        'invitedEmail': invitedEmail,
        'intendedRole': role.name,
        'status': UserInviteStatus.pending.name,
        'invitedBy': currentUser.uid,
        'oneTimeUse': true,
        'deliveryChannel': 'in_app',
        'expiresAt': Timestamp.fromDate(expiresAtUtc),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    final inviteRoute = role == UserRole.counselor
        ? Uri(
            path: AppRoute.inviteAccept,
            queryParameters: <String, String>{AppRoute.inviteIdQuery: inviteId},
          ).toString()
        : Uri(
            path: AppRoute.home,
            queryParameters: <String, String>{
              AppRoute.openJoinCodeQuery: '1',
              'joinCode': activeJoinCode,
            },
          ).toString();
    final waMessage = _buildWhatsAppInviteText(
      institutionName: institutionName,
      inviterName: inviterName,
      role: role,
      joinCode: activeJoinCode,
      expiresAtUtc: expiresAtUtc,
    );

    await _createNotifications([
      _notificationPayload(
        userId: inviteeUserId,
        institutionId: institutionId,
        type: 'institution_invite',
        title: 'Invitation to join $institutionName',
        body:
            'You were invited as ${role.label}. Open this alert and enter your institution code to accept.',
        relatedId: inviteId,
        priority: 'high',
        actionRequired: true,
        route: inviteRoute,
        isPinned: true,
      ),
    ]);

    await _appendMembershipAudit(
      institutionId: institutionId,
      actorUid: currentUser.uid,
      targetUserId: inviteeUserId,
      action: 'invite_created',
      details: <String, dynamic>{
        'inviteId': inviteId,
        'intendedRole': role.name,
        'inviteePhoneE164': normalizedPhone,
        'expiresAt': kUseWindowsRestAuth
            ? expiresAtUtc
            : Timestamp.fromDate(expiresAtUtc),
      },
    );

    return InAppInviteDraft(
      inviteId: inviteId,
      inviteeUid: inviteeUserId,
      inviteePhoneE164: normalizedPhone,
      invitedEmail: invitedEmail,
      invitedName: invitedName,
      institutionId: institutionId,
      institutionName: institutionName,
      role: role,
      expiresAtUtc: expiresAtUtc,
      joinCode: activeJoinCode,
      whatsAppMessage: waMessage,
      whatsAppDeepLink: _buildWhatsAppDeepLink(
        phoneE164: normalizedPhone,
        message: waMessage,
      ),
    );
  }

  Future<String?> counselorIntentNameByPhone(String inviteePhoneNumber) async {
    String normalized;
    try {
      normalized = _normalizePhoneE164(inviteePhoneNumber);
    } catch (_) {
      return null;
    }
    final phoneCandidates = _buildPhoneCandidates(primaryPhone: normalized);
    final Map<String, dynamic>? resolved;
    if (kUseWindowsRestAuth) {
      resolved = (await _findUserByPhoneCandidates(phoneCandidates))?.data;
    } else {
      final snapshot = await _firestore
          .collection('users')
          .where('phoneNumbers', arrayContainsAny: phoneCandidates)
          .limit(1)
          .get();
      resolved = snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
    }
    if (resolved == null) {
      return null;
    }
    final intent = (resolved['registrationIntent'] as String?)?.trim();
    if (intent != UserProfile.counselorRegistrationIntent) {
      return null;
    }
    final name = (resolved['name'] as String?)?.trim();
    return name?.isNotEmpty == true ? name! : 'This user';
  }

  Future<void> _assertInviteeNotAlreadyMember({
    required String targetInstitutionId,
    required String inviteeUid,
    required String inviteeInstitutionId,
  }) async {
    String? blockingInstitutionId;
    String? blockingRole;
    if (kUseWindowsRestAuth) {
      final existingMembership = await _windowsRest.queryCollection(
        collectionId: 'institution_members',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', inviteeUid),
          WindowsFirestoreFieldFilter.inList('status', const <String>[
            'active',
            'pending',
          ]),
        ],
        limit: 1,
      );
      if (existingMembership.isNotEmpty) {
        final data = existingMembership.first.data;
        blockingInstitutionId = (data['institutionId'] as String?) ?? '';
        blockingRole = (data['role'] as String?) ?? '';
      } else if (inviteeInstitutionId.isNotEmpty) {
        blockingInstitutionId = inviteeInstitutionId;
      }
    } else {
      final existingMembership = await _firestore
          .collection('institution_members')
          .where('userId', isEqualTo: inviteeUid)
          .where('status', whereIn: ['active', 'pending'])
          .limit(1)
          .get();
      if (existingMembership.docs.isNotEmpty) {
        final data = existingMembership.docs.first.data();
        blockingInstitutionId = (data['institutionId'] as String?) ?? '';
        blockingRole = (data['role'] as String?) ?? '';
      } else if (inviteeInstitutionId.isNotEmpty) {
        blockingInstitutionId = inviteeInstitutionId;
      }
    }
    if (blockingInstitutionId == null || blockingInstitutionId.isEmpty) {
      return;
    }

    // Resolve institution name for clearer error.
    String institutionName = blockingInstitutionId;
    try {
      final instData = kUseWindowsRestAuth
          ? (await _windowsRest.getDocument(
              'institutions/$blockingInstitutionId',
            ))?.data
          : (await _firestore
                    .collection('institutions')
                    .doc(blockingInstitutionId)
                    .get())
                .data();
      institutionName =
          (instData?['name'] as String?)?.trim().isNotEmpty == true
          ? (instData!['name'] as String)
          : institutionName;
    } catch (_) {
      // Keep fallback ID if lookup fails.
    }

    if (blockingInstitutionId == targetInstitutionId) {
      final roleLabel = _roleLabel(blockingRole);
      throw Exception(
        'This user is already in your institution${roleLabel != null ? ' as $roleLabel' : ''}.',
      );
    }

    throw Exception(
      'This user already belongs to $institutionName. Ask them to leave that institution before inviting.',
    );
  }

  String? _roleLabel(String? roleName) {
    if (roleName == null) return null;
    try {
      final roleEnum = UserRole.values.firstWhere(
        (r) => r.name == roleName,
        orElse: () => UserRole.other,
      );
      return roleEnum.label;
    } catch (_) {
      return null;
    }
  }

  Future<void> declineInvite(UserInvite invite) async {
    if (!invite.isPending) {
      throw Exception('Only pending invites can be declined.');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (currentUser.uid != invite.inviteeUid) {
      throw Exception('This invite is not linked to your account.');
    }
    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('user_invites/${invite.id}'))?.data
        : (await _firestore.collection('user_invites').doc(invite.id).get())
              .data();
    if (data == null ||
        (data['status'] as String?) != UserInviteStatus.pending.name) {
      throw Exception('Only pending invites can be declined.');
    }
    final inviteeUid = (data['inviteeUid'] as String?) ?? '';
    if (inviteeUid != currentUser.uid) {
      throw Exception('This invite is not linked to your account.');
    }
    final expiresAt = _asUtcDate(data['expiresAt']);
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw Exception('This invite has expired.');
    }
    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      final notifications = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', currentUser.uid),
          WindowsFirestoreFieldFilter.equal('type', 'institution_invite'),
          WindowsFirestoreFieldFilter.equal('relatedId', invite.id),
        ],
        limit: 20,
      );
      await _windowsRest.setDocument('user_invites/${invite.id}', {
        ...data,
        'status': UserInviteStatus.declined.name,
        'declinedAt': now,
        'declinedByUid': currentUser.uid,
        'updatedAt': now,
      });
      for (final notification in notifications) {
        await _windowsRest.setDocument('notifications/${notification.id}', {
          ...notification.data,
          'isRead': true,
          'readAt': now,
          'isPinned': false,
          'isArchived': true,
          'archivedAt': now,
          'resolvedAt': now,
          'updatedAt': now,
        });
      }
    } else {
      final inviteRef = _firestore.collection('user_invites').doc(invite.id);
      final notifications = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: currentUser.uid)
          .where('type', isEqualTo: 'institution_invite')
          .where('relatedId', isEqualTo: invite.id)
          .limit(20)
          .get();

      final batch = _firestore.batch();
      batch.update(inviteRef, {
        'status': UserInviteStatus.declined.name,
        'declinedAt': FieldValue.serverTimestamp(),
        'declinedByUid': currentUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final doc in notifications.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'isPinned': false,
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'resolvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _appendMembershipAudit(
      institutionId: invite.institutionId,
      actorUid: currentUser.uid,
      targetUserId: currentUser.uid,
      action: 'invite_declined',
      details: <String, dynamic>{'inviteId': invite.id},
    );
    await _createNotifications(
      _inviteDecisionNotificationPayloads(
        invite: invite,
        actorUid: currentUser.uid,
        actorDisplayName: _bestInviteActorName(
          fallbackName: invite.invitedName,
          fallbackEmail: currentUser.email,
        ),
        accepted: false,
      ),
    );
  }

  Future<void> acceptInvite({
    required UserInvite invite,
    required String institutionCode,
  }) async {
    if (!invite.isPending) {
      throw Exception('Only pending invites can be accepted.');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (currentUser.uid != invite.inviteeUid) {
      throw Exception('This invite is not linked to your account.');
    }
    final normalizedCode = institutionCode.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw Exception('Institution code is required.');
    }

    final nowUtc = DateTime.now().toUtc();
    if (kUseWindowsRestAuth) {
      final latestInviteData = (await _windowsRest.getDocument(
        'user_invites/${invite.id}',
      ))?.data;
      if (latestInviteData == null) {
        throw Exception('Invite was not found.');
      }
      final latestStatus = (latestInviteData['status'] as String?) ?? '';
      if (latestStatus != UserInviteStatus.pending.name) {
        throw Exception('Invite is no longer available.');
      }
      final inviteeUid = (latestInviteData['inviteeUid'] as String?) ?? '';
      if (inviteeUid != currentUser.uid) {
        throw Exception('This invite is not linked to your account.');
      }
      final intendedRoleRaw =
          (latestInviteData['intendedRole'] as String?) ?? UserRole.other.name;
      final intendedRole = UserRole.values.firstWhere(
        (value) => value.name == intendedRoleRaw,
        orElse: () => UserRole.other,
      );
      if (intendedRole != UserRole.student &&
          intendedRole != UserRole.staff &&
          intendedRole != UserRole.counselor) {
        throw Exception('Invite has unsupported role.');
      }
      final expiresAt = _asUtcDate(latestInviteData['expiresAt']);
      if (expiresAt != null && !expiresAt.isAfter(nowUtc)) {
        throw Exception('This invite has expired.');
      }

      final institutionData = (await _windowsRest.getDocument(
        'institutions/${invite.institutionId}',
      ))?.data;
      if (institutionData == null) {
        throw Exception('Institution not found.');
      }
      final institutionStatus =
          (institutionData['status'] as String?) ?? 'approved';
      if (institutionStatus != 'approved') {
        throw Exception('Institution is not approved for joins.');
      }
      final activeJoinCode = (institutionData['joinCode'] as String? ?? '')
          .trim()
          .toUpperCase();
      if (activeJoinCode != normalizedCode) {
        throw Exception('Invalid institution code.');
      }
      final usageCount =
          (institutionData['joinCodeUsageCount'] as num?)?.toInt() ?? 0;
      final expiresAtUtc = _asUtcDate(institutionData['joinCodeExpiresAt']);
      final isCodeExpired =
          expiresAtUtc == null || !expiresAtUtc.isAfter(nowUtc);
      if (isCodeExpired) {
        throw Exception('This institution code has expired.');
      }
      if (usageCount >= _joinCodeMaxUses) {
        throw Exception('This institution code reached its maximum usage.');
      }

      final userData = (await _windowsRest.getDocument(
        'users/${currentUser.uid}',
      ))?.data;
      if (userData == null) {
        throw Exception('User profile not found.');
      }
      final synchronizedOnboardingCompletedRoles =
          _synchronizedOnboardingCompletedRoles(
            userData: userData,
            targetRole: intendedRole,
          );
      final previousInstitutionId = userData['institutionId'] as String?;
      final memberStatus = intendedRole == UserRole.counselor
          ? 'pending'
          : 'active';
      final notifications = await _windowsRest.queryCollection(
        collectionId: 'notifications',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('userId', currentUser.uid),
          WindowsFirestoreFieldFilter.equal('type', 'institution_invite'),
          WindowsFirestoreFieldFilter.equal('relatedId', invite.id),
        ],
        limit: 20,
      );
      final updatedUserData = <String, dynamic>{
        ...userData,
        'institutionId': invite.institutionId,
        'institutionName':
            ((latestInviteData['institutionName'] as String?) ?? '')
                .trim()
                .isNotEmpty
            ? (latestInviteData['institutionName'] as String)
            : invite.institutionName,
        'role': intendedRole.name,
        'registrationIntent': null,
        if (intendedRole == UserRole.counselor) ...{
          'counselorSetupCompleted': false,
          'counselorSetupData': <String, dynamic>{},
          'counselorApprovalStatus': 'pending',
        },
        'updatedAt': nowUtc,
      };
      if (synchronizedOnboardingCompletedRoles != null) {
        updatedUserData['onboardingCompletedRoles'] =
            synchronizedOnboardingCompletedRoles;
      }

      final writes = <WindowsFirestoreWrite>[
        WindowsFirestoreWrite.set('users/${currentUser.uid}', updatedUserData),
        WindowsFirestoreWrite.set(
          'institution_members/${invite.institutionId}_${currentUser.uid}',
          {
            'institutionId': invite.institutionId,
            'userId': currentUser.uid,
            'role': intendedRole.name,
            'userName':
                (userData['name'] as String?) ??
                (latestInviteData['invitedName'] as String?) ??
                '',
            'email': (userData['email'] as String?) ?? '',
            'phoneNumber':
                (latestInviteData['inviteePhoneE164'] as String?) ?? '',
            'joinedAt': nowUtc,
            'status': memberStatus,
            'joinedVia': 'invite',
            'inviteId': invite.id,
            'updatedAt': nowUtc,
          },
        ),
        WindowsFirestoreWrite.set('institutions/${invite.institutionId}', {
          ...institutionData,
          'joinCodeUsageCount': usageCount + 1,
          'updatedAt': nowUtc,
        }),
        WindowsFirestoreWrite.set('user_invites/${invite.id}', {
          ...latestInviteData,
          'status': UserInviteStatus.accepted.name,
          'acceptedAt': nowUtc,
          'acceptedByUid': currentUser.uid,
          'acceptedWithCode': normalizedCode,
          'updatedAt': nowUtc,
        }),
        WindowsFirestoreWrite.set(
          'institution_membership_audit/${_windowsDocId('audit')}',
          {
            'institutionId': invite.institutionId,
            'actorUid': currentUser.uid,
            'targetUserId': currentUser.uid,
            'action': 'invite_accepted',
            'details': <String, dynamic>{
              'inviteId': invite.id,
              'intendedRole': intendedRole.name,
              'memberStatus': memberStatus,
              'codeVerified': true,
            },
            'createdAt': nowUtc,
          },
        ),
      ];
      for (final notification in notifications) {
        writes.add(
          WindowsFirestoreWrite.set('notifications/${notification.id}', {
            ...notification.data,
            'isRead': true,
            'readAt': nowUtc,
            'isPinned': false,
            'isArchived': true,
            'archivedAt': nowUtc,
            'resolvedAt': nowUtc,
            'updatedAt': nowUtc,
          }),
        );
      }
      if (previousInstitutionId != null &&
          previousInstitutionId.isNotEmpty &&
          previousInstitutionId != invite.institutionId) {
        writes.add(
          WindowsFirestoreWrite.delete(
            'institution_members/${previousInstitutionId}_${currentUser.uid}',
          ),
        );
      }
      await _windowsRest.commitWrites(writes);
      await _createNotifications(
        _inviteDecisionNotificationPayloads(
          invite: invite,
          actorUid: currentUser.uid,
          actorDisplayName: _bestInviteActorName(
            fallbackName: invite.invitedName,
            fallbackEmail: currentUser.email,
          ),
          accepted: true,
        ),
      );
      return;
    }

    final inviteRef = _firestore.collection('user_invites').doc(invite.id);
    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final institutionRef = _firestore
        .collection('institutions')
        .doc(invite.institutionId);
    final notificationSnapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: currentUser.uid)
        .where('type', isEqualTo: 'institution_invite')
        .where('relatedId', isEqualTo: invite.id)
        .limit(20)
        .get();
    final notificationRefs = notificationSnapshot.docs
        .map((doc) => doc.reference)
        .toList(growable: false);
    final auditRef = _firestore
        .collection('institution_membership_audit')
        .doc();

    await _firestore.runTransaction((transaction) async {
      final latestInviteSnapshot = await transaction.get(inviteRef);
      final latestInviteData = latestInviteSnapshot.data();
      if (latestInviteData == null) {
        throw Exception('Invite was not found.');
      }
      final latestStatus = (latestInviteData['status'] as String?) ?? '';
      if (latestStatus != UserInviteStatus.pending.name) {
        throw Exception('Invite is no longer available.');
      }
      final inviteeUid = (latestInviteData['inviteeUid'] as String?) ?? '';
      if (inviteeUid != currentUser.uid) {
        throw Exception('This invite is not linked to your account.');
      }
      final intendedRoleRaw =
          (latestInviteData['intendedRole'] as String?) ?? UserRole.other.name;
      final intendedRole = UserRole.values.firstWhere(
        (value) => value.name == intendedRoleRaw,
        orElse: () => UserRole.other,
      );
      if (intendedRole != UserRole.student &&
          intendedRole != UserRole.staff &&
          intendedRole != UserRole.counselor) {
        throw Exception('Invite has unsupported role.');
      }
      final expiresAt = _asUtcDate(latestInviteData['expiresAt']);
      if (expiresAt != null && !expiresAt.isAfter(nowUtc)) {
        throw Exception('This invite has expired.');
      }

      final institutionSnapshot = await transaction.get(institutionRef);
      final institutionData = institutionSnapshot.data();
      if (institutionData == null) {
        throw Exception('Institution not found.');
      }
      final institutionStatus =
          (institutionData['status'] as String?) ?? 'approved';
      if (institutionStatus != 'approved') {
        throw Exception('Institution is not approved for joins.');
      }
      final activeJoinCode = (institutionData['joinCode'] as String? ?? '')
          .trim()
          .toUpperCase();
      if (activeJoinCode != normalizedCode) {
        throw Exception('Invalid institution code.');
      }
      final usageCount =
          (institutionData['joinCodeUsageCount'] as num?)?.toInt() ?? 0;
      final expiresAtUtc = _asUtcDate(institutionData['joinCodeExpiresAt']);
      final isCodeExpired =
          expiresAtUtc == null || !expiresAtUtc.isAfter(nowUtc);
      if (isCodeExpired) {
        throw Exception('This institution code has expired.');
      }
      if (usageCount >= _joinCodeMaxUses) {
        throw Exception('This institution code reached its maximum usage.');
      }

      final userSnapshot = await transaction.get(userRef);
      if (!userSnapshot.exists || userSnapshot.data() == null) {
        throw Exception('User profile not found.');
      }
      final synchronizedOnboardingCompletedRoles =
          _synchronizedOnboardingCompletedRoles(
            userData: userSnapshot.data()!,
            targetRole: intendedRole,
          );
      final previousInstitutionId =
          userSnapshot.data()!['institutionId'] as String?;

      final memberStatus = intendedRole == UserRole.counselor
          ? 'pending'
          : 'active';
      final membershipRef = _firestore
          .collection('institution_members')
          .doc('${invite.institutionId}_${currentUser.uid}');
      final userUpdates = <String, dynamic>{
        'institutionId': invite.institutionId,
        'institutionName':
            ((latestInviteData['institutionName'] as String?) ?? '')
                .trim()
                .isNotEmpty
            ? (latestInviteData['institutionName'] as String)
            : invite.institutionName,
        'role': intendedRole.name,
        'registrationIntent': null,
        if (intendedRole == UserRole.counselor) ...{
          'counselorSetupCompleted': false,
          'counselorSetupData': <String, dynamic>{},
          'counselorApprovalStatus': 'pending',
        },
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (synchronizedOnboardingCompletedRoles != null) {
        userUpdates['onboardingCompletedRoles'] =
            synchronizedOnboardingCompletedRoles;
      }

      transaction.update(userRef, userUpdates);
      transaction.set(membershipRef, {
        'institutionId': invite.institutionId,
        'userId': currentUser.uid,
        'role': intendedRole.name,
        'userName':
            (userSnapshot.data()!['name'] as String?) ??
            (latestInviteData['invitedName'] as String?) ??
            '',
        'email': (userSnapshot.data()!['email'] as String?) ?? '',
        'phoneNumber': (latestInviteData['inviteePhoneE164'] as String?) ?? '',
        'joinedAt': FieldValue.serverTimestamp(),
        'status': memberStatus,
        'joinedVia': 'invite',
        'inviteId': invite.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(institutionRef, {
        'joinCodeUsageCount': usageCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(inviteRef, {
        'status': UserInviteStatus.accepted.name,
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedByUid': currentUser.uid,
        'acceptedWithCode': normalizedCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final notificationRef in notificationRefs) {
        transaction.update(notificationRef, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
          'isPinned': false,
          'isArchived': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'resolvedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(auditRef, {
        'institutionId': invite.institutionId,
        'actorUid': currentUser.uid,
        'targetUserId': currentUser.uid,
        'action': 'invite_accepted',
        'details': <String, dynamic>{
          'inviteId': invite.id,
          'intendedRole': intendedRole.name,
          'memberStatus': memberStatus,
          'codeVerified': true,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (previousInstitutionId != null &&
          previousInstitutionId.isNotEmpty &&
          previousInstitutionId != invite.institutionId) {
        final previousMembershipRef = _firestore
            .collection('institution_members')
            .doc('${previousInstitutionId}_${currentUser.uid}');
        transaction.delete(previousMembershipRef);
      }
    });
    await _createNotifications(
      _inviteDecisionNotificationPayloads(
        invite: invite,
        actorUid: currentUser.uid,
        actorDisplayName: _bestInviteActorName(
          fallbackName: invite.invitedName,
          fallbackEmail: currentUser.email,
        ),
        accepted: true,
      ),
    );
  }

  Future<void> revokeInvite({required String inviteId}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    final profile = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can revoke invites.');
    }
    final institutionId = (profile['institutionId'] as String?) ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('user_invites/$inviteId'))?.data
        : (await _firestore.collection('user_invites').doc(inviteId).get())
              .data();
    if (data == null) {
      throw Exception('Invite was not found.');
    }
    final inviteInstitutionId = (data['institutionId'] as String?) ?? '';
    if (inviteInstitutionId != institutionId) {
      throw Exception('You can revoke invites only in your institution.');
    }
    final status = (data['status'] as String?) ?? '';
    if (status != UserInviteStatus.pending.name) {
      throw Exception('Only pending invites can be revoked.');
    }
    final inviteeUid = (data['inviteeUid'] as String?) ?? '';
    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('user_invites/$inviteId', {
        ...data,
        'status': UserInviteStatus.revoked.name,
        'revokedAt': now,
        'revokedByUid': currentUser.uid,
        'updatedAt': now,
      });
    } else {
      final inviteRef = _firestore.collection('user_invites').doc(inviteId);
      await inviteRef.update({
        'status': UserInviteStatus.revoked.name,
        'revokedAt': FieldValue.serverTimestamp(),
        'revokedByUid': currentUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    if (inviteeUid.isNotEmpty) {
      await _createNotifications([
        _notificationPayload(
          userId: inviteeUid,
          institutionId: institutionId,
          type: 'institution_invite_revoked',
          title: 'Invite revoked',
          body:
              'An invitation for ${(data['intendedRole'] as String?) ?? 'a role'} was revoked by your admin.',
          relatedId: inviteId,
        ),
      ]);
    }
    await _appendMembershipAudit(
      institutionId: institutionId,
      actorUid: currentUser.uid,
      targetUserId: inviteeUid,
      action: 'invite_revoked',
      details: <String, dynamic>{'inviteId': inviteId},
    );
  }

  Future<void> updateMemberLifecycleStatus({
    required String memberUserId,
    required String status,
    String? reason,
  }) async {
    const allowed = <String>{'active', 'suspended', 'removed'};
    final normalizedStatus = status.trim().toLowerCase();
    final normalizedReason = _normalizedLifecycleReason(reason);
    if (!allowed.contains(normalizedStatus)) {
      throw Exception('Unsupported member status.');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    final profile = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can update member status.');
    }
    final institutionId = (profile['institutionId'] as String?) ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final membershipId = '${institutionId}_$memberUserId';
    final membership = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument(
            'institution_members/$membershipId',
          ))?.data
        : (await _firestore
                  .collection('institution_members')
                  .doc(membershipId)
                  .get())
              .data();
    if (membership == null) {
      throw Exception('Member record not found.');
    }
    final memberRole = (membership['role'] as String?) ?? '';
    final previousStatus = ((membership['status'] as String?) ?? 'active')
        .trim()
        .toLowerCase();
    if (memberRole == UserRole.institutionAdmin.name &&
        memberUserId == currentUser.uid) {
      throw Exception('You cannot change your own admin membership status.');
    }
    if (previousStatus == normalizedStatus) {
      return;
    }
    if (memberRole == UserRole.counselor.name &&
        previousStatus == 'removed' &&
        normalizedStatus != 'removed') {
      throw Exception(
        'Removed counselor access must be restored through a new invite.',
      );
    }

    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('institution_members/$membershipId', {
        ...membership,
        'status': normalizedStatus,
        'lifecycleReason': normalizedReason,
        'lifecycleUpdatedBy': currentUser.uid,
        'lifecycleUpdatedAt': now,
        'updatedAt': now,
      });
    } else {
      await _firestore
          .collection('institution_members')
          .doc(membershipId)
          .update({
            'status': normalizedStatus,
            'lifecycleReason': normalizedReason,
            'lifecycleUpdatedBy': currentUser.uid,
            'lifecycleUpdatedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
    }

    var cancelledAppointments = 0;
    if (memberRole == UserRole.counselor.name) {
      await _syncCounselorLifecycleState(
        institutionId: institutionId,
        counselorId: memberUserId,
        status: normalizedStatus,
      );
      if (normalizedStatus == 'suspended' || normalizedStatus == 'removed') {
        cancelledAppointments =
            await _cancelFutureCounselorAppointmentsForLifecycleChange(
              institutionId: institutionId,
              counselorId: memberUserId,
              counselorDisplayName: ((membership['userName'] as String?) ?? '')
                  .trim(),
              status: normalizedStatus,
            );
      }
      await _syncFutureCounselorAvailabilityForLifecycleStatus(
        institutionId: institutionId,
        counselorId: memberUserId,
        status: normalizedStatus,
      );
      await _createNotifications(
        _counselorLifecycleNotificationPayloads(
          userId: memberUserId,
          institutionId: institutionId,
          status: normalizedStatus,
          cancelledAppointments: cancelledAppointments,
          reason: normalizedReason,
        ),
      );
    }

    await _appendMembershipAudit(
      institutionId: institutionId,
      actorUid: currentUser.uid,
      targetUserId: memberUserId,
      action: 'member_status_changed',
      details: <String, dynamic>{
        'previousStatus': previousStatus,
        'nextStatus': normalizedStatus,
        'reason': normalizedReason,
        if (memberRole == UserRole.counselor.name)
          'cancelledAppointments': cancelledAppointments,
      },
    );
  }

  Future<void> joinInstitutionByCode({required String code}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      throw Exception('Join code is required.');
    }

    if (kUseWindowsRestAuth) {
      final institutions = await _windowsRest.queryCollection(
        collectionId: 'institutions',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('joinCode', normalizedCode),
        ],
        limit: 1,
      );

      if (institutions.isEmpty) {
        throw Exception('Invalid join code.');
      }

      final institutionDoc = institutions.first;
      final institutionData = institutionDoc.data;
      final institutionName =
          (institutionData['name'] as String?) ?? 'Institution';
      final rotatedCodeCandidate = await _generateUniqueJoinCode(
        excludeInstitutionId: institutionDoc.id,
      );
      final nowUtc = DateTime.now().toUtc();

      final institutionStatus =
          (institutionData['status'] as String?) ?? 'approved';
      if (institutionStatus != 'approved') {
        throw Exception(
          'This institution is not approved yet. Ask your institution admin for an approved join code.',
        );
      }

      final activeJoinCode = (institutionData['joinCode'] as String? ?? '')
          .trim()
          .toUpperCase();
      if (activeJoinCode != normalizedCode) {
        throw Exception('Invalid join code.');
      }

      final usageCount =
          (institutionData['joinCodeUsageCount'] as num?)?.toInt() ?? 0;
      final expiresAtUtc = _asUtcDate(institutionData['joinCodeExpiresAt']);
      final isExpired = expiresAtUtc == null || !expiresAtUtc.isAfter(nowUtc);
      final isUsageCapped = usageCount >= _joinCodeMaxUses;

      if (isExpired || isUsageCapped) {
        await _windowsRest
            .setDocument('institutions/${institutionDoc.id}', <String, dynamic>{
              ...institutionData,
              ..._buildJoinCodePayload(
                code: rotatedCodeCandidate,
                nowUtc: nowUtc,
                usageCount: 0,
              ),
            });
        if (isExpired) {
          throw Exception(
            'This join code expired and has been regenerated. Ask your institution admin for the latest code.',
          );
        }
        throw Exception(
          'This join code reached its 50-user limit and has been regenerated. Ask your institution admin for the latest code.',
        );
      }

      final userData = (await _windowsRest.getDocument(
        'users/${currentUser.uid}',
      ))?.data;
      if (userData == null) {
        throw Exception('User profile not found.');
      }
      final previousInstitutionId = userData['institutionId'] as String?;

      final pendingInvites = await _windowsRest.queryCollection(
        collectionId: 'user_invites',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('inviteeUid', currentUser.uid),
          WindowsFirestoreFieldFilter.equal('institutionId', institutionDoc.id),
          WindowsFirestoreFieldFilter.equal(
            'status',
            UserInviteStatus.pending.name,
          ),
        ],
      );
      final writes = <WindowsFirestoreWrite>[
        WindowsFirestoreWrite.set('users/${currentUser.uid}', {
          ...userData,
          'institutionId': institutionDoc.id,
          'institutionName': institutionName,
          'role': UserRole.student.name,
          'registrationIntent': null,
          'updatedAt': nowUtc,
        }),
        WindowsFirestoreWrite.set(
          'institution_members/${institutionDoc.id}_${currentUser.uid}',
          {
            'institutionId': institutionDoc.id,
            'userId': currentUser.uid,
            'role': UserRole.student.name,
            'userName': currentUser.displayName,
            'email': currentUser.email,
            'joinedAt': nowUtc,
            'status': 'active',
            'joinedVia': 'code',
            'joinedCode': normalizedCode,
            'updatedAt': nowUtc,
          },
        ),
        WindowsFirestoreWrite.set('institutions/${institutionDoc.id}', {
          ...institutionData,
          'joinCodeUsageCount': usageCount + 1,
          'updatedAt': nowUtc,
        }),
      ];
      if (previousInstitutionId != null &&
          previousInstitutionId.isNotEmpty &&
          previousInstitutionId != institutionDoc.id) {
        writes.add(
          WindowsFirestoreWrite.delete(
            'institution_members/${previousInstitutionId}_${currentUser.uid}',
          ),
        );
      }
      if (pendingInvites.isNotEmpty) {
        final inviteIds = <String>[];
        for (final inviteDoc in pendingInvites) {
          inviteIds.add(inviteDoc.id);
          writes.add(
            WindowsFirestoreWrite.set('user_invites/${inviteDoc.id}', {
              ...inviteDoc.data,
              'status': UserInviteStatus.accepted.name,
              'updatedAt': nowUtc,
            }),
          );
        }
        for (var i = 0; i < inviteIds.length; i += 10) {
          final chunk = inviteIds.sublist(
            i,
            i + 10 > inviteIds.length ? inviteIds.length : i + 10,
          );
          final notifications = await _windowsRest.queryCollection(
            collectionId: 'notifications',
            filters: <WindowsFirestoreFieldFilter>[
              WindowsFirestoreFieldFilter.equal('userId', currentUser.uid),
              WindowsFirestoreFieldFilter.inList('relatedId', chunk),
            ],
          );
          for (final notification in notifications) {
            writes.add(
              WindowsFirestoreWrite.set('notifications/${notification.id}', {
                ...notification.data,
                'actionRequired': false,
                'updatedAt': nowUtc,
              }),
            );
          }
        }
      }
      await _windowsRest.commitWrites(writes);

      await _appendMembershipAudit(
        institutionId: institutionDoc.id,
        actorUid: currentUser.uid,
        targetUserId: currentUser.uid,
        action: 'joined_by_code',
        details: const <String, dynamic>{'role': 'student'},
      );
      return;
    }

    final institutionsSnapshot = await _firestore
        .collection('institutions')
        .where('joinCode', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (institutionsSnapshot.docs.isEmpty) {
      throw Exception('Invalid join code.');
    }

    final institutionDoc = institutionsSnapshot.docs.first;
    final institutionData = institutionDoc.data();
    final institutionName =
        (institutionData['name'] as String?) ?? 'Institution';
    final rotatedCodeCandidate = await _generateUniqueJoinCode(
      excludeInstitutionId: institutionDoc.id,
    );

    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final membershipRef = _firestore
        .collection('institution_members')
        .doc('${institutionDoc.id}_${currentUser.uid}');

    final nowUtc = DateTime.now().toUtc();
    try {
      await _firestore.runTransaction((transaction) async {
        final institutionSnapshot = await transaction.get(
          institutionDoc.reference,
        );
        final data = institutionSnapshot.data();
        if (data == null) {
          throw const _JoinCodeFlowException('Invalid join code.');
        }
        final institutionStatus = (data['status'] as String?) ?? 'approved';
        if (institutionStatus != 'approved') {
          throw const _JoinCodeFlowException(
            'This institution is not approved yet. Ask your institution admin for an approved join code.',
          );
        }

        final activeJoinCode = (data['joinCode'] as String? ?? '')
            .trim()
            .toUpperCase();
        if (activeJoinCode != normalizedCode) {
          throw const _JoinCodeFlowException('Invalid join code.');
        }

        final usageCount = (data['joinCodeUsageCount'] as num?)?.toInt() ?? 0;
        final expiresAtUtc = _asUtcDate(data['joinCodeExpiresAt']);
        final isExpired = expiresAtUtc == null || !expiresAtUtc.isAfter(nowUtc);
        final isUsageCapped = usageCount >= _joinCodeMaxUses;

        if (isExpired || isUsageCapped) {
          transaction.update(
            institutionDoc.reference,
            _buildJoinCodePayload(
              code: rotatedCodeCandidate,
              nowUtc: nowUtc,
              usageCount: 0,
            ),
          );

          if (isExpired) {
            throw const _JoinCodeFlowException(
              'This join code expired and has been regenerated. Ask your institution admin for the latest code.',
            );
          }
          throw const _JoinCodeFlowException(
            'This join code reached its 50-user limit and has been regenerated. Ask your institution admin for the latest code.',
          );
        }

        final userSnapshot = await transaction.get(userRef);
        final previousInstitutionId =
            userSnapshot.data()?['institutionId'] as String?;

        transaction.update(userRef, {
          'institutionId': institutionDoc.id,
          'institutionName': institutionName,
          'role': UserRole.student.name,
          'registrationIntent': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(membershipRef, {
          'institutionId': institutionDoc.id,
          'userId': currentUser.uid,
          'role': UserRole.student.name,
          'userName': currentUser.displayName ?? '',
          'email': currentUser.email,
          'joinedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'joinedVia': 'code',
          'joinedCode': normalizedCode,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(institutionDoc.reference, {
          'joinCodeUsageCount': usageCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (previousInstitutionId != null &&
            previousInstitutionId.isNotEmpty &&
            previousInstitutionId != institutionDoc.id) {
          final previousMembershipRef = _firestore
              .collection('institution_members')
              .doc('${previousInstitutionId}_${currentUser.uid}');
          transaction.delete(previousMembershipRef);
        }
      });
    } on _JoinCodeFlowException catch (error) {
      throw Exception(error.message);
    }

    // Mark any pending invites for this institution as accepted now that the
    // user joined via code, and relax action-required notifications.
    final pendingInvitesSnapshot = await _firestore
        .collection('user_invites')
        .where('inviteeUid', isEqualTo: currentUser.uid)
        .where('institutionId', isEqualTo: institutionDoc.id)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .get();
    if (pendingInvitesSnapshot.docs.isNotEmpty) {
      final batch = _firestore.batch();
      final inviteIds = <String>[];
      for (final doc in pendingInvitesSnapshot.docs) {
        inviteIds.add(doc.id);
        batch.update(doc.reference, {
          'status': UserInviteStatus.accepted.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      // Best-effort notification soft-close.
      final chunks = <List<String>>[];
      for (var i = 0; i < inviteIds.length; i += 10) {
        chunks.add(
          inviteIds.sublist(
            i,
            i + 10 > inviteIds.length ? inviteIds.length : i + 10,
          ),
        );
      }
      for (final chunk in chunks) {
        final notifications = await _firestore
            .collection('notifications')
            .where('userId', isEqualTo: currentUser.uid)
            .where('relatedId', whereIn: chunk)
            .get();
        if (notifications.docs.isEmpty) continue;
        final nBatch = _firestore.batch();
        for (final doc in notifications.docs) {
          nBatch.update(doc.reference, {
            'actionRequired': false,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await nBatch.commit();
      }
    }

    await _appendMembershipAudit(
      institutionId: institutionDoc.id,
      actorUid: currentUser.uid,
      targetUserId: currentUser.uid,
      action: 'joined_by_code',
      details: const <String, dynamic>{'role': 'student'},
    );
  }

  Future<void> regenerateJoinCodeForCurrentAdminInstitution() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final profile = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can regenerate join codes.');
    }

    final institutionId = profile['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }
    final institutionData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('institutions/$institutionId'))?.data
        : (await _firestore.collection('institutions').doc(institutionId).get())
              .data();
    final status = (institutionData?['status'] as String?) ?? 'approved';
    if (status != 'approved') {
      throw Exception('Join code is available only after approval.');
    }

    final nextJoinCode = await _generateUniqueJoinCode(
      excludeInstitutionId: institutionId,
    );
    final payload = _buildJoinCodePayload(
      code: nextJoinCode,
      nowUtc: DateTime.now().toUtc(),
      usageCount: 0,
    );
    if (kUseWindowsRestAuth) {
      await _windowsRest.setDocument('institutions/$institutionId', {
        ...institutionData!,
        ...payload,
      });
    } else {
      await _firestore
          .collection('institutions')
          .doc(institutionId)
          .update(payload);
    }
  }

  Stream<Map<String, dynamic>?> watchCurrentAdminInstitution() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream<Map<String, dynamic>?>.empty();
    }

    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<Map<String, dynamic>?>(
        load: getCurrentAdminInstitution,
        signature: (data) => data == null ? 'null' : data.toString(),
      );
    }

    return _firestore
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .asyncExpand((userDoc) {
          final institutionId = userDoc.data()?['institutionId'] as String?;
          if (institutionId == null || institutionId.isEmpty) {
            return Stream<Map<String, dynamic>?>.value(null);
          }
          return _firestore
              .collection('institutions')
              .doc(institutionId)
              .snapshots()
              .map((institutionDoc) {
                final data = institutionDoc.data();
                if (data == null) {
                  return null;
                }
                return <String, dynamic>{'id': institutionDoc.id, ...data};
              });
        });
  }

  Future<Map<String, dynamic>?> getCurrentAdminInstitution() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final userDoc = await _windowsRest.getDocument(
        'users/${currentUser.uid}',
      );
      final institutionId = userDoc?.data['institutionId'] as String?;
      if (institutionId == null || institutionId.isEmpty) {
        return null;
      }
      final institutionDoc = await _windowsRest.getDocument(
        'institutions/$institutionId',
      );
      if (institutionDoc == null) {
        return null;
      }
      return <String, dynamic>{'id': institutionDoc.id, ...institutionDoc.data};
    }

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final institutionId = userDoc.data()?['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      return null;
    }

    final institutionDoc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .get();
    final data = institutionDoc.data();
    if (data == null) {
      return null;
    }
    return <String, dynamic>{'id': institutionDoc.id, ...data};
  }

  Future<Map<String, dynamic>?> getInstitutionDocument(
    String institutionId,
  ) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    if (kUseWindowsRestAuth) {
      final document = await _windowsRest.getDocument(
        'institutions/$normalized',
      );
      if (document == null) {
        return null;
      }
      return <String, dynamic>{'id': document.id, ...document.data};
    }

    final doc = await _firestore
        .collection('institutions')
        .doc(normalized)
        .get();
    final data = doc.data();
    if (data == null) {
      return null;
    }
    return <String, dynamic>{'id': doc.id, ...data};
  }

  Future<void> updateCounselorWorkflowSettings({
    required CounselorWorkflowSettings settings,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final userData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    final institutionId = userData?['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Institution not found for this admin account.');
    }

    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'institutions/$institutionId',
      );
      if (existing == null) {
        throw Exception('Institution not found for this admin account.');
      }
      await _windowsRest.setDocument('institutions/$institutionId', {
        ...existing.data,
        ...settings.toInstitutionPatch(),
        'updatedAt': DateTime.now().toUtc(),
      });
    } else {
      await _firestore.collection('institutions').doc(institutionId).update({
        ...settings.toInstitutionPatch(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Stream<List<Map<String, dynamic>>> watchOwnerPendingInstitutions() {
    _ensureOwnerAccount();
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<Map<String, dynamic>>>(
        load: getOwnerPendingInstitutions,
        signature: (items) => items
            .map(
              (item) => '${item['id']}|${item['status']}|${item['updatedAt']}',
            )
            .join(';'),
      );
    }
    return _firestore
        .collection('institutions')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .toList(growable: false);
          items.sort((a, b) {
            final aDate =
                _asUtcDate(a['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                _asUtcDate(b['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return items;
        });
  }

  Stream<List<Map<String, dynamic>>> watchOwnerSchoolRequests() {
    _ensureOwnerAccount();
    if (_useWindowsPollingWorkaround) {
      return _buildWindowsPollingStream<List<Map<String, dynamic>>>(
        load: getOwnerSchoolRequests,
        signature: (items) => items
            .map(
              (item) => '${item['id']}|${item['status']}|${item['updatedAt']}',
            )
            .join(';'),
      );
    }
    return _firestore
        .collection('school_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .toList(growable: false);
          items.sort((a, b) {
            final aDate =
                _asUtcDate(a['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            final bDate =
                _asUtcDate(b['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0);
            return bDate.compareTo(aDate);
          });
          return items;
        });
  }

  Future<void> submitSchoolRequest({
    required String schoolName,
    String? mobileNumber,
    String? requesterName,
    String? requesterEmail,
  }) async {
    final normalizedSchoolName = schoolName.trim();
    final normalizedMobile = (mobileNumber ?? '').trim();
    if (normalizedSchoolName.length < 2) {
      throw Exception('School name is required.');
    }

    final currentUser = _auth.currentUser;
    String notificationInstitutionId = '';
    if (currentUser != null) {
      try {
        final requesterData = kUseWindowsRestAuth
            ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
            : (await _firestore.collection('users').doc(currentUser.uid).get())
                  .data();
        notificationInstitutionId =
            (requesterData?['institutionId'] as String?) ?? '';
      } catch (_) {
        notificationInstitutionId = '';
      }
    }
    final requestId = kUseWindowsRestAuth
        ? _windowsDocId('school_request')
        : _firestore.collection('school_requests').doc().id;
    final schoolRequestPayload = <String, dynamic>{
      'schoolName': normalizedSchoolName,
      if (normalizedMobile.isNotEmpty) 'mobileNumber': normalizedMobile,
      'requesterUid': currentUser?.uid,
      'requesterName': (requesterName ?? currentUser?.displayName ?? '').trim(),
      'requesterEmail': (requesterEmail ?? currentUser?.email ?? '')
          .trim()
          .toLowerCase(),
      'status': 'pending',
      'ownerEmail': kOwnerEmail,
      'createdAt': kUseWindowsRestAuth
          ? DateTime.now().toUtc()
          : FieldValue.serverTimestamp(),
      'updatedAt': kUseWindowsRestAuth
          ? DateTime.now().toUtc()
          : FieldValue.serverTimestamp(),
    };
    if (kUseWindowsRestAuth) {
      await _windowsRest.setDocument(
        'school_requests/$requestId',
        schoolRequestPayload,
        allowUnauthenticated: currentUser == null,
      );
    } else {
      await _firestore
          .collection('school_requests')
          .doc(requestId)
          .set(schoolRequestPayload);
    }

    final ownerUserId = await _resolveOwnerUserId();
    if (ownerUserId != null &&
        currentUser != null &&
        notificationInstitutionId.isNotEmpty) {
      await _createNotifications([
        _notificationPayload(
          userId: ownerUserId,
          institutionId: notificationInstitutionId,
          type: 'school_request_submitted',
          title: 'School not listed request',
          body: '$normalizedSchoolName was requested for onboarding.',
          relatedId: requestId,
        ),
      ]);
    }
  }

  Future<List<Map<String, dynamic>>> getOwnerPendingInstitutions() async {
    _ensureOwnerAccount();
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'institutions',
        filters: const <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('status', 'pending'),
        ],
      );
      final items = documents
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data})
          .toList(growable: false);
      items.sort((a, b) {
        final aDate =
            _asUtcDate(a['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            _asUtcDate(b['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return items;
    }
    final snapshot = await _firestore
        .collection('institutions')
        .where('status', isEqualTo: 'pending')
        .get();
    return _sortDocumentsByCreatedAt(snapshot.docs);
  }

  Future<List<Map<String, dynamic>>> getOwnerSchoolRequests() async {
    _ensureOwnerAccount();
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'school_requests',
        filters: const <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('status', 'pending'),
        ],
      );
      final items = documents
          .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data})
          .toList(growable: false);
      items.sort((a, b) {
        final aDate =
            _asUtcDate(a['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate =
            _asUtcDate(b['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
      return items;
    }
    final snapshot = await _firestore
        .collection('school_requests')
        .where('status', isEqualTo: 'pending')
        .get();
    return _sortDocumentsByCreatedAt(snapshot.docs);
  }

  Future<void> dismissInstitutionWelcome() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'users/${currentUser.uid}',
      );
      if (existing == null) {
        throw Exception('User profile not found.');
      }
      await _windowsRest.setDocument('users/${currentUser.uid}', {
        ...existing.data,
        'institutionWelcomePending': false,
        'updatedAt': DateTime.now().toUtc(),
      });
    } else {
      await _firestore.collection('users').doc(currentUser.uid).update({
        'institutionWelcomePending': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> approveInstitutionRequest({
    required String institutionId,
  }) async {
    _ensureOwnerAccount();
    final owner = _auth.currentUser;
    if (owner == null) {
      throw Exception('You must be logged in.');
    }

    final nextJoinCode = await _generateUniqueJoinCode(
      excludeInstitutionId: institutionId,
    );

    String? createdBy;
    if (kUseWindowsRestAuth) {
      final snapshot = await _windowsRest.getDocument(
        'institutions/$institutionId',
      );
      final data = snapshot?.data;
      if (data == null) {
        throw Exception('Institution request not found.');
      }
      final status = (data['status'] as String?) ?? 'pending';
      if (status == 'approved') {
        throw Exception('Institution is already approved.');
      }
      final institutionName = ((data['name'] as String?) ?? '').trim();
      final institutionCatalogId =
          ((data['institutionCatalogId'] as String?) ?? '').trim();
      final normalizedName = _normalizeInstitutionName(
        ((data['nameNormalized'] as String?) ?? institutionName).trim(),
      );
      createdBy = data['createdBy'] as String?;
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('institutions/$institutionId', {
        ...data,
        'status': 'approved',
        'nameNormalized': normalizedName,
        'approvedAt': now,
        'review': <String, dynamic>{
          'reviewedBy': owner.uid,
          'reviewedAt': now,
          'decision': 'approved',
          'declineReason': null,
        },
        ..._buildJoinCodePayload(
          code: nextJoinCode,
          nowUtc: now,
          usageCount: 0,
        ),
      });
      if (institutionCatalogId.isNotEmpty) {
        final registryPath = _institutionCatalogRegistryPath(
          institutionCatalogId,
        );
        await _windowsRest.setDocument(registryPath, {
          ...(await _windowsRest.getDocument(registryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionCatalogId': institutionCatalogId,
          'institutionName': institutionName,
          'status': 'approved',
          'updatedAt': now,
        });
      }
      if (normalizedName.isNotEmpty) {
        final registryPath = _institutionNameRegistryPath(normalizedName);
        await _windowsRest.setDocument(registryPath, {
          ...(await _windowsRest.getDocument(registryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionName': institutionName,
          'normalizedName': normalizedName,
          'status': 'approved',
          'updatedAt': now,
        });
      }
    } else {
      final institutionRef = _firestore
          .collection('institutions')
          .doc(institutionId);
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(institutionRef);
        final data = snapshot.data();
        if (data == null) {
          throw Exception('Institution request not found.');
        }
        final status = (data['status'] as String?) ?? 'pending';
        if (status == 'approved') {
          throw Exception('Institution is already approved.');
        }
        final institutionName = ((data['name'] as String?) ?? '').trim();
        final institutionCatalogId =
            ((data['institutionCatalogId'] as String?) ?? '').trim();
        final normalizedName = _normalizeInstitutionName(
          ((data['nameNormalized'] as String?) ?? institutionName).trim(),
        );
        createdBy = data['createdBy'] as String?;
        transaction.update(institutionRef, {
          'status': 'approved',
          'nameNormalized': normalizedName,
          'approvedAt': FieldValue.serverTimestamp(),
          'review': <String, dynamic>{
            'reviewedBy': owner.uid,
            'reviewedAt': FieldValue.serverTimestamp(),
            'decision': 'approved',
            'declineReason': null,
          },
          ..._buildJoinCodePayload(
            code: nextJoinCode,
            nowUtc: DateTime.now().toUtc(),
            usageCount: 0,
          ),
        });
        if (institutionCatalogId.isNotEmpty) {
          transaction.set(
            _institutionCatalogRegistryRef(institutionCatalogId),
            {
              'institutionId': institutionId,
              'institutionCatalogId': institutionCatalogId,
              'institutionName': institutionName,
              'status': 'approved',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
        if (normalizedName.isNotEmpty) {
          transaction.set(_institutionNameRegistryRef(normalizedName), {
            'institutionId': institutionId,
            'institutionName': institutionName,
            'normalizedName': normalizedName,
            'status': 'approved',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      });
    }

    if (createdBy != null && createdBy!.isNotEmpty) {
      await _createNotifications([
        _notificationPayload(
          userId: createdBy!,
          institutionId: institutionId,
          type: 'institution_request_approved',
          title: 'Institution approved',
          body:
              'Your institution request was approved. You can now use the admin dashboard.',
        ),
      ]);
    }
  }

  Future<void> declineInstitutionRequest({
    required String institutionId,
    required String declineReason,
  }) async {
    _ensureOwnerAccount();
    final owner = _auth.currentUser;
    if (owner == null) {
      throw Exception('You must be logged in.');
    }
    final reason = declineReason.trim();
    if (reason.length < 3) {
      throw Exception('Decline reason is required.');
    }

    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('institutions/$institutionId'))?.data
        : (await _firestore.collection('institutions').doc(institutionId).get())
              .data();
    if (data == null) {
      throw Exception('Institution request not found.');
    }
    final createdBy = data['createdBy'] as String?;
    final institutionName = ((data['name'] as String?) ?? '').trim();
    final institutionCatalogId =
        ((data['institutionCatalogId'] as String?) ?? '').trim();
    final normalizedName = _normalizeInstitutionName(
      ((data['nameNormalized'] as String?) ?? institutionName).trim(),
    );

    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('institutions/$institutionId', {
        ...data,
        'status': 'declined',
        'nameNormalized': normalizedName,
        'updatedAt': now,
        'review': <String, dynamic>{
          'reviewedBy': owner.uid,
          'reviewedAt': now,
          'decision': 'declined',
          'declineReason': reason,
        },
      });
      if (institutionCatalogId.isNotEmpty) {
        final registryPath = _institutionCatalogRegistryPath(
          institutionCatalogId,
        );
        await _windowsRest.setDocument(registryPath, {
          ...(await _windowsRest.getDocument(registryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionCatalogId': institutionCatalogId,
          'institutionName': institutionName,
          'status': 'declined',
          'updatedAt': now,
        });
      }
      if (normalizedName.isNotEmpty) {
        final registryPath = _institutionNameRegistryPath(normalizedName);
        await _windowsRest.setDocument(registryPath, {
          ...(await _windowsRest.getDocument(registryPath))?.data ??
              const <String, dynamic>{},
          'institutionId': institutionId,
          'institutionName': institutionName,
          'normalizedName': normalizedName,
          'status': 'declined',
          'updatedAt': now,
        });
      }
    } else {
      final institutionRef = _firestore
          .collection('institutions')
          .doc(institutionId);
      await institutionRef.update({
        'status': 'declined',
        'nameNormalized': normalizedName,
        'updatedAt': FieldValue.serverTimestamp(),
        'review': <String, dynamic>{
          'reviewedBy': owner.uid,
          'reviewedAt': FieldValue.serverTimestamp(),
          'decision': 'declined',
          'declineReason': reason,
        },
      });
      if (institutionCatalogId.isNotEmpty) {
        await _institutionCatalogRegistryRef(institutionCatalogId).set({
          'institutionId': institutionId,
          'institutionCatalogId': institutionCatalogId,
          'institutionName': institutionName,
          'status': 'declined',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (normalizedName.isNotEmpty) {
        await _institutionNameRegistryRef(normalizedName).set({
          'institutionId': institutionId,
          'institutionName': institutionName,
          'normalizedName': normalizedName,
          'status': 'declined',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    if (createdBy != null && createdBy.isNotEmpty) {
      await _createNotifications([
        _notificationPayload(
          userId: createdBy,
          institutionId: institutionId,
          type: 'institution_request_declined',
          title: 'Institution declined',
          body:
              'Your request was declined: $reason. You can edit and resubmit.',
        ),
      ]);
    }
  }

  Future<void> resubmitCurrentAdminInstitutionRequest({
    required String institutionCatalogId,
    required String institutionName,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final profile = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can resubmit requests.');
    }

    final institutionId = profile['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final data = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('institutions/$institutionId'))?.data
        : (await _firestore.collection('institutions').doc(institutionId).get())
              .data();
    if (data == null) {
      throw Exception('Institution request not found.');
    }
    final currentStatus = (data['status'] as String?) ?? 'pending';
    if (currentStatus == 'approved') {
      throw Exception('Institution is already approved.');
    }

    final trimmedInstitutionCatalogId = institutionCatalogId.trim();
    final trimmedInstitutionName = institutionName.trim();
    if (trimmedInstitutionCatalogId.isEmpty ||
        trimmedInstitutionName.length < 2) {
      throw Exception('Select a valid institution name.');
    }
    final normalizedNameKey = _normalizeInstitutionName(trimmedInstitutionName);
    await _assertInstitutionCatalogIdAvailable(
      trimmedInstitutionCatalogId,
      excludeInstitutionId: institutionId,
    );

    if (kUseWindowsRestAuth) {
      final currentCatalogId = ((data['institutionCatalogId'] as String?) ?? '')
          .trim();
      final nextCatalogRegistryPath = _institutionCatalogRegistryPath(
        trimmedInstitutionCatalogId,
      );
      if (currentCatalogId != trimmedInstitutionCatalogId) {
        final conflict = await _windowsRest.getDocument(
          nextCatalogRegistryPath,
        );
        if (conflict != null) {
          final claimedInstitutionId =
              (conflict.data['institutionId'] as String?) ?? '';
          if (claimedInstitutionId != institutionId) {
            throw Exception(
              'This institution already exists or is pending approval.',
            );
          }
        }
        if (currentCatalogId.isNotEmpty) {
          await _windowsRest.deleteDocument(
            _institutionCatalogRegistryPath(currentCatalogId),
          );
        }
      }

      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('institutions/$institutionId', {
        ...data,
        'name': trimmedInstitutionName,
        'nameNormalized': normalizedNameKey,
        'institutionCatalogId': trimmedInstitutionCatalogId,
        'status': 'pending',
        'updatedAt': now,
        'review': const <String, dynamic>{
          'reviewedBy': null,
          'reviewedAt': null,
          'decision': null,
          'declineReason': null,
        },
      });
      final existingUser = await _windowsRest.getDocument(
        'users/${currentUser.uid}',
      );
      if (existingUser != null) {
        await _windowsRest.setDocument('users/${currentUser.uid}', {
          ...existingUser.data,
          'institutionName': trimmedInstitutionName,
          'institutionCatalogId': trimmedInstitutionCatalogId,
          'updatedAt': now,
        });
      }
      await _windowsRest.setDocument(nextCatalogRegistryPath, {
        ...(await _windowsRest.getDocument(nextCatalogRegistryPath))?.data ??
            const <String, dynamic>{},
        'institutionId': institutionId,
        'institutionCatalogId': trimmedInstitutionCatalogId,
        'institutionName': trimmedInstitutionName,
        'status': 'pending',
        'updatedAt': now,
      });
      final nameRegistryPath = _institutionNameRegistryPath(normalizedNameKey);
      await _windowsRest.setDocument(nameRegistryPath, {
        ...(await _windowsRest.getDocument(nameRegistryPath))?.data ??
            const <String, dynamic>{},
        'institutionId': institutionId,
        'institutionName': trimmedInstitutionName,
        'normalizedName': normalizedNameKey,
        'status': 'pending',
        'updatedAt': now,
      });
    } else {
      final institutionRef = _firestore
          .collection('institutions')
          .doc(institutionId);
      final userRef = _firestore.collection('users').doc(currentUser.uid);
      try {
        await _firestore.runTransaction((transaction) async {
          final snapshot = await transaction.get(institutionRef);
          final data = snapshot.data();
          if (data == null) {
            throw Exception('Institution request not found.');
          }
          final currentStatus = (data['status'] as String?) ?? 'pending';
          if (currentStatus == 'approved') {
            throw Exception('Institution is already approved.');
          }

          final currentCatalogId =
              ((data['institutionCatalogId'] as String?) ?? '').trim();
          final currentCatalogRegistryRef = currentCatalogId.isEmpty
              ? null
              : _institutionCatalogRegistryRef(currentCatalogId);
          final nextCatalogRegistryRef = _institutionCatalogRegistryRef(
            trimmedInstitutionCatalogId,
          );

          if (currentCatalogId != trimmedInstitutionCatalogId) {
            final conflict = await transaction.get(nextCatalogRegistryRef);
            if (conflict.exists) {
              final claimedInstitutionId =
                  (conflict.data()?['institutionId'] as String?) ?? '';
              if (claimedInstitutionId != institutionId) {
                throw const _InstitutionDuplicationException(
                  'This institution already exists or is pending approval.',
                );
              }
            }
            if (currentCatalogRegistryRef != null) {
              final currentRegistrySnapshot = await transaction.get(
                currentCatalogRegistryRef,
              );
              if (currentRegistrySnapshot.exists) {
                transaction.delete(currentCatalogRegistryRef);
              }
            }
          }

          transaction.update(institutionRef, {
            'name': trimmedInstitutionName,
            'nameNormalized': normalizedNameKey,
            'institutionCatalogId': trimmedInstitutionCatalogId,
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
            'review': const <String, dynamic>{
              'reviewedBy': null,
              'reviewedAt': null,
              'decision': null,
              'declineReason': null,
            },
          });
          transaction.update(userRef, {
            'institutionName': trimmedInstitutionName,
            'institutionCatalogId': trimmedInstitutionCatalogId,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          transaction.set(nextCatalogRegistryRef, {
            'institutionId': institutionId,
            'institutionCatalogId': trimmedInstitutionCatalogId,
            'institutionName': trimmedInstitutionName,
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          transaction.set(
            _institutionNameRegistryRef(normalizedNameKey),
            {
              'institutionId': institutionId,
              'institutionName': trimmedInstitutionName,
              'normalizedName': normalizedNameKey,
              'status': 'pending',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });
      } on _InstitutionDuplicationException {
        throw Exception(
          'This institution already exists or is pending approval.',
        );
      }
    }

    final ownerUserId = await _resolveOwnerUserId();
    if (ownerUserId != null) {
      await _createNotifications([
        _notificationPayload(
          userId: ownerUserId,
          institutionId: institutionId,
          type: 'institution_request_resubmitted',
          title: 'Institution request resubmitted',
          body: '$trimmedInstitutionName was resubmitted for approval.',
        ),
      ]);
    }
  }

  Future<void> resolveSchoolRequest({
    required String requestId,
    required bool approved,
    String? note,
  }) async {
    _ensureOwnerAccount();
    final owner = _auth.currentUser;
    if (owner == null) {
      throw Exception('You must be logged in.');
    }
    if (kUseWindowsRestAuth) {
      final existing = await _windowsRest.getDocument(
        'school_requests/$requestId',
      );
      if (existing == null) {
        throw Exception('School request not found.');
      }
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('school_requests/$requestId', {
        ...existing.data,
        'status': approved ? 'approved' : 'declined',
        'note': (note ?? '').trim(),
        'reviewedBy': owner.uid,
        'reviewedAt': now,
        'updatedAt': now,
      });
      return;
    }
    await _firestore.collection('school_requests').doc(requestId).update({
      'status': approved ? 'approved' : 'declined',
      'note': (note ?? '').trim(),
      'reviewedBy': owner.uid,
      'reviewedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> clearAllDataForDevelopment() async {
    final liveSessionsSnapshot = await _firestore
        .collection('live_sessions')
        .get();
    for (final sessionDoc in liveSessionsSnapshot.docs) {
      for (final sub in const <String>[
        'participants',
        'mic_requests',
        'comments',
        'reactions',
        'comment_reports',
      ]) {
        await _deleteCollectionPath('live_sessions/${sessionDoc.id}/$sub');
      }
    }

    for (final collectionPath in const <String>[
      'appointments',
      'care_goals',
      'counselor_availability',
      'counselor_profiles',
      'counselor_public_ratings',
      'counselor_ratings',
      'institution_catalog_registry',
      'institution_membership_audit',
      'institution_members',
      'institution_name_registry',
      'institutions',
      'live_sessions',
      'notifications',
      'onboarding_responses',
      'phone_number_registry',
      'school_requests',
      'user_invites',
      'user_notification_settings',
      'user_privacy_settings',
      'user_push_tokens',
      'users',
    ]) {
      await _deleteCollectionPath(collectionPath);
    }
  }

  String _normalizeInstitutionName(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _institutionNameRegistryKey(String normalizedName) {
    return base64Url.encode(utf8.encode(normalizedName));
  }

  String _institutionNameRegistryPath(String normalizedName) {
    return 'institution_name_registry/${_institutionNameRegistryKey(normalizedName)}';
  }

  String _institutionCatalogRegistryPath(String institutionCatalogId) {
    return 'institution_catalog_registry/${institutionCatalogId.trim()}';
  }

  List<String> _phoneRegistryKeysForRegistration({
    required String primaryPhoneNumber,
    String? additionalPhoneNumber,
  }) {
    return <String>{
      primaryPhoneNumber.replaceAll(RegExp(r'[^0-9]'), ''),
      if (additionalPhoneNumber != null && additionalPhoneNumber.isNotEmpty)
        additionalPhoneNumber.replaceAll(RegExp(r'[^0-9]'), ''),
    }.toList(growable: false);
  }

  List<String> _phoneRegistryPathsForRegistration({
    required String primaryPhoneNumber,
    String? additionalPhoneNumber,
  }) {
    return _phoneRegistryKeysForRegistration(
      primaryPhoneNumber: primaryPhoneNumber,
      additionalPhoneNumber: additionalPhoneNumber,
    ).map((key) => 'phone_number_registry/$key').toList(growable: false);
  }

  DocumentReference<Map<String, dynamic>> _institutionNameRegistryRef(
    String normalizedName,
  ) {
    final key = _institutionNameRegistryKey(normalizedName);
    return _firestore.collection('institution_name_registry').doc(key);
  }

  DocumentReference<Map<String, dynamic>> _institutionCatalogRegistryRef(
    String institutionCatalogId,
  ) {
    return _firestore
        .collection('institution_catalog_registry')
        .doc(institutionCatalogId);
  }

  Future<void> _assertInstitutionCatalogIdAvailable(
    String institutionCatalogId, {
    String? excludeInstitutionId,
  }) async {
    final normalizedCatalogId = institutionCatalogId.trim();
    if (normalizedCatalogId.isEmpty) {
      return;
    }

    if (kUseWindowsRestAuth) {
      final registrySnapshot = await _windowsRest.getDocument(
        _institutionCatalogRegistryPath(normalizedCatalogId),
      );
      if (registrySnapshot != null) {
        final claimedInstitutionId =
            (registrySnapshot.data['institutionId'] as String?) ?? '';
        if (excludeInstitutionId == null ||
            claimedInstitutionId != excludeInstitutionId) {
          throw const _InstitutionDuplicationException(
            'This institution already exists or is pending approval.',
          );
        }
      }
      return;
    }

    final registryRef = _institutionCatalogRegistryRef(normalizedCatalogId);
    final registrySnapshot = await registryRef.get();
    if (registrySnapshot.exists) {
      final claimedInstitutionId =
          (registrySnapshot.data()?['institutionId'] as String?) ?? '';
      if (excludeInstitutionId == null ||
          claimedInstitutionId != excludeInstitutionId) {
        throw const _InstitutionDuplicationException(
          'This institution already exists or is pending approval.',
        );
      }
    }
  }

  DateTime? _asUtcDate(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toUtc();
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return null;
  }

  Future<void> _assertNoActivePendingInvite({
    required String institutionId,
    required String inviteeUid,
    required UserRole role,
  }) async {
    final nowUtc = DateTime.now().toUtc();
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'user_invites',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.equal('inviteeUid', inviteeUid),
          WindowsFirestoreFieldFilter.equal('intendedRole', role.name),
          WindowsFirestoreFieldFilter.equal(
            'status',
            UserInviteStatus.pending.name,
          ),
        ],
        limit: 8,
      );
      for (final doc in documents) {
        final data = doc.data;
        final expiresAt = _asUtcDate(data['expiresAt']);
        final revokedAt = _asUtcDate(data['revokedAt']);
        if (revokedAt != null) {
          continue;
        }
        if (expiresAt == null || expiresAt.isAfter(nowUtc)) {
          throw Exception(
            'A pending invite already exists for this account and role.',
          );
        }
      }
      return;
    }

    final snapshot = await _firestore
        .collection('user_invites')
        .where('institutionId', isEqualTo: institutionId)
        .where('inviteeUid', isEqualTo: inviteeUid)
        .where('intendedRole', isEqualTo: role.name)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .limit(8)
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final expiresAt = _asUtcDate(data['expiresAt']);
      final revokedAt = _asUtcDate(data['revokedAt']);
      if (revokedAt != null) {
        continue;
      }
      if (expiresAt == null || expiresAt.isAfter(nowUtc)) {
        throw Exception(
          'A pending invite already exists for this account and role.',
        );
      }
    }
  }

  String _buildWhatsAppInviteText({
    required String institutionName,
    required String inviterName,
    required UserRole role,
    required String joinCode,
    required DateTime expiresAtUtc,
  }) {
    return 'MindNest invite\n'
        '$inviterName invited you to join $institutionName as ${role.label}.\n'
        'Institution code: $joinCode\n'
        'Open the MindNest app, go to Notifications, and accept the invite.\n'
        'Invite expires: ${expiresAtUtc.toIso8601String()}';
  }

  String _buildWhatsAppDeepLink({
    required String phoneE164,
    required String message,
  }) {
    final destination = phoneE164.replaceAll(RegExp(r'[^0-9]'), '');
    return Uri(
      scheme: 'https',
      host: 'wa.me',
      path: destination,
      queryParameters: <String, String>{'text': message},
    ).toString();
  }

  String _normalizePhoneE164(String rawPhone) {
    var normalized = rawPhone.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (normalized.startsWith('00')) {
      normalized = '+${normalized.substring(2)}';
    }
    if (!normalized.startsWith('+')) {
      throw Exception('Use E.164 format for phone number, e.g. +2547...');
    }
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(normalized)) {
      throw Exception('Phone number must be a valid E.164 number.');
    }
    return normalized;
  }

  String? _normalizeOptionalPhoneE164(String? rawPhone) {
    final trimmed = rawPhone?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == '+254') {
      return null;
    }
    return _normalizePhoneE164(trimmed);
  }

  List<String> _buildPhoneCandidates({
    required String primaryPhone,
    String? additionalPhone,
  }) {
    final candidates = <String>{primaryPhone, primaryPhone.substring(1)};
    if (additionalPhone != null && additionalPhone.isNotEmpty) {
      candidates.add(additionalPhone);
      candidates.add(additionalPhone.substring(1));
    }
    return candidates.toList(growable: false);
  }

  List<DocumentReference<Map<String, dynamic>>>
  _phoneRegistryRefsForRegistration({
    required String primaryPhoneNumber,
    String? additionalPhoneNumber,
  }) {
    return _phoneRegistryKeysForRegistration(
          primaryPhoneNumber: primaryPhoneNumber,
          additionalPhoneNumber: additionalPhoneNumber,
        )
        .map((key) => _firestore.collection('phone_number_registry').doc(key))
        .toList(growable: false);
  }

  Future<WindowsFirestoreDocument?> _findUserByPhoneCandidates(
    List<String> phoneCandidates,
  ) async {
    final uniqueCandidates = phoneCandidates
        .map((candidate) => candidate.trim())
        .where((candidate) => candidate.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (uniqueCandidates.isEmpty) {
      return null;
    }

    final indexedSnapshot = await _windowsRest.queryCollection(
      collectionId: 'users',
      filters: <WindowsFirestoreFieldFilter>[
        WindowsFirestoreFieldFilter.arrayContainsAny(
          'phoneNumbers',
          uniqueCandidates,
        ),
      ],
      limit: 1,
    );
    if (indexedSnapshot.isNotEmpty) {
      return indexedSnapshot.first;
    }

    for (final candidate in uniqueCandidates) {
      final snapshot = await _windowsRest.queryCollection(
        collectionId: 'users',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('phoneNumber', candidate),
        ],
        limit: 1,
      );
      if (snapshot.isNotEmpty) {
        return snapshot.first;
      }

      final secondarySnapshot = await _windowsRest.queryCollection(
        collectionId: 'users',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('additionalPhoneNumber', candidate),
        ],
        limit: 1,
      );
      if (secondarySnapshot.isNotEmpty) {
        return secondarySnapshot.first;
      }
    }

    return null;
  }

  Future<WindowsFirestoreDocument> _resolveInviteeByPhoneWindows(
    String phoneE164,
  ) async {
    final candidates = _buildPhoneCandidates(primaryPhone: phoneE164);
    final user = await _findUserByPhoneCandidates(candidates);
    if (user == null) {
      throw Exception(
        'No user account found for this phone number. Ask the user to register first.',
      );
    }
    return user;
  }

  String _normalizedLifecycleReason(String? reason) {
    final normalized = (reason ?? '').trim();
    if (normalized.isEmpty || normalized == 'admin_dashboard') {
      return '';
    }
    return normalized;
  }

  Future<void> _syncCounselorLifecycleState({
    required String institutionId,
    required String counselorId,
    required String status,
  }) async {
    final isActive = status == 'active';
    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      final userDocument = await _windowsRest.getDocument('users/$counselorId');
      if (userDocument != null) {
        final userData = userDocument.data;
        final rawSetup = userData['counselorSetupData'];
        final setupData = <String, dynamic>{};
        if (rawSetup is Map) {
          for (final entry in rawSetup.entries) {
            setupData[entry.key.toString()] = entry.value;
          }
        }
        setupData['isActive'] = isActive;
        await _windowsRest.setDocument('users/$counselorId', {
          ...userData,
          'counselorApprovalStatus': status,
          'counselorSetupData': setupData,
          'updatedAt': now,
        });
      }

      final profileDocument = await _windowsRest.getDocument(
        'counselor_profiles/$counselorId',
      );
      if (profileDocument != null) {
        await _windowsRest.setDocument('counselor_profiles/$counselorId', {
          ...profileDocument.data,
          'institutionId': institutionId,
          'isActive': isActive,
          'updatedAt': now,
        });
      }
      return;
    }

    final userRef = _firestore.collection('users').doc(counselorId);
    final profileRef = _firestore
        .collection('counselor_profiles')
        .doc(counselorId);
    final userSnapshot = await userRef.get();
    final profileSnapshot = await profileRef.get();
    final batch = _firestore.batch();
    var hasWrites = false;
    if (userSnapshot.exists) {
      batch.update(userRef, {
        'counselorApprovalStatus': status,
        'counselorSetupData.isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      hasWrites = true;
    }
    if (profileSnapshot.exists) {
      batch.set(profileRef, {
        'institutionId': institutionId,
        'isActive': isActive,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      hasWrites = true;
    }
    if (hasWrites) {
      await batch.commit();
    }
  }

  Future<int> _cancelFutureCounselorAppointmentsForLifecycleChange({
    required String institutionId,
    required String counselorId,
    required String counselorDisplayName,
    required String status,
  }) async {
    final now = DateTime.now().toUtc();
    final statusToCancel = <String>{'pending', 'confirmed'};
    final normalizedCounselorName = counselorDisplayName.trim().isEmpty
        ? 'your counselor'
        : counselorDisplayName.trim();
    final cancellationMessage = status == 'removed'
        ? 'Session cancelled because counselor access was removed by the institution admin.'
        : 'Session cancelled because counselor access was suspended by the institution admin.';
    final studentNotificationBody = status == 'removed'
        ? 'Your upcoming session with $normalizedCounselorName was cancelled because the institution admin removed counselor access.'
        : 'Your upcoming session with $normalizedCounselorName was cancelled because the institution admin suspended counselor access.';

    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.equal('counselorId', counselorId),
        ],
      );

      final cancellable = <String, WindowsFirestoreDocument>{};
      for (final doc in documents) {
        final data = doc.data;
        final appointmentStatus = (data['status'] as String?) ?? '';
        final startAt = _asUtcDate(data['startAt']);
        if (!statusToCancel.contains(appointmentStatus) || startAt == null) {
          continue;
        }
        if (startAt.isBefore(now)) {
          continue;
        }
        cancellable[doc.id] = doc;
      }

      if (cancellable.isEmpty) {
        return 0;
      }

      final slotIds = cancellable.values
          .map((doc) => (doc.data['slotId'] as String?) ?? '')
          .where((slotId) => slotId.isNotEmpty)
          .toSet();
      final existingSlots = <String, WindowsFirestoreDocument>{};
      for (final slotId in slotIds) {
        final slot = await _windowsRest.getDocument(
          'counselor_availability/$slotId',
        );
        if (slot != null) {
          existingSlots[slot.id] = slot;
        }
      }

      final notifications = <Map<String, dynamic>>[];
      for (final appointment in cancellable.values) {
        final data = appointment.data;
        await _windowsRest.setDocument('appointments/${appointment.id}', {
          ...data,
          'status': 'cancelled',
          'cancelledByRole': 'institution_admin',
          'counselorCancelMessage': cancellationMessage,
          'cancelledAt': now,
          'updatedAt': now,
        });

        final slotId = (data['slotId'] as String?) ?? '';
        final slot = existingSlots[slotId];
        if (slot != null) {
          await _windowsRest.setDocument('counselor_availability/$slotId', {
            ...slot.data,
            'status': 'available',
            'bookedBy': null,
            'appointmentId': null,
            'updatedAt': now,
          });
        }

        final studentId = ((data['studentId'] as String?) ?? '').trim();
        if (studentId.isNotEmpty) {
          notifications.add(
            _notificationPayload(
              userId: studentId,
              institutionId: institutionId,
              type: 'appointment_cancelled',
              title: 'Counseling session cancelled',
              body: studentNotificationBody,
              relatedId: appointment.id,
              priority: 'high',
            ),
          );
        }
      }

      await _createNotifications(notifications);
      return cancellable.length;
    }

    final snapshot = await _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .get();

    final cancellable = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final appointmentStatus = (data['status'] as String?) ?? '';
      final startAt = _asUtcDate(data['startAt']);
      if (!statusToCancel.contains(appointmentStatus) || startAt == null) {
        continue;
      }
      if (startAt.isBefore(now)) {
        continue;
      }
      cancellable[doc.id] = doc;
    }

    if (cancellable.isEmpty) {
      return 0;
    }

    final slotIds = cancellable.values
        .map((doc) => (doc.data()['slotId'] as String?) ?? '')
        .where((slotId) => slotId.isNotEmpty)
        .toSet();
    final slotRefs = slotIds
        .map(
          (slotId) =>
              _firestore.collection('counselor_availability').doc(slotId),
        )
        .toList(growable: false);
    final slotSnaps = await Future.wait(slotRefs.map((ref) => ref.get()));
    final existingSlotById =
        <String, DocumentReference<Map<String, dynamic>>>{};
    for (var index = 0; index < slotSnaps.length; index++) {
      if (slotSnaps[index].exists) {
        existingSlotById[slotSnaps[index].id] = slotRefs[index];
      }
    }

    final batch = _firestore.batch();
    final notifications = <Map<String, dynamic>>[];
    for (final appointment in cancellable.values) {
      final data = appointment.data();
      batch.update(appointment.reference, {
        'status': 'cancelled',
        'cancelledByRole': 'institution_admin',
        'counselorCancelMessage': cancellationMessage,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final slotId = (data['slotId'] as String?) ?? '';
      final slotRef = existingSlotById[slotId];
      if (slotRef != null) {
        batch.update(slotRef, {
          'status': 'available',
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      final studentId = ((data['studentId'] as String?) ?? '').trim();
      if (studentId.isNotEmpty) {
        notifications.add(
          _notificationPayload(
            userId: studentId,
            institutionId: institutionId,
            type: 'appointment_cancelled',
            title: 'Counseling session cancelled',
            body: studentNotificationBody,
            relatedId: appointment.id,
            priority: 'high',
          ),
        );
      }
    }

    await batch.commit();
    await _createNotifications(notifications);
    return cancellable.length;
  }

  Future<void> _syncFutureCounselorAvailabilityForLifecycleStatus({
    required String institutionId,
    required String counselorId,
    required String status,
  }) async {
    final now = DateTime.now().toUtc();
    if (kUseWindowsRestAuth) {
      final documents = await _windowsRest.queryCollection(
        collectionId: 'counselor_availability',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.equal('counselorId', counselorId),
        ],
      );

      for (final doc in documents) {
        final data = doc.data;
        final endAt = _asUtcDate(data['endAt']);
        if (endAt == null || !endAt.isAfter(now)) {
          continue;
        }
        final slotStatus = ((data['status'] as String?) ?? '')
            .trim()
            .toLowerCase();
        final lifecycleLockReason =
            ((data['lifecycleLockReason'] as String?) ?? '')
                .trim()
                .toLowerCase();

        if (status == 'active') {
          if (slotStatus == 'blocked' &&
              lifecycleLockReason == 'member_suspended') {
            await _windowsRest.setDocument('counselor_availability/${doc.id}', {
              ...data,
              'status': 'available',
              'bookedBy': null,
              'appointmentId': null,
              'lifecycleLocked': false,
              'lifecycleLockReason': null,
              'updatedAt': now,
            });
          }
          continue;
        }

        if (status == 'suspended') {
          if (slotStatus == 'available') {
            await _windowsRest.setDocument('counselor_availability/${doc.id}', {
              ...data,
              'status': 'blocked',
              'bookedBy': null,
              'appointmentId': null,
              'lifecycleLocked': true,
              'lifecycleLockReason': 'member_suspended',
              'updatedAt': now,
            });
          }
          continue;
        }

        if (status == 'removed') {
          await _windowsRest.deleteDocument('counselor_availability/${doc.id}');
        }
      }
      return;
    }

    final snapshot = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .get();
    final batch = _firestore.batch();
    var hasWrites = false;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final endAt = _asUtcDate(data['endAt']);
      if (endAt == null || !endAt.isAfter(now)) {
        continue;
      }
      final slotStatus = ((data['status'] as String?) ?? '')
          .trim()
          .toLowerCase();
      final lifecycleLockReason =
          ((data['lifecycleLockReason'] as String?) ?? '').trim().toLowerCase();

      if (status == 'active') {
        if (slotStatus == 'blocked' &&
            lifecycleLockReason == 'member_suspended') {
          batch.update(doc.reference, {
            'status': 'available',
            'bookedBy': null,
            'appointmentId': null,
            'lifecycleLocked': FieldValue.delete(),
            'lifecycleLockReason': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasWrites = true;
        }
        continue;
      }

      if (status == 'suspended') {
        if (slotStatus == 'available') {
          batch.update(doc.reference, {
            'status': 'blocked',
            'bookedBy': null,
            'appointmentId': null,
            'lifecycleLocked': true,
            'lifecycleLockReason': 'member_suspended',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          hasWrites = true;
        }
        continue;
      }

      if (status == 'removed') {
        batch.delete(doc.reference);
        hasWrites = true;
      }
    }

    if (hasWrites) {
      await batch.commit();
    }
  }

  List<Map<String, dynamic>> _counselorLifecycleNotificationPayloads({
    required String userId,
    required String institutionId,
    required String status,
    required int cancelledAppointments,
    required String reason,
  }) {
    final normalizedReason = reason.trim();
    String title;
    String body;
    String route;
    switch (status) {
      case 'suspended':
        title = 'Counselor access suspended';
        body =
            'Your institution admin suspended your counselor access. You can stay signed in and review notifications, but counselor tools are blocked until access is restored.';
        route = AppRoute.notificationsRoute(
          returnTo: AppRoute.counselorAccessSuspended,
        );
        break;
      case 'removed':
        title = 'Counselor access removed';
        body =
            'Your institution admin removed your counselor access. You have been moved to the recovery screen and can wait there for a new invite.';
        route = AppRoute.notificationsRoute(
          returnTo: AppRoute.counselorInviteWaiting,
        );
        break;
      default:
        title = 'Counselor access restored';
        body =
            'Your institution admin restored your counselor access. You can return to the counselor dashboard.';
        route = AppRoute.counselorDashboard;
        break;
    }

    if (cancelledAppointments > 0) {
      body =
          '$body $cancelledAppointments upcoming ${cancelledAppointments == 1 ? 'session was' : 'sessions were'} cancelled.';
    }
    if (normalizedReason.isNotEmpty) {
      body = '$body Reason: $normalizedReason';
    }

    return <Map<String, dynamic>>[
      _notificationPayload(
        userId: userId,
        institutionId: institutionId,
        type: 'counselor_access_$status',
        title: title,
        body: body,
        route: route,
        priority: 'high',
        actionRequired: status != 'active',
        isPinned: status != 'active',
      ),
    ];
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>> _resolveInviteeByPhone(
    String phoneE164,
  ) async {
    final candidates = <String>{phoneE164};
    if (phoneE164.startsWith('+') && phoneE164.length > 1) {
      candidates.add(phoneE164.substring(1));
    }

    QueryDocumentSnapshot<Map<String, dynamic>>? found;
    for (final candidate in candidates) {
      final indexedSnapshot = await _firestore
          .collection('users')
          .where('phoneNumbers', arrayContains: candidate)
          .limit(1)
          .get();
      if (indexedSnapshot.docs.isNotEmpty) {
        found = indexedSnapshot.docs.first;
        break;
      }

      final snapshot = await _firestore
          .collection('users')
          .where('phoneNumber', isEqualTo: candidate)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        found = snapshot.docs.first;
        break;
      }

      final secondarySnapshot = await _firestore
          .collection('users')
          .where('additionalPhoneNumber', isEqualTo: candidate)
          .limit(1)
          .get();
      if (secondarySnapshot.docs.isNotEmpty) {
        found = secondarySnapshot.docs.first;
        break;
      }
    }
    if (found == null) {
      throw Exception(
        'No user account found for this phone number. Ask the user to register first.',
      );
    }
    return found;
  }

  Future<int> _cancelFutureAppointmentsBeforeLeave({
    required String institutionId,
    required String userId,
  }) async {
    final now = DateTime.now().toUtc();
    final statusToCancel = <String>{'pending', 'confirmed'};

    if (kUseWindowsRestAuth) {
      final studentAppointmentsFuture = _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.equal('studentId', userId),
        ],
      );
      final counselorAppointmentsFuture = _windowsRest.queryCollection(
        collectionId: 'appointments',
        filters: <WindowsFirestoreFieldFilter>[
          WindowsFirestoreFieldFilter.equal('institutionId', institutionId),
          WindowsFirestoreFieldFilter.equal('counselorId', userId),
        ],
      );
      final snapshots = await Future.wait([
        studentAppointmentsFuture,
        counselorAppointmentsFuture,
      ]);

      final cancellable = <String, WindowsFirestoreDocument>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot) {
          final data = doc.data;
          final status = (data['status'] as String?) ?? '';
          final startAt = _asUtcDate(data['startAt']);
          if (!statusToCancel.contains(status) || startAt == null) {
            continue;
          }
          if (startAt.isBefore(now)) {
            continue;
          }
          cancellable[doc.id] = doc;
        }
      }

      if (cancellable.isEmpty) {
        return 0;
      }

      final slotIds = cancellable.values
          .map((doc) => (doc.data['slotId'] as String?) ?? '')
          .where((slotId) => slotId.isNotEmpty)
          .toSet();

      final existingSlotById = <String, WindowsFirestoreDocument>{};
      for (final slotId in slotIds) {
        final slot = await _windowsRest.getDocument(
          'counselor_availability/$slotId',
        );
        if (slot != null) {
          existingSlotById[slot.id] = slot;
        }
      }

      for (final entry in cancellable.values) {
        final data = entry.data;
        final actingRole = ((data['counselorId'] as String?) ?? '') == userId
            ? 'counselor'
            : 'student';
        await _windowsRest.setDocument('appointments/${entry.id}', {
          ...data,
          'status': 'cancelled',
          'cancelledByRole': actingRole,
          'counselorCancelMessage': actingRole == 'counselor'
              ? 'Session cancelled because counselor left the institution.'
              : null,
          'cancelledAt': now,
          'updatedAt': now,
        });

        final slotId = (data['slotId'] as String?) ?? '';
        final slot = existingSlotById[slotId];
        if (slot != null) {
          await _windowsRest.setDocument('counselor_availability/$slotId', {
            ...slot.data,
            'status': 'available',
            'bookedBy': null,
            'appointmentId': null,
            'updatedAt': now,
          });
        }
      }
      return cancellable.length;
    }

    final studentAppointmentsFuture = _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: institutionId)
        .where('studentId', isEqualTo: userId)
        .get();
    final counselorAppointmentsFuture = _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: userId)
        .get();

    final snapshots = await Future.wait([
      studentAppointmentsFuture,
      counselorAppointmentsFuture,
    ]);

    final cancellable = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String?) ?? '';
        final startAt = _asUtcDate(data['startAt']);
        if (!statusToCancel.contains(status) || startAt == null) {
          continue;
        }
        if (startAt.isBefore(now)) {
          continue;
        }
        cancellable[doc.id] = doc;
      }
    }

    if (cancellable.isEmpty) {
      return 0;
    }

    final slotIds = cancellable.values
        .map((doc) => (doc.data()['slotId'] as String?) ?? '')
        .where((slotId) => slotId.isNotEmpty)
        .toSet();

    final slotRefs = slotIds
        .map(
          (slotId) =>
              _firestore.collection('counselor_availability').doc(slotId),
        )
        .toList(growable: false);
    final slotSnaps = await Future.wait(slotRefs.map((ref) => ref.get()));
    final existingSlotById =
        <String, DocumentReference<Map<String, dynamic>>>{};
    for (var i = 0; i < slotSnaps.length; i++) {
      final snap = slotSnaps[i];
      if (snap.exists) {
        existingSlotById[snap.id] = slotRefs[i];
      }
    }

    final batch = _firestore.batch();
    for (final entry in cancellable.values) {
      final data = entry.data();
      final actingRole = ((data['counselorId'] as String?) ?? '') == userId
          ? 'counselor'
          : 'student';
      batch.update(entry.reference, {
        'status': 'cancelled',
        'cancelledByRole': actingRole,
        'counselorCancelMessage': actingRole == 'counselor'
            ? 'Session cancelled because counselor left the institution.'
            : null,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final slotId = (data['slotId'] as String?) ?? '';
      final slotRef = existingSlotById[slotId];
      if (slotRef != null) {
        batch.update(slotRef, {
          'status': 'available',
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
    return cancellable.length;
  }

  Future<int> leaveInstitution() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final userData = kUseWindowsRestAuth
        ? (await _windowsRest.getDocument('users/${currentUser.uid}'))?.data
        : (await _firestore.collection('users').doc(currentUser.uid).get())
              .data();
    final institutionId = userData?['institutionId'] as String?;

    if (institutionId == null || institutionId.isEmpty) {
      return 0;
    }

    final cancelledCount = await _cancelFutureAppointmentsBeforeLeave(
      institutionId: institutionId,
      userId: currentUser.uid,
    );

    if (kUseWindowsRestAuth) {
      final now = DateTime.now().toUtc();
      await _windowsRest.setDocument('users/${currentUser.uid}', {
        ...?userData,
        'institutionId': null,
        'institutionName': null,
        'role': UserRole.individual.name,
        'registrationIntent': null,
        'updatedAt': now,
      });
      await _windowsRest.deleteDocument(
        'institution_members/${institutionId}_${currentUser.uid}',
      );
    } else {
      final userRef = _firestore.collection('users').doc(currentUser.uid);
      final membershipRef = _firestore
          .collection('institution_members')
          .doc('${institutionId}_${currentUser.uid}');

      final batch = _firestore.batch();
      batch.update(userRef, {
        'institutionId': null,
        'institutionName': null,
        'role': UserRole.individual.name,
        'registrationIntent': null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.delete(membershipRef);
      await batch.commit();
    }
    return cancelledCount;
  }

  void _ensureOwnerAccount() {
    if (!isOwnerEmail(_auth.currentUser?.email)) {
      throw Exception('Only owner account can perform this action.');
    }
  }

  Future<String?> _resolveOwnerUserId() async {
    final currentUser = _auth.currentUser;
    if (isOwnerEmail(currentUser?.email)) {
      return currentUser?.uid;
    }
    try {
      if (kUseWindowsRestAuth) {
        final snapshot = await _windowsRest.queryCollection(
          collectionId: 'users',
          filters: <WindowsFirestoreFieldFilter>[
            WindowsFirestoreFieldFilter.equal('email', kOwnerEmail),
          ],
          limit: 1,
        );
        if (snapshot.isNotEmpty) {
          return snapshot.first.id;
        }
        final fallback = await _windowsRest.queryCollection(
          collectionId: 'users',
          filters: <WindowsFirestoreFieldFilter>[
            WindowsFirestoreFieldFilter.equal(
              'email',
              kOwnerEmail.toUpperCase(),
            ),
          ],
          limit: 1,
        );
        if (fallback.isNotEmpty) {
          return fallback.first.id;
        }
      } else {
        final snapshot = await _firestore
            .collection('users')
            .where('email', isEqualTo: kOwnerEmail)
            .limit(1)
            .get();
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.first.id;
        }

        final fallback = await _firestore
            .collection('users')
            .where('email', isEqualTo: kOwnerEmail.toUpperCase())
            .limit(1)
            .get();
        if (fallback.docs.isNotEmpty) {
          return fallback.docs.first.id;
        }
      }
    } catch (_) {
      // Owner lookup can be blocked by security rules for non-owner users.
    }
    return null;
  }

  Map<String, dynamic> _notificationPayload({
    required String userId,
    required String institutionId,
    required String type,
    required String title,
    required String body,
    String? relatedId,
    String? route,
    String priority = 'normal',
    bool actionRequired = false,
    bool isPinned = false,
  }) {
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'userId': userId,
      'institutionId': institutionId,
      'type': type,
      'title': title,
      'body': body,
      'isRead': false,
      'isPinned': isPinned,
      'isArchived': false,
      'priority': priority,
      'actionRequired': actionRequired,
      if (route != null && route.trim().isNotEmpty) 'route': route.trim(),
      'relatedId': relatedId,
      'createdAt': kUseWindowsRestAuth ? now : FieldValue.serverTimestamp(),
      'updatedAt': kUseWindowsRestAuth ? now : FieldValue.serverTimestamp(),
    };
  }

  List<Map<String, dynamic>> _inviteDecisionNotificationPayloads({
    required UserInvite invite,
    required String actorUid,
    required String actorDisplayName,
    required bool accepted,
  }) {
    final roleLabel = invite.intendedRole.label;
    final normalizedActorName = actorDisplayName.trim().isEmpty
        ? 'The invited user'
        : actorDisplayName.trim();
    final decisionVerb = accepted ? 'accepted' : 'declined';
    final decisionType = accepted
        ? 'institution_invite_accepted'
        : 'institution_invite_declined';
    final selfTitle = accepted ? 'Invite accepted' : 'Invite declined';
    final selfBody = accepted
        ? 'You accepted the $roleLabel invite for ${invite.institutionName}.'
        : 'You declined the $roleLabel invite for ${invite.institutionName}.';
    final adminTitle = accepted
        ? '$roleLabel invite accepted'
        : '$roleLabel invite declined';
    final adminBody =
        '$normalizedActorName $decisionVerb the $roleLabel invite for ${invite.institutionName}.';

    final payloads = <Map<String, dynamic>>[
      _notificationPayload(
        userId: actorUid,
        institutionId: invite.institutionId,
        type: decisionType,
        title: selfTitle,
        body: selfBody,
        relatedId: invite.id,
        priority: 'high',
      ),
    ];

    final invitedBy = (invite.invitedBy ?? '').trim();
    if (invitedBy.isNotEmpty && invitedBy != actorUid) {
      payloads.add(
        _notificationPayload(
          userId: invitedBy,
          institutionId: invite.institutionId,
          type: decisionType,
          title: adminTitle,
          body: adminBody,
          relatedId: invite.id,
          priority: 'high',
        ),
      );
    }

    return payloads;
  }

  String _bestInviteActorName({
    required String fallbackName,
    String? fallbackEmail,
  }) {
    final normalizedName = fallbackName.trim();
    if (normalizedName.isNotEmpty) {
      return normalizedName;
    }
    final normalizedEmail = (fallbackEmail ?? '').trim();
    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail;
    }
    return 'The invited user';
  }

  Future<void> _createNotifications(List<Map<String, dynamic>> payloads) async {
    if (payloads.isEmpty) {
      return;
    }
    try {
      if (kUseWindowsRestAuth) {
        for (final payload in payloads) {
          await _windowsRest.setDocument(
            'notifications/${_windowsDocId('notif')}',
            payload,
          );
        }
      } else {
        final batch = _firestore.batch();
        for (final payload in payloads) {
          batch.set(_firestore.collection('notifications').doc(), payload);
        }
        await batch.commit();
      }
    } catch (_) {
      // Notification delivery should not fail critical workflows.
      return;
    }
    unawaited(_dispatchPushNotifications(payloads));
  }

  Future<void> _dispatchPushNotifications(
    List<Map<String, dynamic>> payloads,
  ) async {
    if (_pushDispatchEndpoint.isEmpty) {
      return;
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return;
    }

    try {
      final idToken = await _auth.getIdToken();
      final uri = Uri.tryParse(_pushDispatchEndpoint);
      if (uri == null) {
        return;
      }
      final notifications = payloads
          .map(
            (payload) => <String, dynamic>{
              'userId': payload['userId'],
              'institutionId': payload['institutionId'],
              'title': payload['title'],
              'body': payload['body'],
              'type': payload['type'],
              'relatedId': payload['relatedId'],
              'route': payload['route'],
              'priority': payload['priority'],
              'actionRequired': payload['actionRequired'],
            },
          )
          .toList(growable: false);

      await _httpClient
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{'notifications': notifications}),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      // Keep primary flow responsive.
    } catch (_) {
      // In-app notification already persisted.
    }
  }

  Stream<T> _buildWindowsPollingStream<T>({
    required Future<T> Function() load,
    required String Function(T value) signature,
  }) {
    late final StreamController<T> controller;
    Timer? timer;
    String? lastEmissionSignature;

    Future<void> emitIfChanged() async {
      if (controller.isClosed) {
        return;
      }
      try {
        final value = await load();
        final nextSignature = 'value:${signature(value)}';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.add(value);
        }
      } catch (error, stackTrace) {
        final nextSignature = 'error:$error';
        if (nextSignature == lastEmissionSignature) {
          return;
        }
        lastEmissionSignature = nextSignature;
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(emitIfChanged());
        timer = Timer.periodic(_windowsPollInterval, (_) {
          unawaited(emitIfChanged());
        });
      },
      onCancel: () {
        timer?.cancel();
      },
    );

    return controller.stream;
  }

  List<Map<String, dynamic>> _sortDocumentsByCreatedAt(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs
        .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
        .toList(growable: false);
    items.sort((a, b) {
      final aDate =
          _asUtcDate(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          _asUtcDate(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return items;
  }

  Future<void> _appendMembershipAudit({
    required String institutionId,
    required String actorUid,
    required String targetUserId,
    required String action,
    Map<String, dynamic>? details,
  }) async {
    try {
      final payload = <String, dynamic>{
        'institutionId': institutionId,
        'actorUid': actorUid,
        'targetUserId': targetUserId,
        'action': action,
        'details': details ?? const <String, dynamic>{},
        'createdAt': kUseWindowsRestAuth
            ? DateTime.now().toUtc()
            : FieldValue.serverTimestamp(),
      };
      if (kUseWindowsRestAuth) {
        await _windowsRest.setDocument(
          'institution_membership_audit/${_windowsDocId('audit')}',
          payload,
        );
      } else {
        await _firestore
            .collection('institution_membership_audit')
            .add(payload);
      }
    } catch (_) {
      // Audit logging should not break user-facing operations.
    }
  }

  Future<void> _deleteCollectionPath(
    String collectionPath, {
    int batchSize = 250,
  }) async {
    while (true) {
      final snapshot = await _firestore
          .collection(collectionPath)
          .limit(batchSize)
          .get();
      if (snapshot.docs.isEmpty) {
        break;
      }
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }

  String _generateJoinCode() {
    final buffer = StringBuffer();
    for (var i = 0; i < 8; i++) {
      final index = _random.nextInt(_joinCodeAlphabet.length);
      buffer.write(_joinCodeAlphabet[index]);
    }
    return buffer.toString();
  }

  Future<String> _generateUniqueJoinCode({String? excludeInstitutionId}) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final candidate = _generateJoinCode();
      if (kUseWindowsRestAuth) {
        final documents = await _windowsRest.queryCollection(
          collectionId: 'institutions',
          filters: <WindowsFirestoreFieldFilter>[
            WindowsFirestoreFieldFilter.equal('joinCode', candidate),
          ],
          limit: 1,
        );
        if (documents.isEmpty) {
          return candidate;
        }
        if (excludeInstitutionId != null &&
            documents.first.id == excludeInstitutionId) {
          return candidate;
        }
      } else {
        final snapshot = await _firestore
            .collection('institutions')
            .where('joinCode', isEqualTo: candidate)
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) {
          return candidate;
        }
        if (excludeInstitutionId != null &&
            snapshot.docs.first.id == excludeInstitutionId) {
          return candidate;
        }
      }
    }
    throw Exception('Unable to generate a unique join code. Please retry.');
  }

  Map<String, dynamic> _buildJoinCodePayload({
    required String code,
    required DateTime nowUtc,
    required int usageCount,
  }) {
    return {
      'joinCode': code,
      'joinCodeCreatedAt': kUseWindowsRestAuth
          ? nowUtc
          : Timestamp.fromDate(nowUtc),
      'joinCodeExpiresAt': kUseWindowsRestAuth
          ? nowUtc.add(_joinCodeValidity)
          : Timestamp.fromDate(nowUtc.add(_joinCodeValidity)),
      'joinCodeUsageCount': usageCount,
      'updatedAt': kUseWindowsRestAuth ? nowUtc : FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic>? _synchronizedOnboardingCompletedRoles({
    required Map<String, dynamic> userData,
    required UserRole targetRole,
  }) {
    if (!OnboardingQuestionBank.roleRequiresQuestionnaire(targetRole)) {
      return null;
    }

    final completedRoles = Map<String, dynamic>.from(
      (userData['onboardingCompletedRoles'] as Map?) ??
          const <String, dynamic>{},
    );
    if (completedRoles.isEmpty) {
      return null;
    }

    var highestEquivalentVersion = 0;
    for (final role in OnboardingQuestionBank.completionEquivalentRoles(
      targetRole,
    )) {
      final rawValue = completedRoles[role.name];
      final normalizedValue = rawValue is num ? rawValue.toInt() : 0;
      if (normalizedValue > highestEquivalentVersion) {
        highestEquivalentVersion = normalizedValue;
      }
    }

    if (highestEquivalentVersion == 0) {
      return completedRoles;
    }

    final currentTargetVersion = completedRoles[targetRole.name];
    final normalizedTargetVersion = currentTargetVersion is num
        ? currentTargetVersion.toInt()
        : 0;
    if (normalizedTargetVersion >= highestEquivalentVersion) {
      return completedRoles;
    }

    completedRoles[targetRole.name] = highestEquivalentVersion;
    return completedRoles;
  }
}

class _JoinCodeFlowException implements Exception {
  const _JoinCodeFlowException(this.message);

  final String message;
}

class _InstitutionDuplicationException implements Exception {
  const _InstitutionDuplicationException(this.message);

  final String message;
}

class _PhoneNumberAlreadyInUseException implements Exception {
  const _PhoneNumberAlreadyInUseException(this.message);

  final String message;
}
