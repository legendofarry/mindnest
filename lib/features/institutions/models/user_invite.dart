import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

enum UserInviteStatus { pending, accepted, declined, revoked, unknown }

extension UserInviteStatusX on UserInviteStatus {
  static UserInviteStatus fromString(String? value) {
    return UserInviteStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => UserInviteStatus.unknown,
    );
  }
}

class UserInvite {
  const UserInvite({
    required this.id,
    required this.institutionId,
    required this.institutionName,
    required this.inviteeUid,
    required this.inviteePhoneE164,
    required this.invitedEmail,
    required this.invitedName,
    required this.intendedRole,
    required this.status,
    this.expiresAt,
    this.revokedAt,
    this.invitedBy,
  });

  final String id;
  final String institutionId;
  final String institutionName;
  final String inviteeUid;
  final String inviteePhoneE164;
  final String invitedEmail;
  final String invitedName;
  final UserRole intendedRole;
  final UserInviteStatus status;
  final DateTime? expiresAt;
  final DateTime? revokedAt;
  final String? invitedBy;

  bool get isExpired {
    final expires = expiresAt;
    if (expires == null) {
      return false;
    }
    return !expires.toUtc().isAfter(DateTime.now().toUtc());
  }

  bool get isPending => status == UserInviteStatus.pending && !isExpired;

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    return null;
  }

  factory UserInvite.fromMap(String id, Map<String, dynamic> data) {
    final intendedRole = UserRole.values.firstWhere(
      (role) => role.name == (data['intendedRole'] as String?),
      orElse: () => UserRole.other,
    );

    return UserInvite(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      institutionName: (data['institutionName'] as String?) ?? '',
      inviteeUid: (data['inviteeUid'] as String?) ?? '',
      inviteePhoneE164: (data['inviteePhoneE164'] as String?) ?? '',
      invitedEmail: (data['invitedEmail'] as String?) ?? '',
      invitedName: (data['invitedName'] as String?) ?? '',
      intendedRole: intendedRole,
      status: UserInviteStatusX.fromString(data['status'] as String?),
      expiresAt: _asDateTime(data['expiresAt']),
      revokedAt: _asDateTime(data['revokedAt']),
      invitedBy: data['invitedBy'] as String?,
    );
  }
}
