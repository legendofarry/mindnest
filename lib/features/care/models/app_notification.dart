import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.institutionId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.isRead,
    this.relatedAppointmentId,
    this.relatedId,
  });

  final String id;
  final String userId;
  final String institutionId;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? relatedAppointmentId;
  final String? relatedId;

  factory AppNotification.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return AppNotification(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      institutionId: (data['institutionId'] as String?) ?? '',
      type: (data['type'] as String?) ?? 'general',
      title: (data['title'] as String?) ?? 'Notification',
      body: (data['body'] as String?) ?? '',
      createdAt: parseDate(data['createdAt']),
      isRead: (data['isRead'] as bool?) ?? false,
      relatedAppointmentId: data['relatedAppointmentId'] as String?,
      relatedId: data['relatedId'] as String?,
    );
  }
}
