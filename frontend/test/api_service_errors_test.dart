import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karaok_app/core/network/api_service.dart';

void main() {
  test(
    'maps single and multiple server field errors without losing message',
    () async {
      for (final body in [
        '{"error":"Email already registered","field":"email"}',
        '{"error":"Please check your details","errors":{"email":"Email already registered","password":"Too weak"}}',
      ]) {
        final api = ApiService.withClient(
          MockClient((_) async => http.Response(body, 409)),
        );
        await expectLater(
          api.startRegistration(email: 'a@example.com', password: 'GoodPass1!'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', 409)
                .having(
                  (e) => e.fieldErrors['email'],
                  'email field',
                  'Email already registered',
                ),
          ),
        );
      }
    },
  );

  test('rate limit uses server wait time', () async {
    final api = ApiService.withClient(
      MockClient(
        (_) async => http.Response(
          '{"error":"Too many requests"}',
          429,
          headers: {'retry-after': '175'},
        ),
      ),
    );
    await expectLater(
      api.requestPasswordReset('a@example.com'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.retryAfterSeconds, 'wait', 175)
            .having((e) => e.message, 'message', contains('175 seconds')),
      ),
    );
  });

  test(
    'ordinary requests time out and report friendly connectivity errors',
    () async {
      final api = ApiService.withClient(
        MockClient((_) => Completer<http.Response>().future),
        requestTimeout: const Duration(milliseconds: 1),
      );
      await expectLater(
        api.requestPasswordReset('a@example.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('too long'),
          ),
        ),
      );
      final offline = ApiService.withClient(
        MockClient((_) async => throw http.ClientException('network error')),
      );
      await expectLater(
        offline.requestPasswordReset('a@example.com'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('No connection'),
          ),
        ),
      );
    },
  );

  test('upload maps client and timeout errors', () async {
    for (final error in [
      http.ClientException('network error'),
      TimeoutException('timeout'),
    ]) {
      final api = ApiService.withClient(MockClient((_) async => throw error));
      await expectLater(
        api.submitAudio(
          filePath: '',
          fileName: 'test.wav',
          fileBytes: Uint8List(4),
          durationSeconds: 10,
          guest: true,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'connectivity status', 0)
              .having((e) => e.message, 'retry advice', contains('retry')),
        ),
      );
    }
  });
}
