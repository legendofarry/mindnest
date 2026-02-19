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
    required this.invitedEmail,
    required this.invitedName,
    required this.intendedRole,
    required this.status,
  });

  final String id;
  final String institutionId;
  final String institutionName;
  final String invitedEmail;
  final String invitedName;
  final UserRole intendedRole;
  final UserInviteStatus status;

  bool get isPending => status == UserInviteStatus.pending;

  factory UserInvite.fromMap(String id, Map<String, dynamic> data) {
    final intendedRole = UserRole.values.firstWhere(
      (role) => role.name == (data['intendedRole'] as String?),
      orElse: () => UserRole.other,
    );

    return UserInvite(
      id: id,
      institutionId: (data['institutionId'] as String?) ?? '',
      institutionName: (data['institutionName'] as String?) ?? '',
      invitedEmail: (data['invitedEmail'] as String?) ?? '',
      invitedName: (data['invitedName'] as String?) ?? '',
      intendedRole: intendedRole,
      status: UserInviteStatusX.fromString(data['status'] as String?),
    );
  }
}
