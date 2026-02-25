import 'dart:math';
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/core/config/owner_config.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

class InstitutionRepository {
  InstitutionRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
    required http.Client httpClient,
  }) : _firestore = firestore,
       _auth = auth,
       _httpClient = httpClient;

  static const Duration _joinCodeValidity = Duration(hours: 24);
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

  Stream<UserInvite?> pendingInviteForEmail(String email) {
    final normalizedEmail = email.trim().toLowerCase();
    return _firestore
        .collection('user_invites')
        .where('invitedEmail', isEqualTo: normalizedEmail)
        .where('status', isEqualTo: UserInviteStatus.pending.name)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }
          final doc = snapshot.docs.first;
          return UserInvite.fromMap(doc.id, doc.data());
        });
  }

  Future<void> createInstitutionAdminAccount({
    required String adminName,
    required String adminEmail,
    required String adminPhoneNumber,
    required String password,
    required String institutionName,
  }) async {
    final trimmedName = adminName.trim();
    final trimmedInstitutionName = institutionName.trim();
    final trimmedAdminPhone = adminPhoneNumber.trim();
    final normalizedEmail = adminEmail.trim().toLowerCase();
    if (trimmedName.length < 2 ||
        trimmedInstitutionName.length < 2 ||
        trimmedAdminPhone.length < 6) {
      throw Exception('Name, institution name, and phone number are required.');
    }

    final institutionRef = _firestore.collection('institutions').doc();

    final credential = await _auth.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw Exception('Unable to create admin account.');
    }

    await user.updateDisplayName(trimmedName);
    await user.sendEmailVerification();

    final membershipRef = _firestore
        .collection('institution_members')
        .doc('${institutionRef.id}_${user.uid}');

    final batch = _firestore.batch();
    batch.set(institutionRef, {
      'name': trimmedInstitutionName,
      'status': 'pending',
      'createdBy': user.uid,
      'adminPhoneNumber': trimmedAdminPhone,
      'contactPhone': trimmedAdminPhone,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'review': <String, dynamic>{
        'reviewedBy': null,
        'reviewedAt': null,
        'decision': null,
        'declineReason': null,
      },
    });
    batch.set(_firestore.collection('users').doc(user.uid), {
      'email': user.email ?? normalizedEmail,
      'name': trimmedName,
      'role': UserRole.institutionAdmin.name,
      'onboardingCompletedRoles': <String, int>{},
      'institutionId': institutionRef.id,
      'institutionName': trimmedInstitutionName,
      'phoneNumber': trimmedAdminPhone,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(membershipRef, {
      'institutionId': institutionRef.id,
      'userId': user.uid,
      'role': UserRole.institutionAdmin.name,
      'userName': trimmedName,
      'email': user.email ?? normalizedEmail,
      'phoneNumber': trimmedAdminPhone,
      'joinedAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });
    await batch.commit();

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

    await _createNotifications([
      _notificationPayload(
        userId: user.uid,
        institutionId: institutionRef.id,
        type: 'institution_request_pending',
        title: 'Institution submitted',
        body:
            'Your institution request is pending review. Approval usually takes about 30 minutes.',
      ),
    ]);
  }

  Future<void> createRoleInvite({
    required String invitedName,
    required String invitedEmail,
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

    final institutionId = profile['institutionId'] as String?;
    final institutionName = profile['institutionName'] as String?;
    if (institutionId == null || institutionName == null) {
      throw Exception('Admin profile is not linked to an institution.');
    }

    await _firestore.collection('user_invites').add({
      'institutionId': institutionId,
      'institutionName': institutionName,
      'invitedName': invitedName.trim(),
      'invitedEmail': invitedEmail.trim().toLowerCase(),
      'intendedRole': role.name,
      'status': 'pending',
      'invitedBy': currentUser.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> createCounselorInvite({
    required String counselorName,
    required String counselorEmail,
  }) {
    return createRoleInvite(
      invitedName: counselorName,
      invitedEmail: counselorEmail,
      role: UserRole.counselor,
    );
  }

  Future<void> declineInvite(UserInvite invite) async {
    if (!invite.isPending) {
      throw Exception('Only pending invites can be declined.');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    final currentEmail = (currentUser.email ?? '').toLowerCase();
    if (currentEmail != invite.invitedEmail.toLowerCase()) {
      throw Exception('This invite is not linked to your account email.');
    }
    await _firestore.collection('user_invites').doc(invite.id).update({
      'status': UserInviteStatus.declined.name,
      'declinedAt': FieldValue.serverTimestamp(),
      'declinedByUid': currentUser.uid,
    });
  }

  Future<void> acceptInvite(UserInvite invite) async {
    if (!invite.isPending) {
      throw Exception('Only pending invites can be accepted.');
    }
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    final currentEmail = (currentUser.email ?? '').toLowerCase();
    if (currentEmail != invite.invitedEmail.toLowerCase()) {
      throw Exception('This invite is not linked to your account email.');
    }

    if (invite.intendedRole != UserRole.student &&
        invite.intendedRole != UserRole.staff &&
        invite.intendedRole != UserRole.counselor) {
      throw Exception('Invite has unsupported role.');
    }

    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw Exception('User profile not found.');
    }

    final previousInstitutionId = userDoc.data()?['institutionId'] as String?;
    final newMembershipRef = _firestore
        .collection('institution_members')
        .doc('${invite.institutionId}_${currentUser.uid}');

    final batch = _firestore.batch();
    final userUpdatePayload = <String, dynamic>{
      'institutionId': invite.institutionId,
      'institutionName': invite.institutionName,
      'role': invite.intendedRole.name,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (invite.intendedRole == UserRole.counselor) {
      userUpdatePayload['counselorSetupCompleted'] = false;
      userUpdatePayload['counselorSetupData'] = <String, dynamic>{};
    }
    batch.update(userRef, {...userUpdatePayload});
    batch.set(newMembershipRef, {
      'institutionId': invite.institutionId,
      'userId': currentUser.uid,
      'role': invite.intendedRole.name,
      'userName': currentUser.displayName ?? invite.invitedName,
      'email': currentEmail,
      'joinedAt': FieldValue.serverTimestamp(),
      'status': 'active',
      'joinedVia': 'invite',
    });
    batch.update(_firestore.collection('user_invites').doc(invite.id), {
      'status': UserInviteStatus.accepted.name,
      'acceptedAt': FieldValue.serverTimestamp(),
      'acceptedByUid': currentUser.uid,
    });

    if (previousInstitutionId != null &&
        previousInstitutionId.isNotEmpty &&
        previousInstitutionId != invite.institutionId) {
      final previousMembershipRef = _firestore
          .collection('institution_members')
          .doc('${previousInstitutionId}_${currentUser.uid}');
      batch.delete(previousMembershipRef);
    }

    await batch.commit();
  }

  Future<void> joinInstitutionByCode({
    required String code,
    required UserRole role,
  }) async {
    if (role != UserRole.student && role != UserRole.staff) {
      throw Exception('Only Student or Staff can join with code.');
    }

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
          'role': role.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.set(membershipRef, {
          'institutionId': institutionDoc.id,
          'userId': currentUser.uid,
          'role': role.name,
          'userName': currentUser.displayName ?? '',
          'email': currentUser.email ?? '',
          'joinedAt': FieldValue.serverTimestamp(),
          'status': 'active',
          'joinedVia': 'code',
          'joinedCode': normalizedCode,
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
    required String mobileNumber,
    String? requesterName,
    String? requesterEmail,
  }) async {
    final normalizedSchoolName = schoolName.trim();
    final normalizedMobile = mobileNumber.trim();
    if (normalizedSchoolName.length < 2) {
      throw Exception('School name is required.');
    }
    if (normalizedMobile.length < 6) {
      throw Exception('Mobile number is required.');
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
      'mobileNumber': normalizedMobile,
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
      createdBy = data['createdBy'] as String?;
      transaction.update(institutionRef, {
        'status': 'approved',
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

    await institutionRef.update({
      'status': 'declined',
      'updatedAt': FieldValue.serverTimestamp(),
      'review': <String, dynamic>{
        'reviewedBy': owner.uid,
        'reviewedAt': FieldValue.serverTimestamp(),
        'decision': 'declined',
        'declineReason': reason,
      },
    });

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

    final normalizedName = institutionName.trim();
    if (normalizedName.length < 2) {
      throw Exception('Select a valid institution name.');
    }

    await institutionRef.update({
      'name': normalizedName,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      'review': <String, dynamic>{
        'reviewedBy': null,
        'reviewedAt': null,
        'decision': null,
        'declineReason': null,
      },
    });

    final ownerUserId = await _resolveOwnerUserId();
    if (ownerUserId != null) {
      await _createNotifications([
        _notificationPayload(
          userId: ownerUserId,
          institutionId: institutionId,
          type: 'institution_request_resubmitted',
          title: 'Institution request resubmitted',
          body: '$normalizedName was resubmitted for approval.',
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
      'institution_members',
      'institutions',
      'live_sessions',
      'notifications',
      'onboarding_responses',
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

  DateTime? _asUtcDate(dynamic raw) {
    if (raw is Timestamp) {
      return raw.toDate().toUtc();
    }
    if (raw is DateTime) {
      return raw.toUtc();
    }
    return null;
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
  }) {
    return <String, dynamic>{
      'userId': userId,
      'institutionId': institutionId,
      'type': type,
      'title': title,
      'body': body,
      'isRead': false,
      'relatedId': relatedId,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
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
