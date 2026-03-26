import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/auth_session_manager.dart';
import 'package:mindnest/features/auth/data/windows_google_oauth_flow.dart';
import 'package:mindnest/features/auth/models/app_auth_user.dart';
import 'package:mindnest/firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool get kUseWindowsRestAuth =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

class AppAuthSignInResult {
  const AppAuthSignInResult({required this.user});

  final AppAuthUser user;
}

abstract class AppAuthClient {
  Future<AppAuthUser?> initialize();

  Stream<AppAuthUser?> userChanges();

  AppAuthUser? get currentUser;

  Future<AppAuthSignInResult> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  Future<AppAuthSignInResult> createUserWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  });

  Future<AppAuthSignInResult> signInWithGoogle({
    String? loginHint,
    bool existingAccountsOnly = false,
  });

  Future<void> signOut();

  Future<void> deleteCurrentUser();

  Future<void> sendPasswordResetEmail(String email);

  Future<void> sendEmailVerification();

  Future<void> updatePassword(String newPassword);

  Future<void> updateDisplayName(String displayName);

  Future<AppAuthUser?> reloadCurrentUser();

  Future<String?> getIdToken({bool forceRefresh = false});
}

class FirebaseAppAuthClient implements AppAuthClient {
  FirebaseAppAuthClient(this._auth);

  final fb.FirebaseAuth _auth;

  @override
  Future<AppAuthUser?> initialize() async {
    return _mapUser(_auth.currentUser);
  }

  @override
  Stream<AppAuthUser?> userChanges() {
    return _auth.userChanges().map(_mapUser);
  }

  @override
  AppAuthUser? get currentUser => _mapUser(_auth.currentUser);

  @override
  Future<AppAuthSignInResult> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = _mapUser(credential.user);
    if (user == null) {
      throw Exception('Unable to sign in.');
    }
    return AppAuthSignInResult(user: user);
  }

  @override
  Future<AppAuthSignInResult> createUserWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    if ((displayName ?? '').trim().isNotEmpty) {
      await credential.user?.updateDisplayName(displayName!.trim());
      await credential.user?.reload();
    }
    final user = _mapUser(_auth.currentUser);
    if (user == null) {
      throw Exception('Unable to create user account.');
    }
    return AppAuthSignInResult(user: user);
  }

  @override
  Future<AppAuthSignInResult> signInWithGoogle({
    String? loginHint,
    bool existingAccountsOnly = false,
  }) {
    throw UnsupportedError(
      'Google sign-in should be handled by platform-specific auth flows.',
    );
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  @override
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    await _auth.currentUser?.updateDisplayName(displayName);
    await _auth.currentUser?.reload();
  }

  @override
  Future<AppAuthUser?> reloadCurrentUser() async {
    await _auth.currentUser?.reload();
    return currentUser;
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdToken(forceRefresh);
  }

  AppAuthUser? _mapUser(fb.User? user) {
    if (user == null) {
      return null;
    }
    return AppAuthUser(
      uid: user.uid,
      email: user.email ?? '',
      emailVerified: user.emailVerified,
      displayName: user.displayName,
      phoneNumber: user.phoneNumber,
      creationTime: user.metadata.creationTime?.toUtc(),
    );
  }
}

class WindowsRestAppAuthClient implements AppAuthClient {
  WindowsRestAppAuthClient({
    required http.Client httpClient,
    WindowsGoogleOAuthFlow? googleOAuthFlow,
  }) : _httpClient = httpClient,
       _googleOAuthFlow = googleOAuthFlow ?? WindowsGoogleOAuthFlow();

  static const String _sessionPrefsKey = 'windows.auth_rest_session';
  static const String _identityToolkitHost = 'identitytoolkit.googleapis.com';
  static const String _secureTokenHost = 'securetoken.googleapis.com';

  final http.Client _httpClient;
  final WindowsGoogleOAuthFlow _googleOAuthFlow;
  final StreamController<AppAuthUser?> _authStateController =
      StreamController<AppAuthUser?>.broadcast();

  _WindowsAuthSession? _session;
  bool _initialized = false;

  String get _apiKey => DefaultFirebaseOptions.windows.apiKey;

