import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

class PasskeyRepository {
  PasskeyRepository({
    required AppAuthClient auth,
    required http.Client httpClient,
    PasskeyAuthenticator? authenticator,
  }) : _auth = auth,
       _httpClient = httpClient,
       _authenticator =
           authenticator ?? PasskeyAuthenticator(debugMode: kDebugMode);

  static const String _passkeysBaseUrlFromDefine = String.fromEnvironment(
    'PASSKEYS_BASE_URL',
    defaultValue: '',
  );
  static const String _pushDispatchEndpointFromDefine = String.fromEnvironment(
    'PUSH_DISPATCH_ENDPOINT',
    defaultValue: '',
  );
  static const String _pushDispatchEndpointFromSource =
      'https://mindnest-0o6x.onrender.com/push/dispatch';
  static const String _passkeysBaseUrlFromSource =
      'https://mindnest-0o6x.onrender.com';

  final AppAuthClient _auth;
  final http.Client _httpClient;
  final PasskeyAuthenticator _authenticator;

  String get _baseUrl {
    final configured = _passkeysBaseUrlFromDefine.trim();
    if (configured.isNotEmpty) {
      return configured;
    }

    final derivedSource = _pushDispatchEndpointFromDefine.trim().isNotEmpty
        ? _pushDispatchEndpointFromDefine.trim()
        : _pushDispatchEndpointFromSource;
    try {
      final origin = Uri.parse(derivedSource).origin.trim();
      if (origin.isNotEmpty) {
        return origin;
      }
    } catch (_) {}

    return _passkeysBaseUrlFromSource;
  }

  Future<bool> isSupported() async {
    try {
      final availability = await _authenticator.getAvailability().web();
      return availability.hasPasskeySupport;
    } catch (_) {
      return false;
    }
  }

  Future<PasskeySignInResult> signIn() async {
    final start = await _postJson('/passkeys/login/start');
    final sessionId = _requiredString(start, 'sessionId');
    final options = _requiredMap(start, 'options');
    final request = AuthenticateRequestType.fromJsonString(jsonEncode(options));
    final platformResponse = await _authenticator.authenticate(request);

    final finish = await _postJson(
      '/passkeys/login/finish',
      body: <String, dynamic>{
        'sessionId': sessionId,
        'response': platformResponse.toJson(),
      },
    );

    if (finish['verified'] != true) {
      throw Exception('Passkey sign-in could not be verified.');
    }

    final customToken = _requiredString(finish, 'customToken');
    final userId = _requiredString(finish, 'userId');
    final credentialId = _optionalString(finish, 'credentialId');
    return PasskeySignInResult(
      customToken: customToken,
      userId: userId,
      credentialId: credentialId.isEmpty ? null : credentialId,
    );
  }

  Future<PasskeyRegistrationResult> enrollCurrentUser() async {
    final start = await _postJson(
      '/passkeys/register/start',
      authRequired: true,
    );
    final sessionId = _requiredString(start, 'sessionId');
    final options = _requiredMap(start, 'options');
    final request = RegisterRequestType.fromJsonString(jsonEncode(options));
    final platformResponse = await _authenticator.register(request);

    final finish = await _postJson(
      '/passkeys/register/finish',
      body: <String, dynamic>{
        'sessionId': sessionId,
        'response': platformResponse.toJson(),
      },
      authRequired: true,
    );

    if (finish['verified'] != true) {
      throw Exception('Passkey registration could not be verified.');
    }

    final credentialId = _requiredString(finish, 'credentialId');
    final userId = _requiredString(finish, 'userId');
    return PasskeyRegistrationResult(
      credentialId: credentialId,
      userId: userId,
    );
  }

