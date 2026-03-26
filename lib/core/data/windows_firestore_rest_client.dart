import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mindnest/features/auth/data/app_auth_client.dart';
import 'package:mindnest/firebase_options.dart';

class WindowsFirestoreDocument {
  const WindowsFirestoreDocument({
    required this.id,
    required this.path,
    required this.data,
  });

  final String id;
  final String path;
  final Map<String, dynamic> data;
}

class WindowsFirestoreFieldFilter {
  const WindowsFirestoreFieldFilter.equal(this.fieldPath, this.value)
    : op = 'EQUAL';

  const WindowsFirestoreFieldFilter.inList(this.fieldPath, this.value)
    : op = 'IN';

  const WindowsFirestoreFieldFilter.arrayContains(this.fieldPath, this.value)
    : op = 'ARRAY_CONTAINS';

  const WindowsFirestoreFieldFilter.arrayContainsAny(this.fieldPath, this.value)
    : op = 'ARRAY_CONTAINS_ANY';

  const WindowsFirestoreFieldFilter.lessThan(this.fieldPath, this.value)
    : op = 'LESS_THAN';

  const WindowsFirestoreFieldFilter.lessThanOrEqual(this.fieldPath, this.value)
    : op = 'LESS_THAN_OR_EQUAL';

  const WindowsFirestoreFieldFilter.greaterThan(this.fieldPath, this.value)
    : op = 'GREATER_THAN';

  const WindowsFirestoreFieldFilter.greaterThanOrEqual(
    this.fieldPath,
    this.value,
  ) : op = 'GREATER_THAN_OR_EQUAL';

  final String fieldPath;
  final String op;
  final Object? value;
}

class WindowsFirestoreOrderBy {
  const WindowsFirestoreOrderBy(this.fieldPath, {this.descending = false});

  final String fieldPath;
  final bool descending;
}

class WindowsFirestoreRestClient {
  WindowsFirestoreRestClient({
    required AppAuthClient authClient,
    required http.Client httpClient,
  }) : _authClient = authClient,
       _httpClient = httpClient;

  final AppAuthClient _authClient;
  final http.Client _httpClient;

  static const String _host = 'firestore.googleapis.com';

  String get _projectId => DefaultFirebaseOptions.windows.projectId;
  String get _apiKey => DefaultFirebaseOptions.windows.apiKey;

  String get _documentsRoot =>
      '/v1/projects/$_projectId/databases/(default)/documents';

  Future<WindowsFirestoreDocument?> getDocument(
    String documentPath, {
    bool allowUnauthenticated = false,
  }) async {
    final trimmedPath = _trimmedPath(documentPath);
    if (trimmedPath.isEmpty) {
      return null;
    }
    final uri = _buildUri(
      '$_documentsRoot/$trimmedPath',
      allowUnauthenticated: allowUnauthenticated,
    );
    final response = await _sendRequest(
      (headers) => _httpClient.get(uri, headers: headers),
      allowUnauthenticated: allowUnauthenticated,
    );
    if (response.statusCode == 404) {
      return null;
    }
    final payload = _decodeJsonMap(response.body);
    _throwIfFailed(response, payload);
    return _decodeDocument(payload);
  }

  Future<List<WindowsFirestoreDocument>> queryCollection({
    required String collectionId,
    String? parentPath,
    List<WindowsFirestoreFieldFilter> filters =
        const <WindowsFirestoreFieldFilter>[],
    List<WindowsFirestoreOrderBy> orderBy = const <WindowsFirestoreOrderBy>[],
    int? limit,
    bool allDescendants = false,
    bool allowUnauthenticated = false,
  }) async {
    final trimmedCollectionId = collectionId.trim();
    if (trimmedCollectionId.isEmpty) {
      return const <WindowsFirestoreDocument>[];
    }
    final trimmedParent = _trimmedPath(parentPath);
    final endpointPath = trimmedParent.isEmpty
        ? '$_documentsRoot:runQuery'
        : '$_documentsRoot/$trimmedParent:runQuery';
    final uri = _buildUri(
      endpointPath,
      allowUnauthenticated: allowUnauthenticated,
    );
    final body = <String, dynamic>{
      'structuredQuery': <String, dynamic>{
        'from': <Map<String, dynamic>>[
          <String, dynamic>{
            'collectionId': trimmedCollectionId,
            'allDescendants': allDescendants,
          },
        ],
        if (filters.isNotEmpty)
          'where': filters.length == 1
              ? _encodeFieldFilter(filters.first)
              : <String, dynamic>{
                  'compositeFilter': <String, dynamic>{
                    'op': 'AND',
                    'filters': filters.map(_encodeFieldFilter).toList(),
                  },
                },
        if (orderBy.isNotEmpty)
          'orderBy': orderBy
              .map(
                (item) => <String, dynamic>{
                  'field': <String, dynamic>{'fieldPath': item.fieldPath},
                  'direction': item.descending ? 'DESCENDING' : 'ASCENDING',
                },
              )
              .toList(),
        if (limit case final int limitValue) 'limit': limitValue,
      },
    };
    final response = await _sendRequest(
      (headers) =>
          _httpClient.post(uri, headers: headers, body: jsonEncode(body)),
      allowUnauthenticated: allowUnauthenticated,
    );
    final payload = _decodeJsonList(response.body);
    if (response.statusCode == 404) {
      return const <WindowsFirestoreDocument>[];
    }
    _throwIfFailedList(response, payload);
    return payload
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .where((item) => item['document'] is Map)
        .map(
          (item) => _decodeDocument(
            Map<String, dynamic>.from(item['document'] as Map),
          ),
        )
        .toList(growable: false);
  }