  @override
  Future<AppAuthUser?> initialize() async {
    if (_initialized) {
      return currentUser;
    }
    if (_session != null) {
      _initialized = true;
      _emit();
      return currentUser;
    }
    _initialized = true;

    final shouldRestore =
        await AuthSessionManager.shouldRestorePersistedSession();
    if (!shouldRestore) {
      await _clearStoredSession();
      _emit();
      return null;
    }

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionPrefsKey);
    if (raw == null || raw.trim().isEmpty) {
      _emit();
      return null;
    }

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      _session = _WindowsAuthSession.fromJson(decoded);
      await _reloadSession(forceRefreshToken: _session!.isExpiringSoon);
    } catch (_) {
      await _clearStoredSession();
    }
    _emit();
    return currentUser;
  }

  @override
  Stream<AppAuthUser?> userChanges() async* {
    if (!_initialized) {
      await initialize();
    }
    yield currentUser;
    yield* _authStateController.stream;
  }

  @override
  AppAuthUser? get currentUser => _session?.user;

  @override
  Future<AppAuthSignInResult> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final response = await _postIdentityToolkit(
      'accounts:signInWithPassword',
      <String, dynamic>{
        'email': email.trim().toLowerCase(),
        'password': password,
        'returnSecureToken': true,
      },
    );
    final session = await _sessionFromAuthPayload(response);
    await _setSession(session);
    return AppAuthSignInResult(user: session.user);
  }

  @override
  Future<AppAuthSignInResult> createUserWithEmailAndPassword({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response =
        await _postIdentityToolkit('accounts:signUp', <String, dynamic>{
          'email': email.trim().toLowerCase(),
          'password': password,
          'returnSecureToken': true,
        });
    var session = await _sessionFromAuthPayload(response);
    await _setSession(session);
    if ((displayName ?? '').trim().isNotEmpty) {
      await updateDisplayName(displayName!.trim());
      session = _session!;
    }
    return AppAuthSignInResult(user: session.user);
  }

  @override
  Future<AppAuthSignInResult> signInWithGoogle({
    String? loginHint,
    bool existingAccountsOnly = false,
  }) async {
    final googleTokens = await _googleOAuthFlow.signIn(loginHint: loginHint);
    if (existingAccountsOnly) {
      final googleEmail = _extractEmailFromIdToken(googleTokens.idToken);
      if (googleEmail.isEmpty) {
        throw Exception(
          'We could not confirm your Google account email. Use email and password or create your account on the web first.',
        );
      }

      final signInMethods = await _fetchSignInMethodsForEmail(googleEmail);
      if (signInMethods.isEmpty) {
        throw Exception(
          'This Google account does not have a MindNest account on Windows yet. Create your account on the web first.',
        );
      }
    }

    final postBody = <String>[
      'providerId=google.com',
      'id_token=${Uri.encodeQueryComponent(googleTokens.idToken)}',
      if ((googleTokens.accessToken ?? '').trim().isNotEmpty)
        'access_token=${Uri.encodeQueryComponent(googleTokens.accessToken!.trim())}',
    ].join('&');
    final response =
        await _postIdentityToolkit('accounts:signInWithIdp', <String, dynamic>{
          'requestUri': 'http://localhost',
          'postBody': postBody,
          'returnSecureToken': true,
          'returnIdpCredential': true,
        });
    final session = await _sessionFromAuthPayload(response);
    await _setSession(session);
    return AppAuthSignInResult(user: session.user);
  }

  @override
  Future<void> signOut() async {
    await _clearStoredSession();
    await AuthSessionManager.clear();
    _emit();
  }

  @override
  Future<void> deleteCurrentUser() async {
    final idToken = await getIdToken(forceRefresh: true);
    if (idToken == null || idToken.isEmpty) {
      return;
    }
    await _postIdentityToolkit('accounts:delete', <String, dynamic>{
      'idToken': idToken,
    });
    await _clearStoredSession();
    _emit();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _postIdentityToolkit('accounts:sendOobCode', <String, dynamic>{
      'requestType': 'PASSWORD_RESET',
      'email': email.trim().toLowerCase(),
    });
  }

  @override
  Future<void> sendEmailVerification() async {
    var idToken = await getIdToken();
    if (idToken == null || idToken.isEmpty) {
      await reloadCurrentUser();
      idToken = await getIdToken(forceRefresh: true);
    }
    if (idToken == null || idToken.isEmpty) {
      throw Exception('You must be logged in.');
    }
    await _postIdentityToolkit('accounts:sendOobCode', <String, dynamic>{
      'requestType': 'VERIFY_EMAIL',
      'idToken': idToken,
    });
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    final session = await _requireSession();
    final response =
        await _postIdentityToolkit('accounts:update', <String, dynamic>{
          'idToken': await _ensureFreshIdToken(session, forceRefresh: true),
          'password': newPassword,
          'returnSecureToken': true,
        });
    final nextSession = await _sessionFromAuthPayload(response);
    await _setSession(nextSession);
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final session = await _requireSession();
    final response =
        await _postIdentityToolkit('accounts:update', <String, dynamic>{
          'idToken': await _ensureFreshIdToken(session),
          'displayName': displayName.trim(),
          'returnSecureToken': true,
        });
    final nextSession = await _sessionFromAuthPayload(response);
    await _setSession(nextSession);
  }

  @override
  Future<AppAuthUser?> reloadCurrentUser() async {
    if (_session == null) {
      return null;
    }
    await _reloadSession(forceRefreshToken: true);
    _emit();
    return currentUser;
  }

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!_initialized) {
      await initialize();
    }
    final session = _session;
    if (session == null) {
      return null;
    }
    return _ensureFreshIdToken(session, forceRefresh: forceRefresh);
  }

  Future<_WindowsAuthSession> _requireSession() async {
    if (!_initialized) {
      await initialize();
    }
    final session = _session;
    if (session == null) {
      throw Exception('You must be logged in.');
    }
    return session;
  }

  Future<String> _ensureFreshIdToken(
    _WindowsAuthSession session, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && !session.isExpiringSoon) {
      return session.idToken;
    }
    await _refreshAccessToken();
    final nextSession = _session;
    if (nextSession == null) {
      throw Exception('You must be logged in.');
    }
    return nextSession.idToken;
  }

  Future<void> _refreshAccessToken() async {
    final session = _session;
    if (session == null) {
      return;
    }
    final response = await _httpClient.post(
      Uri.https(_secureTokenHost, '/v1/token', <String, String>{
        'key': _apiKey,
      }),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': session.refreshToken,
      },
    );
    final body = _decodeJsonMap(response.body);
    _throwIfHttpFailed(response, body);

    final refreshed = session.copyWith(
      idToken: (body['id_token'] as String?) ?? session.idToken,
      refreshToken: (body['refresh_token'] as String?) ?? session.refreshToken,
      expiresAt: DateTime.now().toUtc().add(
        Duration(
          seconds: int.tryParse((body['expires_in'] as String?) ?? '') ?? 3600,
        ),
      ),
    );
    _session = refreshed;
    await _persistSession();
  }

  Future<void> _reloadSession({bool forceRefreshToken = false}) async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (forceRefreshToken || session.isExpiringSoon) {
      await _refreshAccessToken();
    }
    final active = _session;
    if (active == null) {
      return;
    }
    final lookup = await _lookupCurrentUser(active.idToken);
    _session = active.copyWith(user: lookup);
    await _persistSession();
  }

  Future<_WindowsAuthSession> _sessionFromAuthPayload(
    Map<String, dynamic> payload,
  ) async {
    final idToken = (payload['idToken'] as String?)?.trim() ?? '';
    final refreshToken = (payload['refreshToken'] as String?)?.trim() ?? '';
    final uid = (payload['localId'] as String?)?.trim() ?? '';
    if (idToken.isEmpty || refreshToken.isEmpty || uid.isEmpty) {
      throw Exception('Auth response was incomplete.');
    }
    final user = await _lookupCurrentUser(idToken);
    final expiresIn =
        int.tryParse((payload['expiresIn'] as String?) ?? '') ?? 3600;
    return _WindowsAuthSession(
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: expiresIn)),
      user: user,
    );
  }

  Future<AppAuthUser> _lookupCurrentUser(String idToken) async {
    final response = await _postIdentityToolkit(
      'accounts:lookup',
      <String, dynamic>{'idToken': idToken},
    );
    final usersRaw = response['users'];
    if (usersRaw is! List || usersRaw.isEmpty || usersRaw.first is! Map) {
      throw Exception('Unable to load account details.');
    }
    final user = Map<String, dynamic>.from(usersRaw.first as Map);
    final createdAtMs = int.tryParse((user['createdAt'] as String?) ?? '');
    return AppAuthUser(
      uid: (user['localId'] as String?) ?? '',
      email: (user['email'] as String?) ?? '',
      emailVerified: (user['emailVerified'] as bool?) ?? false,
      displayName: (user['displayName'] as String?)?.trim(),
      phoneNumber: (user['phoneNumber'] as String?)?.trim(),
      creationTime: createdAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
    );
  }

  Future<List<String>> _fetchSignInMethodsForEmail(String email) async {
    final response = await _postIdentityToolkit(
      'accounts:createAuthUri',
      <String, dynamic>{
        'identifier': email.trim().toLowerCase(),
        'continueUri': 'http://localhost',
      },
    );

    final methods = <String>{};
    final rawSignInMethods = response['signinMethods'];
    if (rawSignInMethods is List) {
      for (final method in rawSignInMethods) {
        final normalized = method?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) {
          methods.add(normalized);
        }
      }
    }

    final rawProviders = response['allProviders'];
    if (rawProviders is List) {
      for (final provider in rawProviders) {
        final normalized = provider?.toString().trim();
        if (normalized != null && normalized.isNotEmpty) {
          methods.add(normalized);
        }
      }
    }

    return methods.toList(growable: false);
  }

  String _extractEmailFromIdToken(String idToken) {
    try {
      final segments = idToken.split('.');
      if (segments.length < 2) {
        return '';
      }
      final normalized = base64.normalize(segments[1]);
      final payload = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payload);
      if (decoded is! Map) {
        return '';
      }
      final email = decoded['email']?.toString().trim().toLowerCase() ?? '';
      return email;
    } catch (_) {
      return '';
    }
  }

  Future<Map<String, dynamic>> _postIdentityToolkit(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _httpClient.post(
      Uri.https(_identityToolkitHost, '/v1/$path', <String, String>{
        'key': _apiKey,
      }),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final payload = _decodeJsonMap(response.body);
    _throwIfHttpFailed(response, payload);
    return payload;
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw Exception('Unexpected server response.');
  }

  void _throwIfHttpFailed(
    http.Response response,
    Map<String, dynamic> payload,
  ) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final error = payload['error'];
    if (error is Map) {
      final message = (error['message'] as String?) ?? 'Request failed.';
      throw Exception(_friendlyAuthMessage(message));
    }
    throw Exception('Request failed (${response.statusCode}).');
  }

  String _friendlyAuthMessage(String raw) {
    switch (raw.trim()) {
      case 'EMAIL_NOT_FOUND':
      case 'INVALID_LOGIN_CREDENTIALS':
      case 'INVALID_PASSWORD':
        return 'Invalid email or password.';
      case 'EMAIL_EXISTS':
        return 'An account with this email already exists.';
      case 'USER_DISABLED':
        return 'This account has been disabled.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER':
        return 'Too many attempts. Try again later.';
      default:
        return raw.replaceAll('_', ' ').toLowerCase();
    }
  }

  Future<void> _setSession(_WindowsAuthSession session) async {
    _initialized = true;
    _session = session;
    await _persistSession();
    _emit();
  }

  Future<void> _persistSession() async {
    final session = _session;
    final prefs = await SharedPreferences.getInstance();
    if (session == null) {
      await prefs.remove(_sessionPrefsKey);
      return;
    }
    await prefs.setString(_sessionPrefsKey, jsonEncode(session.toJson()));
  }

  Future<void> _clearStoredSession() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionPrefsKey);
  }

  void _emit() {
    if (!_authStateController.isClosed) {
      _authStateController.add(currentUser);
    }
  }
}

class _WindowsAuthSession {
  const _WindowsAuthSession({
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AppAuthUser user;

  bool get isExpiringSoon => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(minutes: 2)),
  );

  _WindowsAuthSession copyWith({
    String? idToken,
    String? refreshToken,
    DateTime? expiresAt,
    AppAuthUser? user,
  }) {
    return _WindowsAuthSession(
      idToken: idToken ?? this.idToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      user: user ?? this.user,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'idToken': idToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toIso8601String(),
      'user': user.toJson(),
    };
  }

  factory _WindowsAuthSession.fromJson(Map<String, dynamic> json) {
    return _WindowsAuthSession(
      idToken: (json['idToken'] as String?) ?? '',
      refreshToken: (json['refreshToken'] as String?) ?? '',
      expiresAt:
          DateTime.tryParse((json['expiresAt'] as String?) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      user: AppAuthUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map),
      ),
    );
  }
}
