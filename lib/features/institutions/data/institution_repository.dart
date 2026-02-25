import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/institutions/models/user_invite.dart';

class InstitutionRepository {
  InstitutionRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  static const Duration _joinCodeValidity = Duration(hours: 24);
  static const int _joinCodeMaxUses = 50;
  static const String _joinCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
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
    required String password,
    required String institutionName,
  }) async {
    final trimmedName = adminName.trim();
    final trimmedInstitutionName = institutionName.trim();
    final normalizedEmail = adminEmail.trim().toLowerCase();
    if (trimmedName.length < 2 || trimmedInstitutionName.length < 2) {
      throw Exception('Name and institution name are required.');
    }

    final institutionRef = _firestore.collection('institutions').doc();
    final joinCode = await _generateUniqueJoinCode();
    final joinCodePayload = _buildJoinCodePayload(
      code: joinCode,
      nowUtc: DateTime.now().toUtc(),
      usageCount: 0,
    );

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
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      ...joinCodePayload,
    });
    batch.set(_firestore.collection('users').doc(user.uid), {
      'email': user.email ?? normalizedEmail,
      'name': trimmedName,
      'role': UserRole.institutionAdmin.name,
      'onboardingCompletedRoles': <String, int>{},
      'institutionId': institutionRef.id,
      'institutionName': trimmedInstitutionName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(membershipRef, {
      'institutionId': institutionRef.id,
      'userId': user.uid,
      'role': UserRole.institutionAdmin.name,
      'userName': trimmedName,
      'email': user.email ?? normalizedEmail,
      'joinedAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });
    await batch.commit();
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
