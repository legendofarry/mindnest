import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthSessionManager {
  AuthSessionManager._();

  static const String _modeKey = 'auth_session_mode';
  static const String _loginAtKey = 'auth_session_login_at_ms';
  static const String _modeRemember = 'remember_14d';
  static const String _modeSession = 'session_only';
  static const Duration rememberDuration = Duration(days: 14);

  static Future<void> markLogin({required bool rememberMe}) async {
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString(_modeKey, _modeRemember);
      await prefs.setInt(_loginAtKey, DateTime.now().millisecondsSinceEpoch);
      return;
    }

    await prefs.setString(_modeKey, _modeSession);
    await prefs.remove(_loginAtKey);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_modeKey);
    await prefs.remove(_loginAtKey);
  }

  static Future<void> enforceStartupPolicy(FirebaseAuth auth) async {
    final user = auth.currentUser;
    if (user == null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(_modeKey);

    if (mode == _modeSession) {
      await auth.signOut();
      await clear();
      return;
    }

    if (mode == _modeRemember) {
      final loginAtMs = prefs.getInt(_loginAtKey);
      if (loginAtMs == null) {
        await auth.signOut();
        await clear();
        return;
      }
      final loggedAt = DateTime.fromMillisecondsSinceEpoch(loginAtMs);
      final expired = DateTime.now().difference(loggedAt) > rememberDuration;
      if (expired) {
        await auth.signOut();
        await clear();
      }
    }
  }
}
