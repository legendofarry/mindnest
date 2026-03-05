import 'package:flutter_test/flutter_test.dart';
import 'package:mindnest/core/routes/app_router.dart';

void main() {
  test('parses invite from query params', () {
    final uri = Uri.parse(
      'https://mindnestke.netlify.app/invite-accept?inviteId=abc&invitedEmail=foo@bar.com',
    );
    final res = AppRoute.inviteQueryFromUri(uri);
    expect(res['inviteId'], 'abc');
    expect(res['invitedEmail'], 'foo@bar.com');
  });

  test('parses invite from fragment without leading ?', () {
    final uri = Uri.parse(
      'https://mindnestke.netlify.app/invite-accept#inviteId=abc&invitedEmail=foo@bar.com',
    );
    final res = AppRoute.inviteQueryFromUri(uri);
    expect(res['inviteId'], 'abc');
    expect(res['invitedEmail'], 'foo@bar.com');
  });

  test('parses invite from fragment with leading ?', () {
    final uri = Uri.parse(
      'https://mindnestke.netlify.app/invite-accept#?inviteId=abc&invitedEmail=foo@bar.com',
    );
    final res = AppRoute.inviteQueryFromUri(uri);
    expect(res['inviteId'], 'abc');
    expect(res['invitedEmail'], 'foo@bar.com');
  });
}
