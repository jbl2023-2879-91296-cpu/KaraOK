import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:karaok_app/core/config/environment.dart';
import 'package:karaok_app/core/network/api_exception.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';

export 'package:karaok_app/core/network/api_exception.dart';

/// Authenticated client for the KaraOK Flask API.
///
/// Override at build/run time when the API is not on localhost:
/// flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000/api
class ApiService {
  static const String baseUrl = Environment.apiBaseUrl;

  static final _tokenStore = SecureTokenStore.instance;

  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Uri _uri(String path, [Map<String, String>? params]) {
    final uri = Uri.parse('$baseUrl$path');
    return params == null ? uri : uri.replace(queryParameters: params);
  }

  Future<Map<String, String>> _headers({bool authenticated = true}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated) {
      final token = await _tokenStore.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool retry = true,
  }) async {
    final uri = _uri(path, params);
    final headers = await _headers(authenticated: authenticated);
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
        break;
      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'PATCH':
        response = await http.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
        break;
      default:
        throw ArgumentError('Unsupported method: $method');
    }

    if (response.statusCode == 401 &&
        authenticated &&
        retry &&
        await _refresh()) {
      return _send(
        method,
        path,
        params: params,
        body: body,
        authenticated: true,
        retry: false,
      );
    }
    _checkStatus(response);
    return response;
  }

  dynamic _decode(http.Response response) =>
      response.body.isEmpty ? null : jsonDecode(response.body);

  Future<dynamic> _get(String path, [Map<String, String>? params]) async =>
      _decode(await _send('GET', path, params: params));

  Future<dynamic> _post(
    String path,
    Map<String, dynamic> body, {
    bool authenticated = true,
  }) async => _decode(
    await _send('POST', path, body: body, authenticated: authenticated),
  );

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async =>
      _decode(await _send('PATCH', path, body: body));

  Future<void> _delete(String path) async {
    await _send('DELETE', path);
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode >= 400) {
      String message = switch (response.statusCode) {
        429 => 'Too many requests. Please wait before trying again.',
        >= 500 =>
          'The server could not complete the request. Please try again.',
        _ => 'Request failed (${response.statusCode}).',
      };
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'];
        }
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
  }

  Future<void> _saveAuth(Map<String, dynamic> data) async {
    await _tokenStore.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
    );
  }

  Future<bool> _refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return false;
    try {
      final response = await http.post(
        _uri('/auth/refresh'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
      if (response.statusCode >= 400) {
        await clearTokens();
        return false;
      }
      await _saveAuth(
        Map<String, dynamic>.from(jsonDecode(response.body) as Map),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearTokens() async {
    await _tokenStore.clear();
  }

  Future<bool> checkHealth() async {
    try {
      final response = await http.get(_uri('/health'));
      return response.statusCode == 200 &&
          jsonDecode(response.body)['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> startRegistration({
    required String username,
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String address,
    required String city,
    required String stateProvince,
    required String areaCode,
    required String country,
    required String countryCode,
    required String phoneNumber,
    required String birthday,
    String? profileImageBase64,
    String? profileImageMime,
  }) async {
    return Map<String, dynamic>.from(
      await _post('/auth/register', {
            'username': username,
            'first_name': firstName,
            'last_name': lastName,
            'email': email,
            'password': password,
            'address': address,
            'city': city,
            'state_province': stateProvince,
            'area_code': areaCode,
            'country': country,
            'country_code': countryCode,
            'phone_number': phoneNumber,
            'birthday': birthday,
            'profile_image_base64': ?profileImageBase64,
            'profile_image_mime': ?profileImageMime,
          }, authenticated: false)
          as Map,
    );
  }

  Future<Map<String, dynamic>> verifyRegistration({
    required String email,
    required String code,
  }) async {
    final data = Map<String, dynamic>.from(
      await _post('/auth/register/verify', {
            'email': email,
            'code': code,
          }, authenticated: false)
          as Map,
    );
    await _saveAuth(data);
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    final data = Map<String, dynamic>.from(
      await _post('/auth/login', {
            'identifier': identifier,
            'password': password,
          }, authenticated: false)
          as Map,
    );
    await _saveAuth(data);
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    try {
      if (refreshToken != null) {
        await _post('/auth/logout', {'refresh_token': refreshToken});
      }
    } finally {
      await clearTokens();
    }
  }

  Future<Map<String, dynamic>> requestPasswordReset(String email) async {
    return Map<String, dynamic>.from(
      await _post('/auth/forgot-password', {
            'email': email,
          }, authenticated: false)
          as Map,
    );
  }

  Future<void> changePassword({
    String? currentPassword,
    required String newPassword,
  }) async {
    await _post('/auth/change-password', {
      'current_password': ?currentPassword,
      'new_password': newPassword,
    });
  }

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String firstName,
    required String lastName,
    required String address,
    required String city,
    required String stateProvince,
    required String areaCode,
    required String country,
    required String countryCode,
    required String phoneNumber,
    required String birthday,
    String? profileImageBase64,
    String? profileImageMime,
    bool profileImageChanged = false,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'first_name': firstName,
      'last_name': lastName,
      'address': address,
      'city': city,
      'state_province': stateProvince,
      'area_code': areaCode,
      'country': country,
      'country_code': countryCode,
      'phone_number': phoneNumber,
      'birthday': birthday,
    };
    if (profileImageChanged) {
      body['profile_image_base64'] = profileImageBase64;
      body['profile_image_mime'] = profileImageMime;
    }
    final data = Map<String, dynamic>.from(
      await _patch('/users/me', body) as Map,
    );
    return Map<String, dynamic>.from(data['user'] as Map);
  }

  Future<List<dynamic>> getUsers() async =>
      List<dynamic>.from(await _get('/users') as List);

  Future<List<dynamic>> getAudioTests() async =>
      List<dynamic>.from(await _get('/audio-tests') as List);

  Future<Map<String, dynamic>> getAudioTest(int testId) async =>
      Map<String, dynamic>.from(await _get('/audio-tests/$testId') as Map);

  Future<Uint8List> getAudioVisualization(int testId, String kind) async {
    if (kind != 'waveform' && kind != 'spectrogram') {
      throw ArgumentError.value(kind, 'kind', 'Unsupported visualization');
    }
    final response = await _send(
      'GET',
      '/audio-tests/$testId/visualizations/$kind',
    );
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> createAudioTest({
    required String testName,
    required int score,
    double noiseLevel = -4.8,
    double distortionLevel = 0.12,
    String status = 'Acceptable',
    int durationSeconds = 0,
  }) async => Map<String, dynamic>.from(
    await _post('/audio-tests', {
          'test_name': testName,
          'score': score,
          'noise_level': noiseLevel,
          'distortion_level': distortionLevel,
          'status': status,
          'duration_seconds': durationSeconds,
        })
        as Map,
  );

  Future<void> deleteAudioTest(int testId) => _delete('/audio-tests/$testId');

  Future<Map<String, dynamic>> getGenreSettings(String genre) async =>
      Map<String, dynamic>.from(
        await _get('/genre-settings', {'genre': genre}) as Map,
      );

  Future<List<dynamic>> getAllGenreSettings() async =>
      List<dynamic>.from(await _get('/genre-settings') as List);

  Future<Map<String, dynamic>> saveGenreSettings({
    required String genre,
    required int volume,
    required int bass,
    required int treble,
    required int flatness,
    required int sharpness,
  }) async => Map<String, dynamic>.from(
    await _post('/genre-settings', {
          'genre': genre,
          'volume': volume,
          'bass': bass,
          'treble': treble,
          'flatness': flatness,
          'sharpness': sharpness,
        })
        as Map,
  );

  Future<List<dynamic>> getAudioUploads() async =>
      List<dynamic>.from(await _get('/audio-uploads') as List);

  Future<Map<String, dynamic>> getAudioAnalysisDump(int uploadId) async =>
      Map<String, dynamic>.from(
        await _get('/audio-uploads/$uploadId/analysis-dump') as Map,
      );

  Future<Map<String, dynamic>> createAudioUpload({
    required String fileName,
    String? genre,
    int? score,
    String status = 'Acceptable',
  }) async => Map<String, dynamic>.from(
    await _post('/audio-uploads', {
          'file_name': fileName,
          'genre': genre,
          'score': score,
          'status': status,
        })
        as Map,
  );

  Future<Map<String, dynamic>> submitAudio({
    required String filePath,
    required String fileName,
    Uint8List? fileBytes,
    required int durationSeconds,
    String? genre,
    String analysisPurpose = 'quality_evaluation',
    bool guest = false,
  }) async {
    final endpoint = guest ? '/guest/audio-analysis' : '/audio-uploads';
    final request = http.MultipartRequest('POST', _uri(endpoint));
    final headers = await _headers(authenticated: !guest);
    headers.remove('Content-Type');
    request.headers.addAll(headers);
    request.fields['duration_seconds'] =
        (durationSeconds < 1 ? 1 : durationSeconds).toString();
    request.fields['analysis_purpose'] = analysisPurpose;
    if (genre != null && genre.trim().isNotEmpty) {
      request.fields['genre'] = genre.trim();
    }
    request.files.add(
      fileBytes == null
          ? await http.MultipartFile.fromPath('audio', filePath)
          : http.MultipartFile.fromBytes(
              'audio',
              fileBytes,
              filename: fileName,
            ),
    );
    try {
      final streamed = await request.send().timeout(
        const Duration(seconds: 360),
      );
      final response = await http.Response.fromStream(streamed);
      _checkStatus(response);
      final decoded = _decode(response);
      if (decoded is! Map) {
        throw const FormatException('Invalid upload response');
      }
      return Map<String, dynamic>.from(decoded);
    } on SocketException catch (e) {
      throw ApiException(0, 'The backend server is unreachable: ${e.message}');
    } on HttpException catch (e) {
      throw ApiException(0, 'The upload connection failed: ${e.message}');
    }
  }
}
