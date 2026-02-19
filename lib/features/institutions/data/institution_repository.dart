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

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

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
    final joinCode = _generateJoinCode();

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
      'joinCode': joinCode,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
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

    final userRef = _firestore.collection('users').doc(currentUser.uid);
    final userDoc = await userRef.get();
    final previousInstitutionId = userDoc.data()?['institutionId'] as String?;
    final membershipRef = _firestore
        .collection('institution_members')
        .doc('${institutionDoc.id}_${currentUser.uid}');

    final batch = _firestore.batch();
    batch.update(userRef, {
      'institutionId': institutionDoc.id,
      'institutionName': institutionName,
      'role': role.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(membershipRef, {
      'institutionId': institutionDoc.id,
      'userId': currentUser.uid,
      'role': role.name,
      'userName': currentUser.displayName ?? '',
      'email': currentUser.email ?? '',
      'joinedAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });
    if (previousInstitutionId != null &&
        previousInstitutionId.isNotEmpty &&
        previousInstitutionId != institutionDoc.id) {
      final previousMembershipRef = _firestore
          .collection('institution_members')
          .doc('${previousInstitutionId}_${currentUser.uid}');
      batch.delete(previousMembershipRef);
    }

    await batch.commit();
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
    final timestampBase36 = DateTime.now().millisecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    return timestampBase36.substring(timestampBase36.length - 6);
  }
}
