import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> sample() => Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/settings_recommendation_response.json',
          ).readAsStringSync(),
        )
        as Map,
  );

  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'karaok_access_token': 'owner-token',
    }),
  );

  test(
    'feedback posts authenticated choice and round trips saved answer',
    () async {
      for (final value in ['better', 'same', 'worse']) {
        final api = SettingsApi(
          client: ApiService.withClient(
            MockClient((request) async {
              expect(request.method, 'POST');
              expect(
                request.url.path,
                endsWith('/settings-recommendations/41/feedback'),
              );
              expect(request.headers['Authorization'], 'Bearer owner-token');
              expect(jsonDecode(request.body), {'feedback': value});
              return http.Response(
                jsonEncode({...sample(), 'feedback': value}),
                200,
              );
            }),
          ),
        );
        final saved = await api.saveFeedback(41, value);
        expect(saved.feedback, value);
        expect(SettingsRecommendation.fromJson(saved.toJson()).feedback, value);
      }
    },
  );

  test(
    'unanswered remains nullable and invalid saved feedback is rejected',
    () {
      expect(SettingsRecommendation.fromJson(sample()).feedback, isNull);
      expect(
        () =>
            SettingsRecommendation.fromJson({...sample(), 'feedback': 'great'}),
        throwsFormatException,
      );
    },
  );

  test('feedback uses the shared token refresh and retries once', () async {
    FlutterSecureStorage.setMockInitialValues({
      'karaok_access_token': 'expired-token',
      'karaok_refresh_token': 'refresh-token',
    });
    var attempts = 0;
    var refreshes = 0;
    final api = SettingsApi(
      client: ApiService.withClient(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshes++;
            return http.Response(
              jsonEncode({
                'access_token': 'new-token',
                'refresh_token': 'next-refresh',
                'user': {'user_id': 7, 'user_type': 'user'},
              }),
              200,
            );
          }
          attempts++;
          if (attempts == 1) return http.Response('{}', 401);
          expect(request.headers['Authorization'], 'Bearer new-token');
          expect(jsonDecode(request.body), {'feedback': 'better'});
          return http.Response(
            jsonEncode({...sample(), 'feedback': 'better'}),
            200,
          );
        }),
      ),
    );
    expect((await api.saveFeedback(41, 'better')).feedback, 'better');
    expect(attempts, 2);
    expect(refreshes, 1);
  });

  test('invalid input never sends and denied save is surfaced', () async {
    var calls = 0;
    final api = SettingsApi(
      client: ApiService.withClient(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 404);
        }),
      ),
    );
    await expectLater(api.saveFeedback(0, 'better'), throwsArgumentError);
    await expectLater(api.saveFeedback(41, 'great'), throwsArgumentError);
    expect(calls, 0);
    await expectLater(
      api.saveFeedback(41, 'better'),
      throwsA(isA<ApiException>()),
    );
    expect(calls, 1);
  });
}