  Future<void> setDocument(
    String documentPath,
    Map<String, dynamic> data, {
    bool allowUnauthenticated = false,
  }) async {
    final trimmedPath = _trimmedPath(documentPath);
    if (trimmedPath.isEmpty) {
      throw Exception('Document path is required.');
    }
    final uri = _buildUri(
      '$_documentsRoot/$trimmedPath',
      allowUnauthenticated: allowUnauthenticated,
    );
    final body = <String, dynamic>{
      'name': 'projects/$_projectId/databases/(default)/documents/$trimmedPath',
      'fields': _encodeFields(data),
    };
    final response = await _sendRequest(
      (headers) =>
          _httpClient.patch(uri, headers: headers, body: jsonEncode(body)),
      allowUnauthenticated: allowUnauthenticated,
    );
    _throwIfFailed(response, _decodeJsonMap(response.body));
  }

  Future<void> updateDocument(
    String documentPath,
    Map<String, dynamic> data, {
    bool allowUnauthenticated = false,
  }) async {
    final trimmedPath = _trimmedPath(documentPath);
    if (trimmedPath.isEmpty) {
      throw Exception('Document path is required.');
    }
    final baseUri = _buildUri(
      '$_documentsRoot/$trimmedPath',
      allowUnauthenticated: allowUnauthenticated,
    );
    final queryString = data.keys
        .map((key) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(key)}')
        .join('&');
    final uri = queryString.isEmpty
        ? baseUri
        : Uri.parse('${baseUri.toString()}?$queryString');
    final body = <String, dynamic>{
      'name': 'projects/$_projectId/databases/(default)/documents/$trimmedPath',
      'fields': _encodeFields(data),
    };
    final response = await _sendRequest(
      (headers) =>
          _httpClient.patch(uri, headers: headers, body: jsonEncode(body)),
      allowUnauthenticated: allowUnauthenticated,
    );
    _throwIfFailed(response, _decodeJsonMap(response.body));
  }

  Future<void> deleteDocument(
    String documentPath, {
    bool allowUnauthenticated = false,
  }) async {
    final trimmedPath = _trimmedPath(documentPath);
    if (trimmedPath.isEmpty) {
      return;
    }
    final uri = _buildUri(
      '$_documentsRoot/$trimmedPath',
      allowUnauthenticated: allowUnauthenticated,
    );
    final response = await _sendRequest(
      (headers) => _httpClient.delete(uri, headers: headers),
      allowUnauthenticated: allowUnauthenticated,
    );
    if (response.statusCode == 404) {
      return;
    }
    _throwIfFailed(response, _decodeJsonMap(response.body));
  }

  Uri _buildUri(String path, {required bool allowUnauthenticated}) {
    final baseUri = Uri.https(_host, path);
    if (!allowUnauthenticated || _apiKey.trim().isEmpty) {
      return baseUri;
    }
    return baseUri.replace(
      queryParameters: <String, String>{
        ...baseUri.queryParameters,
        'key': _apiKey.trim(),
      },
    );
  }

