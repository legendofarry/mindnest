import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';
import 'package:mindnest/features/care/models/appointment_record.dart';
import 'package:mindnest/features/care/models/availability_slot.dart';
import 'package:mindnest/features/care/models/counselor_profile.dart';

class CareRepository {
  CareRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Stream<List<CounselorProfile>> watchCounselors({
    required String institutionId,
  }) {
    return _firestore
        .collection('counselor_profiles')
        .where('institutionId', isEqualTo: institutionId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          final profiles = snapshot.docs
              .map((doc) => CounselorProfile.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          profiles.sort((a, b) => a.displayName.compareTo(b.displayName));
          return profiles;
        });
  }

  Stream<CounselorProfile?> watchCounselorProfile(String counselorId) {
    return _firestore
        .collection('counselor_profiles')
        .doc(counselorId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) {
            return null;
          }
          return CounselorProfile.fromMap(doc.id, doc.data()!);
        });
  }

  Stream<List<AvailabilitySlot>> watchCounselorPublicAvailability({
    required String institutionId,
    required String counselorId,
  }) {
    return _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .where('status', isEqualTo: AvailabilitySlotStatus.available.name)
        .snapshots()
        .map((snapshot) {
          final slots = snapshot.docs
              .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
              .where((slot) => slot.endAt.isAfter(DateTime.now().toUtc()))
              .toList(growable: false);
          slots.sort((a, b) => a.startAt.compareTo(b.startAt));
          return slots;
        });
  }

  Stream<List<AvailabilitySlot>> watchCounselorSlots({
    required String institutionId,
    required String counselorId,
  }) {
    return _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .snapshots()
        .map((snapshot) {
          final slots = snapshot.docs
              .map((doc) => AvailabilitySlot.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          slots.sort((a, b) => a.startAt.compareTo(b.startAt));
          return slots;
        });
  }

  Future<void> createAvailabilitySlot({
    required String institutionId,
    required DateTime startAtUtc,
    required DateTime endAtUtc,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (!endAtUtc.isAfter(startAtUtc)) {
      throw Exception('End time must be after start time.');
    }

    final overlapping = await _firestore
        .collection('counselor_availability')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: currentUser.uid)
        .where('startAt', isLessThan: Timestamp.fromDate(endAtUtc))
        .get();

    for (final doc in overlapping.docs) {
      final data = doc.data();
      final existing = AvailabilitySlot.fromMap(doc.id, data);
      if (existing.endAt.isAfter(startAtUtc) &&
          existing.status != AvailabilitySlotStatus.blocked) {
        throw Exception('This slot overlaps with an existing schedule.');
      }
    }

    await _firestore.collection('counselor_availability').add({
      'institutionId': institutionId,
      'counselorId': currentUser.uid,
      'startAt': Timestamp.fromDate(startAtUtc),
      'endAt': Timestamp.fromDate(endAtUtc),
      'status': AvailabilitySlotStatus.available.name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAvailabilitySlot(AvailabilitySlot slot) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (slot.counselorId != currentUser.uid) {
      throw Exception('You cannot modify this slot.');
    }
    if (slot.status != AvailabilitySlotStatus.available) {
      throw Exception('Only available slots can be removed.');
    }

    await _firestore.collection('counselor_availability').doc(slot.id).delete();
  }

  Future<void> bookCounselorSlot({
    required String institutionId,
    required CounselorProfile counselor,
    required AvailabilitySlot slot,
    required UserProfile currentProfile,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (currentProfile.role != UserRole.student &&
        currentProfile.role != UserRole.staff &&
        currentProfile.role != UserRole.individual) {
      throw Exception('Your role cannot book counseling sessions.');
    }
    if (slot.status != AvailabilitySlotStatus.available) {
      throw Exception('Selected slot is no longer available.');
    }

    final slotRef = _firestore
        .collection('counselor_availability')
        .doc(slot.id);
    final appointmentRef = _firestore.collection('appointments').doc();

    await _firestore.runTransaction((transaction) async {
      final slotSnap = await transaction.get(slotRef);
      if (!slotSnap.exists || slotSnap.data() == null) {
        throw Exception('Slot no longer exists.');
      }
      final freshSlot = AvailabilitySlot.fromMap(slotSnap.id, slotSnap.data()!);
      if (freshSlot.status != AvailabilitySlotStatus.available) {
        throw Exception('Slot already booked.');
      }

      transaction.set(appointmentRef, {
        'institutionId': institutionId,
        'counselorId': counselor.id,
        'studentId': currentUser.uid,
        'slotId': slot.id,
        'startAt': Timestamp.fromDate(freshSlot.startAt.toUtc()),
        'endAt': Timestamp.fromDate(freshSlot.endAt.toUtc()),
        'status': AppointmentStatus.pending.name,
        'studentName': currentProfile.name,
        'counselorName': counselor.displayName,
        'rated': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(slotRef, {
        'status': AvailabilitySlotStatus.booked.name,
        'bookedBy': currentUser.uid,
        'appointmentId': appointmentRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<List<AppointmentRecord>> watchStudentAppointments({
    required String institutionId,
    required String studentId,
  }) {
    return _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: institutionId)
        .where('studentId', isEqualTo: studentId)
        .snapshots()
        .map((snapshot) {
          final appointments = snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          appointments.sort((a, b) => b.startAt.compareTo(a.startAt));
          return appointments;
        });
  }

  Stream<List<AppointmentRecord>> watchCounselorAppointments({
    required String institutionId,
    required String counselorId,
  }) {
    return _firestore
        .collection('appointments')
        .where('institutionId', isEqualTo: institutionId)
        .where('counselorId', isEqualTo: counselorId)
        .snapshots()
        .map((snapshot) {
          final appointments = snapshot.docs
              .map((doc) => AppointmentRecord.fromMap(doc.id, doc.data()))
              .toList(growable: false);
          appointments.sort((a, b) => a.startAt.compareTo(b.startAt));
          return appointments;
        });
  }

  Future<void> cancelAppointmentAsStudent(AppointmentRecord appointment) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.studentId != currentUser.uid) {
      throw Exception('This appointment does not belong to you.');
    }
    if (appointment.status != AppointmentStatus.pending &&
        appointment.status != AppointmentStatus.confirmed) {
      throw Exception('Only pending or confirmed sessions can be cancelled.');
    }

    await _updateAppointmentAndReleaseSlot(
      appointmentId: appointment.id,
      slotId: appointment.slotId,
      newStatus: AppointmentStatus.cancelled,
    );
  }

  Future<void> updateAppointmentByCounselor({
    required AppointmentRecord appointment,
    required AppointmentStatus newStatus,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.counselorId != currentUser.uid) {
      throw Exception('You cannot update this appointment.');
    }
    if (newStatus == AppointmentStatus.cancelled) {
      await _updateAppointmentAndReleaseSlot(
        appointmentId: appointment.id,
        slotId: appointment.slotId,
        newStatus: newStatus,
      );
      return;
    }

    await _firestore.collection('appointments').doc(appointment.id).update({
      'status': newStatus.name,
      'updatedAt': FieldValue.serverTimestamp(),
      if (newStatus == AppointmentStatus.completed)
        'completedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _updateAppointmentAndReleaseSlot({
    required String appointmentId,
    required String slotId,
    required AppointmentStatus newStatus,
  }) async {
    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointmentId);
    final slotRef = _firestore.collection('counselor_availability').doc(slotId);

    await _firestore.runTransaction((transaction) async {
      final slotSnap = await transaction.get(slotRef);
      if (slotSnap.exists) {
        transaction.update(slotRef, {
          'status': AvailabilitySlotStatus.available.name,
          'bookedBy': null,
          'appointmentId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.update(appointmentRef, {
        'status': newStatus.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> submitRating({
    required AppointmentRecord appointment,
    required int rating,
    required String feedback,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }
    if (appointment.studentId != currentUser.uid) {
      throw Exception('This appointment does not belong to you.');
    }
    if (appointment.status != AppointmentStatus.completed) {
      throw Exception('You can only rate completed sessions.');
    }
    if (appointment.rated) {
      throw Exception('This appointment is already rated.');
    }
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5.');
    }

    final ratingRef = _firestore.collection('counselor_ratings').doc();
    final appointmentRef = _firestore
        .collection('appointments')
        .doc(appointment.id);
    final counselorRef = _firestore
        .collection('counselor_profiles')
        .doc(appointment.counselorId);

    await _firestore.runTransaction((transaction) async {
      final counselorSnap = await transaction.get(counselorRef);
      if (!counselorSnap.exists || counselorSnap.data() == null) {
        throw Exception('Counselor profile not found.');
      }
      final counselorData = counselorSnap.data()!;
      final oldCount = (counselorData['ratingCount'] as num?)?.toInt() ?? 0;
      final oldAverage =
          (counselorData['ratingAverage'] as num?)?.toDouble() ?? 0.0;
      final newCount = oldCount + 1;
      final newAverage = ((oldAverage * oldCount) + rating) / newCount;

      transaction.set(ratingRef, {
        'appointmentId': appointment.id,
        'institutionId': appointment.institutionId,
        'counselorId': appointment.counselorId,
        'studentId': appointment.studentId,
        'rating': rating,
        'feedback': feedback.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      transaction.update(appointmentRef, {
        'rated': true,
        'ratingValue': rating,
        'ratingId': ratingRef.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      transaction.update(counselorRef, {
        'ratingCount': newCount,
        'ratingAverage': newAverage,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