  Future<List<PasskeyCredentialRecord>> listMyPasskeys() async {
    final payload = await _getJson('/passkeys/me', authRequired: true);
    final rawPasskeys = payload['passkeys'];
    if (rawPasskeys is! List) {
      return const <PasskeyCredentialRecord>[];
    }

    final passkeys = <PasskeyCredentialRecord>[];
    for (final raw in rawPasskeys) {
      if (raw is Map) {
        passkeys.add(
          PasskeyCredentialRecord.fromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          ),
        );
      }
    }
    return passkeys;
  }

  Future<int> deleteAllMyPasskeys() async {
    final payload = await _deleteJson('/passkeys/me', authRequired: true);
    return (payload['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<bool> deleteMyPasskey(String credentialId) async {
    final trimmed = credentialId.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final payload = await _deleteJson(
      '/passkeys/me/$trimmed',
      authRequired: true,
    );
    return (payload['deleted'] as num?)?.toInt() == 1;
  }

  Future<String?> currentAuthToken() async {
    return _auth.getIdToken(forceRefresh: true);
  }

  Future<Map<String, dynamic>> _postJson(
    String path, {
    Map<String, dynamic>? body,
    bool authRequired = false,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authRequired) {
      headers.addAll(await _authorizedHeaders());
    }
    final response = await _httpClient.post(
      _uri(path),
      headers: headers,
      body: jsonEncode(body ?? const <String, dynamic>{}),
    );
    return _decodeAndValidate(response);
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    bool authRequired = false,
  }) async {
    final headers = <String, String>{};
    if (authRequired) {
      headers.addAll(await _authorizedHeaders());
    }
    final response = await _httpClient.get(_uri(path), headers: headers);
    return _decodeAndValidate(response);
  }

  Future<Map<String, dynamic>> _deleteJson(
    String path, {
    bool authRequired = false,
  }) async {
    final headers = <String, String>{};
    if (authRequired) {
      headers.addAll(await _authorizedHeaders());
    }
    final response = await _httpClient.delete(_uri(path), headers: headers);
    return _decodeAndValidate(response);
  }

  Future<Map<String, String>> _authorizedHeaders() async {
    final token = (await _auth.getIdToken(forceRefresh: true))?.trim() ?? '';
    if (token.isEmpty) {
      throw Exception('You must be logged in.');
    }

    return <String, String>{'Authorization': 'Bearer $token'};
  }

  Uri _uri(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse(_baseUrl).resolve(normalizedPath);
  }

  Map<String, dynamic> _decodeAndValidate(http.Response response) {
    final decoded = _decodeJsonMap(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final error = decoded['error'];
    if (error is String && error.trim().isNotEmpty) {
      throw Exception(error.trim());
    }
    throw Exception('Request failed (${response.statusCode}).');
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    throw Exception('Unexpected server response.');
  }

  Map<String, dynamic> _requiredMap(Map<String, dynamic> payload, String key) {
    final value = payload[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((nestedKey, nestedValue) {
        return MapEntry(nestedKey.toString(), nestedValue);
      });
    }
    throw Exception('Missing "$key" in server response.');
  }

  String _requiredString(Map<String, dynamic> payload, String key) {
    final value = _optionalString(payload, key);
    if (value.isEmpty) {
      throw Exception('Missing "$key" in server response.');
    }
    return value;
  }

  String _optionalString(Map<String, dynamic> payload, String key) {
    return (payload[key]?.toString().trim() ?? '');
  }
}

class PasskeySignInResult {
  const PasskeySignInResult({
    required this.customToken,
    required this.userId,
    this.credentialId,
  });

  final String customToken;
  final String userId;
  final String? credentialId;
}

class PasskeyRegistrationResult {
  const PasskeyRegistrationResult({
    required this.credentialId,
    required this.userId,
  });

  final String credentialId;
  final String userId;
}

class PasskeyCredentialRecord {
  const PasskeyCredentialRecord({
    required this.credentialId,
    required this.userId,
    required this.userEmail,
    required this.userLabel,
    required this.counter,
    required this.transports,
    required this.deviceType,
    required this.backedUp,
    required this.createdAt,
    required this.updatedAt,
    required this.lastUsedAt,
  });

  final String credentialId;
  final String userId;
  final String userEmail;
  final String userLabel;
  final int counter;
  final List<String> transports;
  final String deviceType;
  final bool backedUp;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastUsedAt;

  String get displayLabel {
    final label = userLabel.trim();
    if (label.isNotEmpty) {
      return label;
    }
    final email = userEmail.trim();
    if (email.isNotEmpty) {
      return email;
    }
    return 'Passkey';
  }

  String get detailLabel {
    final parts = <String>[];
    final type = deviceType.trim();
    if (type.isNotEmpty) {
      parts.add(type);
    }
    if (backedUp) {
      parts.add('backed up');
    }
    if (transports.isNotEmpty) {
      parts.add(transports.join(' / '));
    }
    return parts.isEmpty ? 'No extra details' : parts.join(' / ');
  }

  factory PasskeyCredentialRecord.fromJson(Map<String, dynamic> json) {
    return PasskeyCredentialRecord(
      credentialId: (json['credentialId'] as String?) ?? '',
      userId: (json['userId'] as String?) ?? '',
      userEmail: (json['userEmail'] as String?) ?? '',
      userLabel: (json['userLabel'] as String?) ?? '',
      counter: (json['counter'] as num?)?.toInt() ?? 0,
      transports: _toStringList(json['transports']),
      deviceType: (json['deviceType'] as String?) ?? '',
      backedUp: (json['backedUp'] as bool?) ?? false,
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
      lastUsedAt: _parseDate(json['lastUsedAt']),
    );
  }

  static List<String> _toStringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toUtc();
  }
}
