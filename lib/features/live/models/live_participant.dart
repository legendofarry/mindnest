import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

enum LiveParticipantKind { host, guest, listener }

class LiveParticipant {
  const LiveParticipant({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.kind,
    required this.canSpeak,
    required this.micEnabled,
    required this.mutedByHost,
    required this.joinedAt,
    required this.lastSeenAt,
    required this.removed,
  });

  final String userId;
  final String displayName;
  final UserRole role;
  final LiveParticipantKind kind;
  final bool canSpeak;
  final bool micEnabled;
  final bool mutedByHost;
  final DateTime joinedAt;
  final DateTime lastSeenAt;
  final bool removed;

  bool get isHost => kind == LiveParticipantKind.host;
  bool get isGuest => kind == LiveParticipantKind.guest;

  factory LiveParticipant.fromMap(Map<String, dynamic> data) {
    DateTime parseDate(dynamic raw) {
      if (raw is Timestamp) {
        return raw.toDate();
      }
      if (raw is DateTime) {
        return raw;
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final roleRaw = (data['role'] as String?) ?? UserRole.other.name;
    final role = UserRole.values.firstWhere(
      (value) => value.name == roleRaw,
      orElse: () => UserRole.other,
    );

    final kindRaw =
        (data['kind'] as String?) ?? LiveParticipantKind.listener.name;
    final kind = LiveParticipantKind.values.firstWhere(
      (value) => value.name == kindRaw,
      orElse: () => LiveParticipantKind.listener,
    );

    return LiveParticipant(
      userId: (data['userId'] as String?) ?? '',
      displayName: (data['displayName'] as String?) ?? 'Member',
      role: role,
      kind: kind,
      canSpeak: (data['canSpeak'] as bool?) ?? false,
      micEnabled: (data['micEnabled'] as bool?) ?? false,
      mutedByHost: (data['mutedByHost'] as bool?) ?? false,
      joinedAt: parseDate(data['joinedAt']),
      lastSeenAt: parseDate(data['lastSeenAt']),
      removed: (data['removed'] as bool?) ?? false,
    );
  }
}
