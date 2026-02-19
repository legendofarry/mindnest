import 'package:cloud_firestore/cloud_firestore.dart';

class CareGoal {
  const CareGoal({
    required this.id,
    required this.studentId,
    required this.counselorId,
    required this.institutionId,
    required this.title,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.completedAt,
    this.sourceAppointmentId,
  });

  final String id;
  final String studentId;
  final String counselorId;
  final String institutionId;
  final String title;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? sourceAppointmentId;

  bool get isCompleted => status == 'completed';

  factory CareGoal.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return null;
    }

    return CareGoal(
      id: id,
      studentId: (data['studentId'] as String?) ?? '',
      counselorId: (data['counselorId'] as String?) ?? '',
      institutionId: (data['institutionId'] as String?) ?? '',
      title: (data['title'] as String?) ?? 'Goal',
      status: (data['status'] as String?) ?? 'active',
      createdAt:
          parseDate(data['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: parseDate(data['updatedAt']),
      completedAt: parseDate(data['completedAt']),
      sourceAppointmentId: data['sourceAppointmentId'] as String?,
    );
  }
}
