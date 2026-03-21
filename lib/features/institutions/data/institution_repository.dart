// features/institutions/data/institution_repository.dart
import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/core/routes/app_router.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/models/counselor_workflow_settings.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

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
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required http.Client httpClient,
  }) : _firestore = firestore,
       _auth = auth,
       _httpClient = httpClient;

  static const Duration _joinCodeValidity = Duration(hours: 24);
  static const Duration _inviteValidity = Duration(days: 7);
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

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final http.Client _httpClient;
  final Random _random = Random.secure();

  Stream<UserInvite?> pendingInviteForUid(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Stream<UserInvite?>.value(null);
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
    final snapshot = await _firestore.collection('user_invites').doc(inviteId).get();
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
  }

  Future<UserInvite?> getInviteById(String inviteId) async {
    final snapshot = await _firestore.collection('user_invites').doc(inviteId).get();
    final data = snapshot.data();
    if (data == null) {
      return null;
    }
    return UserInvite.fromMap(snapshot.id, data);
  }

  Future<bool> isInstitutionCatalogIdAvailable(
    String institutionCatalogId,
  ) async {
    final normalizedCatalogId = institutionCatalogId.trim();
    if (normalizedCatalogId.isEmpty) {
      return false;
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

    final institutionRef = _firestore.collection('institutions').doc();
    final catalogRegistryRef = _institutionCatalogRegistryRef(
      trimmedInstitutionCatalogId,
    );

    User? user;
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      user = credential.user;
      if (user == null) {
        throw Exception('Unable to create admin account.');
      }
      final createdUser = user;

      await createdUser.updateDisplayName(trimmedName);
      await createdUser.sendEmailVerification();

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
          'email': createdUser.email ?? normalizedEmail,
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
          'email': createdUser.email ?? normalizedEmail,
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
          await user.delete();
        } catch (_) {
          // Keep rollback resilient.
        }
      }
      throw Exception(error.message);
    } on _InstitutionDuplicationException {
      if (user != null) {
        try {
          await user.delete();
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

    final profileDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final profile = profileDoc.data();
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
    final inviteeUser = await _resolveInviteeByPhone(normalizedPhone);
    if (inviteeUser.id == currentUser.uid) {
      throw Exception('You cannot invite your own account.');
    }
    final inviteeData = inviteeUser.data();
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
      inviteeUid: inviteeUser.id,
      inviteeInstitutionId: (inviteeData['institutionId'] as String?) ?? '',
    );

    await _assertNoActivePendingInvite(
      institutionId: institutionId,
      inviteeUid: inviteeUser.id,
      role: role,
    );

    final institutionDoc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .get();
    final institutionData = institutionDoc.data();
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
    final inviteRef = _firestore.collection('user_invites').doc();

    await inviteRef.set({
      'institutionId': institutionId,
      'institutionName': institutionName,
      'inviteeUid': inviteeUser.id,
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

    final inviteRoute = role == UserRole.counselor
        ? Uri(
            path: AppRoute.inviteAccept,
            queryParameters: <String, String>{AppRoute.inviteIdQuery: inviteRef.id},
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
        userId: inviteeUser.id,
        institutionId: institutionId,
        type: 'institution_invite',
        title: 'Invitation to join $institutionName',
        body:
            'You were invited as ${role.label}. Open this alert and enter your institution code to accept.',
        relatedId: inviteRef.id,
        priority: 'high',
        actionRequired: true,
        route: inviteRoute,
        isPinned: true,
      ),
    ]);

    await _appendMembershipAudit(
      institutionId: institutionId,
      actorUid: currentUser.uid,
      targetUserId: inviteeUser.id,
      action: 'invite_created',
      details: <String, dynamic>{
        'inviteId': inviteRef.id,
        'intendedRole': role.name,
        'inviteePhoneE164': normalizedPhone,
        'expiresAt': Timestamp.fromDate(expiresAtUtc),
      },
    );

    return InAppInviteDraft(
      inviteId: inviteRef.id,
      inviteeUid: inviteeUser.id,
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
    final snapshot = await _firestore
        .collection('users')
        .where('phoneNumbers', arrayContainsAny: phoneCandidates)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) {
      return null;
    }
    final data = snapshot.docs.first.data();
    final intent = (data['registrationIntent'] as String?)?.trim();
    if (intent != UserProfile.counselorRegistrationIntent) {
      return null;
    }
    final name = (data['name'] as String?)?.trim();
    return name?.isNotEmpty == true ? name! : 'This user';
  }

  Future<void> _assertInviteeNotAlreadyMember({
    required String targetInstitutionId,
    required String inviteeUid,
    required String inviteeInstitutionId,
  }) async {
    // Check active/pending membership documents.
    final existingMembership = await _firestore
        .collection('institution_members')
        .where('userId', isEqualTo: inviteeUid)
        .where('status', whereIn: ['active', 'pending'])
        .limit(1)
        .get();

    String? blockingInstitutionId;
    String? blockingRole;
    if (existingMembership.docs.isNotEmpty) {
      final data = existingMembership.docs.first.data();
      blockingInstitutionId = (data['institutionId'] as String?) ?? '';
      blockingRole = (data['role'] as String?) ?? '';
    } else if (inviteeInstitutionId.isNotEmpty) {
      // Fallback to profile flag if membership doc not found.
      blockingInstitutionId = inviteeInstitutionId;
    }

    if (blockingInstitutionId == null || blockingInstitutionId.isEmpty) {
      return;
    }

    // Resolve institution name for clearer error.
    String institutionName = blockingInstitutionId;
    try {
      final instSnap = await _firestore
          .collection('institutions')
          .doc(blockingInstitutionId)
          .get();
      institutionName =
          (instSnap.data()?['name'] as String?)?.trim().isNotEmpty == true
              ? (instSnap.data()!['name'] as String)
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
    final inviteRef = _firestore.collection('user_invites').doc(invite.id);
    final snapshot = await inviteRef.get();
    final data = snapshot.data();
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
      final previousInstitutionId =
          userSnapshot.data()!['institutionId'] as String?;

      final memberStatus = intendedRole == UserRole.counselor
          ? 'pending'
          : 'active';
      final membershipRef = _firestore
          .collection('institution_members')
          .doc('${invite.institutionId}_${currentUser.uid}');

      transaction.update(userRef, {
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
      });
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
    final profileDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final profile = profileDoc.data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can revoke invites.');
    }
    final institutionId = (profile['institutionId'] as String?) ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final inviteRef = _firestore.collection('user_invites').doc(inviteId);
    final snapshot = await inviteRef.get();
    final data = snapshot.data();
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
    await inviteRef.update({
      'status': UserInviteStatus.revoked.name,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedByUid': currentUser.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    if (!allowed.contains(normalizedStatus)) {
      throw Exception('Unsupported member status.');
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    final profileDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final profile = profileDoc.data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can update member status.');
    }
    final institutionId = (profile['institutionId'] as String?) ?? '';
    if (institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final membershipRef = _firestore
        .collection('institution_members')
        .doc('${institutionId}_$memberUserId');
    final membershipSnapshot = await membershipRef.get();
    final membership = membershipSnapshot.data();
    if (membership == null) {
      throw Exception('Member record not found.');
    }
    final memberRole = (membership['role'] as String?) ?? '';
    if (memberRole == UserRole.institutionAdmin.name &&
        memberUserId == currentUser.uid) {
      throw Exception('You cannot change your own admin membership status.');
    }

    await membershipRef.update({
      'status': normalizedStatus,
      'lifecycleReason': (reason ?? '').trim(),
      'lifecycleUpdatedBy': currentUser.uid,
      'lifecycleUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _appendMembershipAudit(
      institutionId: institutionId,
      actorUid: currentUser.uid,
      targetUserId: memberUserId,
      action: 'member_status_changed',
      details: <String, dynamic>{
        'nextStatus': normalizedStatus,
        'reason': (reason ?? '').trim(),
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
          'email': currentUser.email ?? '',
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
        chunks.add(inviteIds.sublist(
          i,
          i + 10 > inviteIds.length ? inviteIds.length : i + 10,
        ));
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

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final profile = userDoc.data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can regenerate join codes.');
    }

    final institutionId = profile['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }
    final institutionDoc = await _firestore
        .collection('institutions')
        .doc(institutionId)
        .get();
    final institutionData = institutionDoc.data();
    final status = (institutionData?['status'] as String?) ?? 'approved';
    if (status != 'approved') {
      throw Exception('Join code is available only after approval.');
    }

    final nextJoinCode = await _generateUniqueJoinCode(
      excludeInstitutionId: institutionId,
    );
    await _firestore
        .collection('institutions')
        .doc(institutionId)
        .update(
          _buildJoinCodePayload(
            code: nextJoinCode,
            nowUtc: DateTime.now().toUtc(),
            usageCount: 0,
          ),
        );
  }

  Stream<Map<String, dynamic>?> watchCurrentAdminInstitution() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Stream<Map<String, dynamic>?>.empty();
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

    final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
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

  Future<Map<String, dynamic>?> getInstitutionDocument(String institutionId) async {
    final normalized = institutionId.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final doc = await _firestore.collection('institutions').doc(normalized).get();
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

    final userSnapshot = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final institutionId = userSnapshot.data()?['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Institution not found for this admin account.');
    }

    await _firestore.collection('institutions').doc(institutionId).update({
      ...settings.toInstitutionPatch(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> watchOwnerPendingInstitutions() {
    _ensureOwnerAccount();
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
        final requesterDoc = await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .get();
        notificationInstitutionId =
            (requesterDoc.data()?['institutionId'] as String?) ?? '';
      } catch (_) {
        notificationInstitutionId = '';
      }
    }
    final createdDoc = await _firestore.collection('school_requests').add({
      'schoolName': normalizedSchoolName,
      if (normalizedMobile.isNotEmpty) 'mobileNumber': normalizedMobile,
      'requesterUid': currentUser?.uid,
      'requesterName': (requesterName ?? currentUser?.displayName ?? '').trim(),
      'requesterEmail': (requesterEmail ?? currentUser?.email ?? '')
          .trim()
          .toLowerCase(),
      'status': 'pending',
      'ownerEmail': kOwnerEmail,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

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
          relatedId: createdDoc.id,
        ),
      ]);
    }
  }

  Future<void> dismissInstitutionWelcome() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    await _firestore.collection('users').doc(currentUser.uid).update({
      'institutionWelcomePending': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> approveInstitutionRequest({
    required String institutionId,
  }) async {
    _ensureOwnerAccount();
    final owner = _auth.currentUser;
    if (owner == null) {
      throw Exception('You must be logged in.');
    }

    final institutionRef = _firestore
        .collection('institutions')
        .doc(institutionId);
    final nextJoinCode = await _generateUniqueJoinCode(
      excludeInstitutionId: institutionId,
    );

    String? createdBy;
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

    final institutionRef = _firestore
        .collection('institutions')
        .doc(institutionId);
    final snapshot = await institutionRef.get();
    final data = snapshot.data();
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

    final userDoc = await _firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final profile = userDoc.data();
    if (profile == null ||
        (profile['role'] as String?) != UserRole.institutionAdmin.name) {
      throw Exception('Only institution admins can resubmit requests.');
    }

    final institutionId = profile['institutionId'] as String?;
    if (institutionId == null || institutionId.isEmpty) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    final institutionRef = _firestore
        .collection('institutions')
        .doc(institutionId);
    final snapshot = await institutionRef.get();
    final data = snapshot.data();
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
    final userRef = _firestore.collection('users').doc(currentUser.uid);
    await _assertInstitutionCatalogIdAvailable(
      trimmedInstitutionCatalogId,
      excludeInstitutionId: institutionId,
    );

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
          'review': <String, dynamic>{
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
        transaction.set(_institutionNameRegistryRef(normalizedNameKey), {
          'institutionId': institutionId,
          'institutionName': trimmedInstitutionName,
          'normalizedName': normalizedNameKey,
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } on _InstitutionDuplicationException {
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

  DocumentReference<Map<String, dynamic>> _institutionNameRegistryRef(
    String normalizedName,
  ) {
    final key = base64Url.encode(utf8.encode(normalizedName));
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
    final snapshot = await _firestore
        .collection('user_invites')
        .where('institutionId', isEqualTo: institutionId)
        .where('inviteeUid', isEqualTo: inviteeUid)
        .where('intendedRole', isEqualTo: role.name)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .limit(8)
        .get();
    if (snapshot.docs.isEmpty) {
      return;
    }
    final nowUtc = DateTime.now().toUtc();
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
    final keys = <String>{
      primaryPhoneNumber.replaceAll(RegExp(r'[^0-9]'), ''),
      if (additionalPhoneNumber != null && additionalPhoneNumber.isNotEmpty)
        additionalPhoneNumber.replaceAll(RegExp(r'[^0-9]'), ''),
    };
    return keys
        .map((key) => _firestore.collection('phone_number_registry').doc(key))
        .toList(growable: false);
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

    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final userSnapshot = await userRef.get();
    final institutionId = userSnapshot.data()?['institutionId'] as String?;

    if (institutionId == null || institutionId.isEmpty) {
      return 0;
    }

    final cancelledCount = await _cancelFutureAppointmentsBeforeLeave(
      institutionId: institutionId,
      userId: currentUser.uid,
    );

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
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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
      final batch = _firestore.batch();
      for (final payload in payloads) {
        batch.set(_firestore.collection('notifications').doc(), payload);
      }
      await batch.commit();
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
      final idToken = await currentUser.getIdToken();
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

  Future<void> _appendMembershipAudit({
    required String institutionId,
    required String actorUid,
    required String targetUserId,
    required String action,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _firestore.collection('institution_membership_audit').add({
        'institutionId': institutionId,
        'actorUid': actorUid,
        'targetUserId': targetUserId,
        'action': action,
        'details': details ?? const <String, dynamic>{},
        'createdAt': FieldValue.serverTimestamp(),
      });
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
    throw Exception('Unable to generate a unique join code. Please retry.');
  }

  Map<String, dynamic> _buildJoinCodePayload({
    required String code,
    required DateTime nowUtc,
    required int usageCount,
  }) {
    return {
      'joinCode': code,
      'joinCodeCreatedAt': Timestamp.fromDate(nowUtc),
      'joinCodeExpiresAt': Timestamp.fromDate(nowUtc.add(_joinCodeValidity)),
      'joinCodeUsageCount': usageCount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
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
