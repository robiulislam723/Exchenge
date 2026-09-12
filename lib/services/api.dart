import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Api {
  // Production API base (Laravel). Override at build time with:
  // flutter build apk --dart-define=API_BASE=https://your-host
  static const String base = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'https://exchenge.narailexpress.net',
  );

  static String? _token;

  static Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
  }

  static Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('token');
    } else {
      await prefs.setString('token', token);
    }
  }

  static bool get isLoggedIn => _token != null && _token!.isNotEmpty;

  static Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  static Future<dynamic> get(String path, [Map<String, dynamic>? query]) async {
    final uri = Uri.parse('$base/api/mobile$path')
        .replace(queryParameters: query?.map((k, v) => MapEntry(k, '$v')));
    final res = await http.get(uri, headers: _headers);
    return _decode(res);
  }

  static Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$base/api/mobile$path');
    final res = await http.post(uri, headers: _headers, body: jsonEncode(body ?? {}));
    return _decode(res);
  }

  static dynamic _decode(http.Response res) {
    final text = res.body.isEmpty ? '{}' : res.body;
    final data = jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) return data;
    final message = (data is Map && data['message'] != null)
        ? data['message'].toString()
        : 'Request failed (${res.statusCode})';
    throw ApiException(message, res.statusCode);
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}