  Future<http.Response> _sendRequest(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool allowUnauthenticated = false,
  }) async {
    http.Response response = await request(
      await _headers(allowUnauthenticated: allowUnauthenticated),
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      response = await request(
        await _headers(
          forceRefresh: true,
          allowUnauthenticated: allowUnauthenticated,
        ),
      );
    }
    return response;
  }

  Future<Map<String, String>> _headers({
    bool forceRefresh = false,
    bool allowUnauthenticated = false,
  }) async {
    var idToken = await _authClient.getIdToken(forceRefresh: forceRefresh);
    if ((idToken ?? '').trim().isEmpty && !allowUnauthenticated) {
      await _authClient.reloadCurrentUser();
      idToken = await _authClient.getIdToken(forceRefresh: true);
    }
    if ((idToken ?? '').trim().isEmpty) {
      if (allowUnauthenticated) {
        return const <String, String>{'Content-Type': 'application/json'};
      }
      throw Exception('You must be logged in.');
    }
    return <String, String>{
      'Authorization': 'Bearer ${idToken!.trim()}',
      'Content-Type': 'application/json',
    };
  }

  Map<String, dynamic> _encodeFieldFilter(WindowsFirestoreFieldFilter filter) {
    return <String, dynamic>{
      'fieldFilter': <String, dynamic>{
        'field': <String, dynamic>{'fieldPath': filter.fieldPath},
        'op': filter.op,
        'value': _encodeValue(filter.value),
      },
    };
  }

  WindowsFirestoreDocument _decodeDocument(Map<String, dynamic> json) {
    final fullName = (json['name'] as String?) ?? '';
    final pathPrefix = 'projects/$_projectId/databases/(default)/documents/';
    final relativePath = fullName.startsWith(pathPrefix)
        ? fullName.substring(pathPrefix.length)
        : fullName;
    final id = relativePath.split('/').isEmpty
        ? ''
        : relativePath.split('/').last;
    final fields = Map<String, dynamic>.from(
      (json['fields'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), _decodeValue(value)),
          ) ??
          const <String, dynamic>{},
    );
    return WindowsFirestoreDocument(id: id, path: relativePath, data: fields);
  }

  Map<String, dynamic> _encodeFields(Map<String, dynamic> data) {
    return data.map((key, value) => MapEntry(key, _encodeValue(value)));
  }

  Map<String, dynamic> _encodeValue(Object? value) {
    if (value == null) {
      return const <String, dynamic>{'nullValue': null};
    }
    if (value is bool) {
      return <String, dynamic>{'booleanValue': value};
    }
    if (value is int) {
      return <String, dynamic>{'integerValue': value.toString()};
    }
    if (value is num) {
      return <String, dynamic>{'doubleValue': value};
    }
    if (value is DateTime) {
      return <String, dynamic>{
        'timestampValue': value.toUtc().toIso8601String(),
      };
    }
    if (value is String) {
      return <String, dynamic>{'stringValue': value};
    }
    if (value is Uint8List) {
      return <String, dynamic>{'bytesValue': base64Encode(value)};
    }
    if (value is Iterable) {
      return <String, dynamic>{
        'arrayValue': <String, dynamic>{
          'values': value.map((item) => _encodeValue(item)).toList(),
        },
      };
    }
    if (value is Map) {
      return <String, dynamic>{
        'mapValue': <String, dynamic>{
          'fields': value.map(
            (key, nested) => MapEntry(key.toString(), _encodeValue(nested)),
          ),
        },
      };
    }
    throw UnsupportedError(
      'Unsupported Firestore value type: ${value.runtimeType}',
    );
  }

  dynamic _decodeValue(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    if (raw.containsKey('nullValue')) {
      return null;
    }
    if (raw.containsKey('stringValue')) {
      return raw['stringValue'] as String?;
    }
    if (raw.containsKey('booleanValue')) {
      return raw['booleanValue'] as bool?;
    }
    if (raw.containsKey('integerValue')) {
      return int.tryParse((raw['integerValue'] as String?) ?? '');
    }
    if (raw.containsKey('doubleValue')) {
      final value = raw['doubleValue'];
      return value is num ? value.toDouble() : double.tryParse('$value');
    }
    if (raw.containsKey('timestampValue')) {
      return DateTime.tryParse(
        (raw['timestampValue'] as String?) ?? '',
      )?.toUtc();
    }
    if (raw.containsKey('bytesValue')) {
      return raw['bytesValue'];
    }
    if (raw.containsKey('referenceValue')) {
      return raw['referenceValue'];
    }
    if (raw.containsKey('arrayValue')) {
      final values = raw['arrayValue'];
      if (values is! Map) {
        return const <dynamic>[];
      }
      final rawValues = values['values'];
      if (rawValues is! List) {
        return const <dynamic>[];
      }
      return rawValues.map(_decodeValue).toList(growable: false);
    }
    if (raw.containsKey('mapValue')) {
      final mapValue = raw['mapValue'];
      if (mapValue is! Map) {
        return const <String, dynamic>{};
      }
      final fields = mapValue['fields'];
      if (fields is! Map) {
        return const <String, dynamic>{};
      }
      return fields.map(
        (key, value) => MapEntry(key.toString(), _decodeValue(value)),
      );
    }
    if (raw.containsKey('geoPointValue')) {
      final geoPoint = raw['geoPointValue'];
      if (geoPoint is! Map) {
        return null;
      }
      return <String, double?>{
        'latitude': (geoPoint['latitude'] as num?)?.toDouble(),
        'longitude': (geoPoint['longitude'] as num?)?.toDouble(),
      };
    }
    return null;
  }

  String _trimmedPath(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.startsWith('/')) {
      return trimmed.substring(1);
    }
    return trimmed;
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  List<dynamic> _decodeJsonList(String body) {
    if (body.trim().isEmpty) {
      return const <dynamic>[];
    }
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return decoded;
    }
    return const <dynamic>[];
  }

  void _throwIfFailed(http.Response response, Map<String, dynamic> payload) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final error = payload['error'];
    if (error is Map) {
      final message = (error['message'] as String?) ?? 'Request failed.';
      throw Exception(message);
    }
    throw Exception('Request failed (${response.statusCode}).');
  }

  void _throwIfFailedList(http.Response response, List<dynamic> payload) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    for (final item in payload) {
      if (item is! Map) {
        continue;
      }
      final error = item['error'];
      if (error is Map) {
        final message = (error['message'] as String?) ?? 'Request failed.';
        throw Exception(message);
      }
    }
    throw Exception('Request failed (${response.statusCode}).');
  }
}
