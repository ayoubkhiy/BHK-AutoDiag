import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

bool isAllowedApiBaseUri(Uri uri, {required bool releaseBuild}) {
  if (uri.userInfo.isNotEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  if (!releaseBuild) return true;
  return const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, Uri? baseUri})
    : _client = client ?? http.Client(),
      _baseUri =
          baseUri ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8000/api/',
            ),
          ) {
    if (!isAllowedApiBaseUri(_baseUri, releaseBuild: kReleaseMode)) {
      throw const ApiException(
        'API_BASE_URL must use HTTPS for remote servers in release builds.',
      );
    }
  }

  final http.Client _client;
  final Uri _baseUri;
  String? token;

  Uri _uri(String path) => _baseUri.resolve(path);

  Uri photoUri(String path) => _uri(path);

  Map<String, String> get photoHeaders => {
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> get(String path) async {
    final response = await _network(
      () => _client.get(_uri(path), headers: _headers),
    );
    return _decode(response);
  }

  Future<Uint8List> getBytes(String path) async {
    final response = await _network(
      () => _client.get(_uri(path), headers: _headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _network(
      () => _client.post(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _network(
      () => _client.patch(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _network(
      () => _client.put(
        _uri(path),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required int inspectionId,
    required String zone,
    required String name,
    required List<int> bytes,
  }) => _uploadPhoto(
    'inspections/$inspectionId/photos/',
    name: name,
    bytes: bytes,
    fields: {'zone': zone},
  );

  Future<Map<String, dynamic>> uploadListingPhoto({
    required int listingId,
    required String name,
    required List<int> bytes,
  }) => _uploadPhoto('listings/$listingId/photos/', name: name, bytes: bytes);

  Future<Map<String, dynamic>> _uploadPhoto(
    String path, {
    required String name,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) async {
    final extension = name.split('.').last.toLowerCase();
    final contentType = switch (extension) {
      'jpg' || 'jpeg' => http.MediaType('image', 'jpeg'),
      'png' => http.MediaType('image', 'png'),
      'webp' => http.MediaType('image', 'webp'),
      _ => throw const ApiException('Format accepté : JPEG, PNG ou WebP.'),
    };
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers)
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: name,
          contentType: contentType,
        ),
      );
    final stream = await _network(() => _client.send(request));
    final response = await _network(() => http.Response.fromStream(stream));
    return _decode(response);
  }

  Future<Map<String, dynamic>> uploadReport({
    required int inspectionId,
    required Uint8List bytes,
  }) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('inspections/$inspectionId/reports/'),
          )
          ..headers.addAll(_headers)
          ..files.add(
            http.MultipartFile.fromBytes(
              'report',
              bytes,
              filename: 'report.pdf',
              contentType: http.MediaType('application', 'pdf'),
            ),
          );
    final stream = await _network(() => _client.send(request));
    final response = await _network(() => http.Response.fromStream(stream));
    return _decode(response);
  }

  Future<void> logout() async {
    if (token != null) {
      await post('logout/', const {});
    }
    token = null;
  }

  Future<T> _network<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 20));
    } on http.ClientException catch (error) {
      throw ApiException('Connexion au serveur impossible : ${error.message}');
    } on TimeoutException {
      throw const ApiException('Le serveur ne répond pas. Réessayez.');
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('Le serveur a renvoyé une réponse invalide.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['error']?.toString()
          : null;
      throw ApiException(message ?? 'Erreur serveur (${response.statusCode}).');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const ApiException('La réponse du serveur est invalide.');
    }
    return decoded;
  }
}

class ApiUser {
  const ApiUser({
    required this.id,
    required this.cin,
    required this.name,
    required this.isAdmin,
    required this.permissions,
  });

  final int id;
  final String cin;
  final String name;
  final bool isAdmin;
  final Map<String, bool> permissions;

  factory ApiUser.fromJson(Map<String, dynamic> json) {
    final rawPermissions = json['permissions'];
    return ApiUser(
      id: json['id'] as int,
      cin: json['cin'] as String? ?? '',
      name: json['name'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
      permissions: rawPermissions is Map<String, dynamic>
          ? rawPermissions.map((key, value) => MapEntry(key, value == true))
          : const {},
    );
  }
}
