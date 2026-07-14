import 'dart:convert';
import 'package:http/http.dart' as http;

/// Central API service — talks to the Flask backend.
/// Change [baseUrl] to your machine's IP when running on a physical device.
class ApiService {
  // Use 10.0.2.2 for Android emulator (maps to host localhost).
  // Use your actual LAN IP (e.g. 192.168.1.x) for a physical device.
  static const String baseUrl = 'http://10.0.2.2:5000/api';

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final _headers = {'Content-Type': 'application/json'};

  // ── helpers ───────────────────────────────────────────────────────────────

  Uri _uri(String path, [Map<String, String>? params]) {
    final uri = Uri.parse('$baseUrl$path');
    return params != null ? uri.replace(queryParameters: params) : uri;
  }

  Future<dynamic> _get(String path, [Map<String, String>? params]) async {
    final res = await http.get(_uri(path, params), headers: _headers);
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final res = await http.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    _checkStatus(res);
    return jsonDecode(res.body);
  }

  Future<void> _delete(String path) async {
    final res = await http.delete(_uri(path), headers: _headers);
    _checkStatus(res);
  }

  void _checkStatus(http.Response res) {
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, res.body);
    }
  }

  // ── health ────────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      final data = await _get('/health');
      return data['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ── auth ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String userType,
  }) async {
    final data = await _post('/auth/register', {
      'name': name,
      'email': email,
      'password': password,
      'user_type': userType,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final data = await _post('/auth/login', {
      'email': email,
      'password': password,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  // ── users ─────────────────────────────────────────────────────────────────

  Future<List<dynamic>> getUsers() => _get('/users') as Future<List<dynamic>>;

  Future<Map<String, dynamic>> createUser({
    required String name,
    required String userType,
  }) async {
    final data = await _post('/users', {'name': name, 'user_type': userType});
    return Map<String, dynamic>.from(data as Map);
  }

  // ── audio tests (technician) ──────────────────────────────────────────────

  Future<List<dynamic>> getAudioTests({int? userId}) async {
    final params = userId != null ? {'user_id': '$userId'} : null;
    final data = await _get('/audio-tests', params);
    return List<dynamic>.from(data as List);
  }

  Future<Map<String, dynamic>> getAudioTest(int testId) async {
    final data = await _get('/audio-tests/$testId');
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> createAudioTest({
    int? userId,
    required String testName,
    required int score,
    double noiseLevel = -4.8,
    double distortionLevel = 0.12,
    String status = 'Acceptable',
    int durationSeconds = 0,
  }) async {
    final data = await _post('/audio-tests', {
      'user_id': userId,
      'test_name': testName,
      'score': score,
      'noise_level': noiseLevel,
      'distortion_level': distortionLevel,
      'status': status,
      'duration_seconds': durationSeconds,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> deleteAudioTest(int testId) => _delete('/audio-tests/$testId');

  // ── genre settings (owner) ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getGenreSettings(String genre) async {
    final data = await _get('/genre-settings', {'genre': genre});
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<dynamic>> getAllGenreSettings() async {
    final data = await _get('/genre-settings');
    return List<dynamic>.from(data as List);
  }

  Future<Map<String, dynamic>> saveGenreSettings({
    int? userId,
    required String genre,
    required int volume,
    required int bass,
    required int treble,
    required int flatness,
    required int sharpness,
  }) async {
    final data = await _post('/genre-settings', {
      'user_id': userId,
      'genre': genre,
      'volume': volume,
      'bass': bass,
      'treble': treble,
      'flatness': flatness,
      'sharpness': sharpness,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  // ── audio uploads (owner) ─────────────────────────────────────────────────

  Future<List<dynamic>> getAudioUploads({int? userId}) async {
    final params = userId != null ? {'user_id': '$userId'} : null;
    final data = await _get('/audio-uploads', params);
    return List<dynamic>.from(data as List);
  }

  Future<Map<String, dynamic>> createAudioUpload({
    int? userId,
    required String fileName,
    String? genre,
    int? score,
    String status = 'Acceptable',
  }) async {
    final data = await _post('/audio-uploads', {
      'user_id': userId,
      'file_name': fileName,
      'genre': genre,
      'score': score,
      'status': status,
    });
    return Map<String, dynamic>.from(data as Map);
  }
}

// ── Exception ─────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException $statusCode: $message';
}
