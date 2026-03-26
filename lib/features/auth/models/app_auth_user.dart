class AppAuthUser {
  const AppAuthUser({
    required this.uid,
    required this.email,
    required this.emailVerified,
    this.displayName,
    this.phoneNumber,
    this.creationTime,
  });

  final String uid;
  final String email;
  final bool emailVerified;
  final String? displayName;
  final String? phoneNumber;
  final DateTime? creationTime;

  AppAuthUser copyWith({
    String? uid,
    String? email,
    bool? emailVerified,
    String? displayName,
    String? phoneNumber,
    DateTime? creationTime,
  }) {
    return AppAuthUser(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      creationTime: creationTime ?? this.creationTime,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'uid': uid,
      'email': email,
      'emailVerified': emailVerified,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'creationTime': creationTime?.toIso8601String(),
    };
  }

  factory AppAuthUser.fromJson(Map<String, dynamic> json) {
    final creationTimeRaw = json['creationTime'] as String?;
    return AppAuthUser(
      uid: (json['uid'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      emailVerified: (json['emailVerified'] as bool?) ?? false,
      displayName: json['displayName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      creationTime: creationTimeRaw == null || creationTimeRaw.isEmpty
          ? null
          : DateTime.tryParse(creationTimeRaw)?.toUtc(),
    );
  }
}
