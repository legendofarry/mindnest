import 'package:cloud_firestore/cloud_firestore.dart';

class LiveComment {
  const LiveComment({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String text;
  final DateTime createdAt;

  factory LiveComment.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return LiveComment(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Member',
      text: (data['text'] as String?) ?? '',
      createdAt: parseDate(data['createdAt']),
    );
  }
}
