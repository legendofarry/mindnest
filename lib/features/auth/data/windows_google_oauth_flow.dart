import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class WindowsGoogleOAuthFlow {
  static const String _clientIdFromDefine = String.fromEnvironment(
    'GOOGLE_WINDOWS_CLIENT_ID',
  );
  static const String _clientSecretFromDefine = String.fromEnvironment(
    'GOOGLE_WINDOWS_CLIENT_SECRET',
  );

  // Source-file fallback for local/dev use when --dart-define is omitted.
  // Client IDs are public and safe to ship in desktop apps.
  static const String _clientIdFallback = '';
  // Desktop app client secrets are not able to protect a native app in the same
  // way a server secret can, so we keep the local fallback here for the Windows
  // desktop OAuth roundtrip.
  static const String _clientSecretFallback = '';

  static const Duration _callbackTimeout = Duration(minutes: 5);
  static const String _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String _authorizationHost = 'accounts.google.com';
  static const String _authorizationPath = '/o/oauth2/v2/auth';

  String get _clientId {
    if (_clientIdFromDefine.trim().isNotEmpty) {
      return _clientIdFromDefine.trim();
    }
    return _clientIdFallback.trim();
  }

  String get _clientSecret {
    if (_clientSecretFromDefine.trim().isNotEmpty) {
      return _clientSecretFromDefine.trim();
    }
    return _clientSecretFallback.trim();
  }

  Future<WindowsGoogleOAuthTokens> signIn({String? loginHint}) async {
    if (_clientId.isEmpty) {
      throw Exception(
        'Google sign-in for Windows is not configured. Add a desktop OAuth client ID with --dart-define=GOOGLE_WINDOWS_CLIENT_ID=your_client_id.apps.googleusercontent.com.',
      );
    }

    final callbackServer = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final redirectUri = Uri(
      scheme: 'http',
      host: 'localhost',
      port: callbackServer.port,
    );

    final state = _createRandomUrlSafeValue(length: 32);
    final codeVerifier = _createRandomUrlSafeValue(length: 64);
    final codeChallenge = _createCodeChallenge(codeVerifier);

    final callbackCompleter = Completer<Uri>();
    late final StreamSubscription<HttpRequest> callbackSubscription;
    var callbackServerClosed = false;

    Future<void> shutdownCallbackServer() async {
      if (callbackServerClosed) {
        return;
      }
      callbackServerClosed = true;
      await callbackSubscription.cancel().catchError((_) {});
      await callbackServer.close(force: true).catchError((_) {});
    }

    callbackSubscription = callbackServer.listen((request) async {
      final callbackUri = request.requestedUri;
      final query = callbackUri.queryParameters;
      final hasError = query.containsKey('error');
      final pageHtml = hasError ? _errorPageHtml : _successPageHtml;

      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.html;
      request.response.write(pageHtml);
      await request.response.close();

      if (!callbackCompleter.isCompleted) {
        callbackCompleter.complete(callbackUri);
      }

      await shutdownCallbackServer();
    });

    try {
      final authUri = Uri.https(_authorizationHost, _authorizationPath, {
        'client_id': _clientId,
        'redirect_uri': redirectUri.toString(),
        'response_type': 'code',
        'scope': 'openid email profile',
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        'access_type': 'offline',
        'prompt': 'select_account',
        if ((loginHint ?? '').trim().isNotEmpty)
          'login_hint': loginHint!.trim(),
      });

      final launched = await launchUrl(
        authUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw Exception('Unable to open the browser for Google sign-in.');
      }

      final callbackUri = await callbackCompleter.future.timeout(
        _callbackTimeout,
      );
      final query = callbackUri.queryParameters;
      final returnedState = query['state'] ?? '';
      if (returnedState != state) {
        throw Exception(
          'Google sign-in was cancelled or could not be verified.',
        );
      }

      final oauthError = query['error'];
      if (oauthError != null && oauthError.isNotEmpty) {
        final errorDescription = query['error_description'];
        final detail = (errorDescription ?? oauthError).replaceAll('+', ' ');
        throw Exception('Google sign-in failed: $detail');
      }

      final code = query['code'] ?? '';
      if (code.isEmpty) {
        throw Exception('Google sign-in did not return an authorization code.');
      }

      return _exchangeCodeForTokens(
        code: code,
        redirectUri: redirectUri,
        codeVerifier: codeVerifier,
      );
    } on TimeoutException {
      throw Exception('Google sign-in timed out. Please try again.');
    } finally {
      await shutdownCallbackServer();
    }
  }

  Future<WindowsGoogleOAuthTokens> _exchangeCodeForTokens({
    required String code,
    required Uri redirectUri,
    required String codeVerifier,
  }) async {
    final response = await http.post(
      Uri.parse(_tokenEndpoint),
      headers: const <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: <String, String>{
        'client_id': _clientId,
        if (_clientSecret.isNotEmpty) 'client_secret': _clientSecret,
        'code': code,
        'code_verifier': codeVerifier,
        'grant_type': 'authorization_code',
        'redirect_uri': redirectUri.toString(),
      },
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = (body['error'] as String?)?.trim() ?? 'unknown_error';
      final description =
          (body['error_description'] as String?)?.trim() ?? 'Please try again.';
      throw Exception('Google sign-in failed: $error ($description)');
    }

    final idToken = (body['id_token'] as String?)?.trim() ?? '';
    final accessToken = (body['access_token'] as String?)?.trim();
    if (idToken.isEmpty) {
      throw Exception('Google sign-in did not return an ID token.');
    }

    return WindowsGoogleOAuthTokens(
      idToken: idToken,
      accessToken: accessToken?.isEmpty ?? true ? null : accessToken,
    );
  }

  String _createRandomUrlSafeValue({required int length}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String _createCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}

class WindowsGoogleOAuthTokens {
  const WindowsGoogleOAuthTokens({required this.idToken, this.accessToken});

  final String idToken;
  final String? accessToken;
}

const String _successPageHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>MindNest Sign-In</title>
    <style>
      body { font-family: Arial, sans-serif; background: #f7fbfc; color: #0f172a; display: grid; place-items: center; min-height: 100vh; margin: 0; }
      .card { background: #ffffff; border: 1px solid #bee9e4; border-radius: 20px; padding: 28px 32px; max-width: 460px; box-shadow: 0 18px 36px rgba(15, 23, 42, 0.08); }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { margin: 0; font-size: 16px; line-height: 1.5; color: #4c607a; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Google sign-in complete</h1>
      <p>You can close this browser window and return to MindNest.</p>
    </div>
  </body>
</html>
''';

const String _errorPageHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>MindNest Sign-In</title>
    <style>
      body { font-family: Arial, sans-serif; background: #fff7f7; color: #7f1d1d; display: grid; place-items: center; min-height: 100vh; margin: 0; }
      .card { background: #ffffff; border: 1px solid #fecaca; border-radius: 20px; padding: 28px 32px; max-width: 460px; box-shadow: 0 18px 36px rgba(127, 29, 29, 0.08); }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { margin: 0; font-size: 16px; line-height: 1.5; color: #991b1b; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Google sign-in was not completed</h1>
      <p>You can close this browser window and return to MindNest.</p>
    </div>
  </body>
</html>
''';
