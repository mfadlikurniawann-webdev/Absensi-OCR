import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';

/// Pengaturan aplikasi yang disimpan di perangkat: alamat server & token admin.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  /// Alamat server bawaan. Bisa diatur saat build:
  ///   flutter build apk --dart-define=API_BASE_URL=https://absensi.domainanda.com
  /// Default `10.0.2.2` = alamat komputer host dari emulator Android.
  static const String defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000',
  );

  static const _kBaseUrl = 'base_url';
  static const _kToken = 'admin_token';
  static const _kTokenExpiry = 'admin_token_expiry';

  SharedPreferences? _prefs;
  String _baseUrl = defaultBaseUrl;
  String? _token;
  DateTime? _tokenExpiry;

  String get baseUrl => _baseUrl;

  /// Token admin yang masih berlaku, atau null.
  String? get adminToken {
    final expiry = _tokenExpiry;
    if (_token == null || expiry == null || DateTime.now().isAfter(expiry)) {
      return null;
    }
    return _token;
  }

  bool get isAdminLoggedIn => adminToken != null;

  ApiService api() => ApiService(baseUrl: _baseUrl, token: adminToken);

  Future<void> load() async {
    final prefs = _prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? defaultBaseUrl;
    _token = prefs.getString(_kToken);
    final expiryMs = prefs.getInt(_kTokenExpiry);
    _tokenExpiry = expiryMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiryMs);
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = normalizeUrl(url);
    await _prefs?.setString(_kBaseUrl, _baseUrl);
    notifyListeners();
  }

  Future<void> saveAdminToken(String token, Duration validFor) async {
    _token = token;
    // Kurangi sedikit agar token tidak dipakai tepat saat kedaluwarsa.
    _tokenExpiry = DateTime.now().add(validFor - const Duration(minutes: 1));
    await _prefs?.setString(_kToken, token);
    await _prefs?.setInt(_kTokenExpiry, _tokenExpiry!.millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> clearAdminToken() async {
    _token = null;
    _tokenExpiry = null;
    await _prefs?.remove(_kToken);
    await _prefs?.remove(_kTokenExpiry);
    notifyListeners();
  }

  /// Rapikan input alamat server: tambah `http://` bila belum ada skema
  /// dan buang garis miring di akhir.
  static String normalizeUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      value = 'http://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
