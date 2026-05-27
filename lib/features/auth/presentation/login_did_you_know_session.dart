import 'package:shared_preferences/shared_preferences.dart';

class LoginDidYouKnowSession {
  LoginDidYouKnowSession._();

  static const _lastFactIdKey = 'login.did_you_know.last_fact_id';

  static String? _activeFactId;

  static String? get activeFactId {
    final normalized = _activeFactId?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  static void setActiveFact(String factId) {
    final normalized = factId.trim();
    _activeFactId = normalized.isEmpty ? null : normalized;
  }

  static void clearActiveFact() {
    _activeFactId = null;
  }

  static Future<String?> readLastFactId() async {
    final preferences = await SharedPreferences.getInstance();
    final normalized = (preferences.getString(_lastFactIdKey) ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }

  static Future<void> persistLastFactId(String factId) async {
    final normalized = factId.trim();
    if (normalized.isEmpty) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastFactIdKey, normalized);
  }
}
