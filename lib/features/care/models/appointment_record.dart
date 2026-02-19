import 'package:cloud_firestore/cloud_firestore.dart';

enum AppointmentStatus { pending, confirmed, completed, cancelled }

class AppointmentRecord {
  const AppointmentRecord({
    required this.id,
    required this.institutionId,
    required this.counselorId,
    required this.studentId,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.slotId,
    this.studentName,
    this.counselorName,
    this.rated = false,
    this.ratingValue,
    this.counselorCancelMessage,
    this.cancelledByRole,
  });

  final String id;
  final String institutionId;
  final String counselorId;
  final String studentId;
  final DateTime startAt;
  final DateTime endAt;
  final AppointmentStatus status;
  final String slotId;
  final String? studentName;
  final String? counselorName;
  final bool rated;
  final int? ratingValue;
  final String? counselorCancelMessage;
  final String? cancelledByRole;

  factory AppointmentRecord.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final statusRaw = (data['status'] as String?) ?? 'pending';
    final status = AppointmentStatus.values.firstWhere(
      (value) => value.name == statusRaw,
      orElse: () => AppointmentStatus.pending,
    );

    return AppointmentRecord(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      counselorId: (data['counselorId'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      startAt: parseDate(data['startAt']),
      endAt: parseDate(data['endAt']),
      status: status,
      slotId: (data['slotId'] as String?) ?? '',
      studentName: data['studentName'] as String?,
      counselorName: data['counselorName'] as String?,
      rated: (data['rated'] as bool?) ?? false,
      ratingValue: (data['ratingValue'] as num?)?.toInt(),
      counselorCancelMessage: data['counselorCancelMessage'] as String?,
      cancelledByRole: data['cancelledByRole'] as String?,
    );
  }
}
