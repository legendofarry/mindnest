import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

enum LiveSessionStatus { live, paused, ended }

class LiveSession {
  const LiveSession({
    required this.id,
    required this.institutionId,
    required this.createdBy,
    required this.hostName,
    required this.hostRole,
    required this.title,
    required this.description,
    required this.status,
    required this.allowedRoles,
    required this.maxGuests,
    required this.likeCount,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String institutionId;
  final String createdBy;
  final String hostName;
  final UserRole hostRole;
  final String title;
  final String description;
  final LiveSessionStatus status;
  final List<UserRole> allowedRoles;
  final int maxGuests;
  final int likeCount;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;

  bool get isActive =>
      status == LiveSessionStatus.live || status == LiveSessionStatus.paused;

  bool canRoleJoin(UserRole role) {
    return allowedRoles.contains(role);
  }

  factory LiveSession.fromMap(String id, Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    DateTime? parseNullableDate(dynamic raw) {
      if (raw == null) {
        return null;
      }
      return parseDate(raw);
    }

    final rawStatus =
        (data['status'] as String?) ?? LiveSessionStatus.live.name;
    final status = LiveSessionStatus.values.firstWhere(
      (value) => value.name == rawStatus,
      orElse: () => LiveSessionStatus.live,
    );

    final rawRole = (data['hostRole'] as String?) ?? UserRole.other.name;
    final hostRole = UserRole.values.firstWhere(
      (value) => value.name == rawRole,
      orElse: () => UserRole.other,
    );

    final rawAllowed = data['allowedRoles'];
    final allowedRoles = <UserRole>[];
    if (rawAllowed is List) {
      for (final role in rawAllowed) {
        if (role is String) {
          final parsed = UserRole.values.firstWhere(
            (value) => value.name == role,
            orElse: () => UserRole.other,
          );
          if (parsed != UserRole.other) {
            allowedRoles.add(parsed);
          }
        }
      }
    }

    return LiveSession(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      createdBy: (data['createdBy'] as String?) ?? '',
      hostName: (data['hostName'] as String?) ?? 'Host',
      hostRole: hostRole,
      title: (data['title'] as String?) ?? 'Untitled Live',
      description: (data['description'] as String?) ?? '',
      status: status,
      allowedRoles: allowedRoles,
      maxGuests: (data['maxGuests'] as num?)?.toInt() ?? 20,
      likeCount: (data['likeCount'] as num?)?.toInt() ?? 0,
      createdAt: parseDate(data['createdAt']),
      startedAt: parseNullableDate(data['startedAt']),
      endedAt: parseNullableDate(data['endedAt']),
    );
  }
}
