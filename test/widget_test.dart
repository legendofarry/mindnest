import 'package:flutter_test/flutter_test.dart';
import 'package:mindnest/features/auth/models/user_profile.dart';

void main() {
  test('UserProfile toMap/fromMap roundtrip', () {
    const profile = UserProfile(
      id: 'uid_1',
      email: 'test@example.com',
      name: 'Test User',
      role: UserRole.student,
      institutionId: 'inst_1',
      institutionName: 'MindNest University',
    );

    final mapped = profile.toMap();
    final rebuilt = UserProfile.fromMap('uid_1', mapped);

    expect(rebuilt.id, 'uid_1');
    expect(rebuilt.email, 'test@example.com');
    expect(rebuilt.role, UserRole.student);
    expect(rebuilt.institutionId, 'inst_1');
  });
}
