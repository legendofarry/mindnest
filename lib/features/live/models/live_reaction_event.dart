import 'package:cloud_firestore/cloud_firestore.dart';

class LiveReactionEvent {
  const LiveReactionEvent({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.emoji,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final String emoji;
  final DateTime createdAt;

  factory LiveReactionEvent.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    return LiveReactionEvent(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Member',
      emoji: (data['emoji'] as String?) ?? '??',
      createdAt: parseDate(data['createdAt']),
    );
  }
}
