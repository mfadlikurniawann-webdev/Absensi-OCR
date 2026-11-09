import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Klien REST API backend absensi (lihat api/app.py).
class ApiService {
  ApiService({required this.baseUrl, this.token, http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);
  // Pencocokan wajah di server bisa lebih lama (CPU, request pertama memuat model).
  static const _faceTimeout = Duration(seconds: 90);

  Map<String, String> get _authHeaders =>
      token == null ? const {} : {'Authorization': 'Bearer $token'};

  Uri _uri(String path, [Map<String, String?>? query]) {
    final uri = Uri.parse('$baseUrl$path');
    final params = <String, String>{
      for (final e in (query ?? const <String, String?>{}).entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return params.isEmpty ? uri : uri.replace(queryParameters: params);
  }

  // ---------------------------------------------------------------- publik

  Future<HealthInfo> health() async {
    final body = await _json(() => _client.get(_uri('/api/health')), _timeout);
    return HealthInfo.fromJson(body);
  }

  /// Kirim foto wajah untuk absen. Wajah tidak dikenali bukan error:
  /// hasilnya `recognized == false`.
  Future<AttendanceResult> submitAttendance(Uint8List jpeg) async {
    final body = await _json(
      () => _upload('/api/attendance', jpeg, const {}),
      _faceTimeout,
    );
    return AttendanceResult.fromJson(body);
  }

  Future<String> registerFace({
    required String name,
    required String npm,
    required Uint8List jpeg,
  }) async {
    final body = await _json(
      () => _upload('/api/register', jpeg, {'name': name, 'npm': npm}),
      _faceTimeout,
    );
    return body['message']?.toString() ?? 'Registrasi berhasil!';
  }

  // ----------------------------------------------------------------- admin

  Future<AdminLogin> adminLogin(String username, String password) async {
    final body = await _json(
      () => _client.post(
        _uri('/api/admin/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ),
      _timeout,
    );
    return AdminLogin.fromJson(body);
  }

  Future<AdminSummary> summary() async {
    final body = await _json(
      () => _client.get(_uri('/api/admin/summary'), headers: _authHeaders),
      _timeout,
    );
    return AdminSummary.fromJson(body);
  }

  Future<List<AttendanceRecord>> attendance({
    String? date,
    String? query,
  }) async {
    final body = await _json(
      () => _client.get(
        _uri('/api/admin/attendance', {'date': date, 'q': query}),
        headers: _authHeaders,
      ),
      _timeout,
    );
    return _list(body['data']).map(AttendanceRecord.fromJson).toList();
  }

  Future<List<RegisteredUser>> users() async {
    final body = await _json(
      () => _client.get(_uri('/api/admin/users'), headers: _authHeaders),
      _timeout,
    );
    return _list(body['data']).map(RegisteredUser.fromJson).toList();
  }

  Future<String> deleteUser(int id) async {
    final body = await _json(
      () => _client.delete(_uri('/api/admin/users/$id'), headers: _authHeaders),
      _timeout,
    );
    return body['message']?.toString() ?? 'Pengguna dihapus.';
  }

  Future<Uint8List> exportCsv({String? date, String? query}) async {
    final res = await _send(
      () => _client.get(
        _uri('/api/admin/export.csv', {'date': date, 'q': query}),
        headers: _authHeaders,
      ),
      _timeout,
    );
    if (res.statusCode >= 400) _decode(res); // lempar ApiException
    return res.bodyBytes;
  }

  // -------------------------------------------------------------- internal

  Future<http.Response> _upload(
    String path,
    Uint8List jpeg,
    Map<String, String> fields,
  ) async {
    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_authHeaders)
      ..fields.addAll(fields)
      ..files.add(
        http.MultipartFile.fromBytes('image', jpeg, filename: 'face.jpg'),
      );
    return http.Response.fromStream(await _client.send(request));
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Server tidak merespons.');
    } on SocketException {
      throw ApiException('Tidak bisa terhubung ke server.');
    } on HandshakeException {
      throw ApiException('Koneksi HTTPS gagal.');
    } on http.ClientException {
      throw ApiException('Tidak bisa terhubung ke server.');
    }
  }

  Future<Map<String, dynamic>> _json(
    Future<http.Response> Function() request,
    Duration timeout,
  ) async => _decode(await _send(request, timeout));

  Map<String, dynamic> _decode(http.Response res) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(
        'Respons server tidak valid. Periksa alamat server.',
        statusCode: res.statusCode,
      );
    }
    final body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};
    if (res.statusCode >= 400) {
      throw ApiException(
        body['message']?.toString() ?? 'Terjadi kesalahan (${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    return body;
  }

  static List<Map<String, dynamic>> _list(Object? data) =>
      data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];
}
