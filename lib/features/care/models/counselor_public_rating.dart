import 'package:cloud_firestore/cloud_firestore.dart';

class CounselorPublicRating {
  const CounselorPublicRating({
    required this.id,
    required this.appointmentId,
    required this.institutionId,
    required this.counselorId,
    required this.studentId,
    required this.rating,
    required this.feedback,
    required this.createdAt,
  });

  final String id;
  final String appointmentId;
  final String institutionId;
  final String counselorId;
  final String studentId;
  final int rating;
  final String feedback;
  final DateTime createdAt;

  factory CounselorPublicRating.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return CounselorPublicRating(
      id: id,
      appointmentId: (data['appointmentId'] as String?) ?? '',
      institutionId: (data['institutionId'] as String?) ?? '',
      counselorId: (data['counselorId'] as String?) ?? '',
      studentId: (data['studentId'] as String?) ?? '',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      feedback: (data['feedback'] as String?) ?? '',
      createdAt: parseDate(data['createdAt']),
    );
  }
}
