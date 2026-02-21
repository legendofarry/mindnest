import 'package:cloud_firestore/cloud_firestore.dart';

enum MicRequestStatus { pending, approved, denied }

class LiveMicRequest {
  const LiveMicRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String displayName;
  final MicRequestStatus status;
  final DateTime createdAt;

  factory LiveMicRequest.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final statusRaw =
        (data['status'] as String?) ?? MicRequestStatus.pending.name;
    final status = MicRequestStatus.values.firstWhere(
      (value) => value.name == statusRaw,
      orElse: () => MicRequestStatus.pending,
    );

    return LiveMicRequest(
      id: id,
      userId: (data['userId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Member',
      status: status,
      createdAt: parseDate(data['createdAt']),
    );
  }
}
