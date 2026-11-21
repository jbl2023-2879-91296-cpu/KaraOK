import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';

String token(Duration validity) {
  final expiry = DateTime.now().add(validity).millisecondsSinceEpoch ~/ 1000;
  return 'header.${base64UrlEncode(utf8.encode(jsonEncode({'exp': expiry})))}.signature';
}

Future<Map<String, dynamic>> upload(
  ApiService api, {
  void Function(int, int)? progress,
}) => api.submitAudio(
  filePath: '',
  fileName: 'karaoke.wav',
  fileBytes: Uint8List.fromList([11, 20, 33, 44]),
  durationSeconds: 20,
  onUploadProgress: progress,
);

http.Response refreshed(String newToken) => http.Response(
  jsonEncode({
    'access_token': newToken,
    'refresh_token': 'rotated',
    'user': {'user_id': 7},
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureTokenStore.instance;
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'an expiring token refreshes before the upload and reports bytes',
    () async {
      final fresh = token(const Duration(minutes: 15));
      await storage.saveTokens(
        accessToken: token(const Duration(minutes: 2)),
        refreshToken: 'initial',
      );
      final paths = <String>[];
      final progress = <(int, int)>[];
      final api = ApiService.withClient(
        MockClient((request) async {
          paths.add(request.url.path.split('/').last);
          if (request.url.path.endsWith('/refresh')) return refreshed(fresh);
          expect(request.headers['authorization'], 'Bearer $fresh');
          expect(request.bodyBytes, containsAllInOrder([11, 20, 33, 44]));
          return http.Response('{"status":"Completed"}', 200);
        }),
      );
      await upload(api, progress: (sent, total) => progress.add((sent, total)));
      expect(paths, ['refresh', 'audio-uploads']);
      expect(progress.first.$1, 0);
      expect(progress.last.$1, progress.last.$2);
      expect(await storage.readRefreshToken(), 'rotated');
    },
  );

  test(
    'two simultaneous unauthorized uploads share one refresh and retry the original audio',
    () async {
      final fresh = token(const Duration(minutes: 15));
      final stale = token(const Duration(minutes: 10));
      await storage.saveTokens(accessToken: stale, refreshToken: 'initial');
      final bothInitialUploads = Completer<void>();
      var initialUploads = 0;
      var retriedUploads = 0;
      var refreshes = 0;
      final api = ApiService.withClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/refresh')) {
            refreshes++;
            return refreshed(fresh);
          }
          expect(request.bodyBytes, containsAllInOrder([11, 20, 33, 44]));
          if (request.headers['authorization'] == 'Bearer $stale') {
            if (++initialUploads == 2) bothInitialUploads.complete();
            await bothInitialUploads.future;
            return http.Response('{"error":"Authorization rejected"}', 401);
          }
          expect(request.headers['authorization'], 'Bearer $fresh');
          retriedUploads++;
          return http.Response('{"status":"Completed"}', 200);
        }),
      );
      final results = await Future.wait([upload(api), upload(api)]);
      expect(results.map((result) => result['status']), [
        'Completed',
        'Completed',
      ]);
      expect(refreshes, 1);
      expect(initialUploads, 2);
      expect(retriedUploads, 2);
    },
  );

  test('only refresh rejection expires the session', () async {
    for (final rejectRefresh in [false, true]) {
      await storage.saveTokens(
        accessToken: token(const Duration(minutes: 10)),
        refreshToken: 'initial',
      );
      final api = ApiService.withClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/refresh') && !rejectRefresh) {
            return refreshed(token(const Duration(minutes: 15)));
          }
          return http.Response('{"error":"Authorization rejected"}', 401);
        }),
      );
      await expectLater(
        upload(api),
        throwsA(
          rejectRefresh
              ? isA<SessionExpiredException>()
              : isA<ApiException>().having(
                  (error) => error is SessionExpiredException,
                  'expired',
                  false,
                ),
        ),
      );
      expect(
        await storage.readRefreshToken(),
        rejectRefresh ? isNull : 'rotated',
      );
    }
  });
}
