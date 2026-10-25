// Native-only smoke suite. Parent runner must build with the isolated Android
// application ID com.jrpbone.karaok.smoketest (KARAOK_APPLICATION_ID).
// Run with --no-uninstall: Flutter may cache the original application ID before
// building the override, and its automatic teardown can uninstall that app.
// Remove only the verified smoketest package explicitly after saving screenshots.
// No real authentication, HTTP requests, store resets, or account mutations.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/home/presentation/pages/user_home_screen.dart';
import 'package:karaok_app/features/reports/domain/sample_assessments.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:path_provider/path_provider.dart';

class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _BlockedHttpClient();
}

/// Allow API client construction, but never create a socket or send a request.
class _BlockedHttpClient implements HttpClient {
  static int attemptedRequests = 0;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    attemptedRequests++;
    throw StateError(
      'Network is forbidden in the native smoke suite: $method $url',
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    // HttpClient configuration is harmless; no underlying client exists.
    if (invocation.isSetter) return null;
    attemptedRequests++;
    throw StateError(
      'Network client operation is forbidden: ${invocation.memberName}',
    );
  }
}

class _NoAuth extends AuthApi {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> startRegistration({
    String? username,
    required String email,
    required String password,
  }) async {
    calls++;
    throw StateError('Blank signup must never submit authentication.');
  }

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) async {
    calls++;
    throw StateError('The smoke suite must never submit login.');
  }
}

Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.light,
  darkTheme: AppTheme.light,
  themeMode: ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: const TextScaler.linear(1.3)),
    child: child!,
  ),
  home: home,
);

Future<void> _checkFrame(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'No layout overflow or framework exception',
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var surfaceConverted = false;
  HttpOverrides? previousHttpOverrides;

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.isAndroid && !surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      surfaceConverted = true;
      await tester.pumpAndSettle();
    }
    final bytes = await binding.takeScreenshot('smoke-$name');
    expect(bytes, isNotEmpty);
    final documents = await getApplicationDocumentsDirectory();
    final file = File('${documents.path}/smoke-$name.png');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('Smoke screenshot: ${file.path}');
  }

  setUp(() {
    // The integration binding restores its Android surface after each test.
    surfaceConverted = false;
    _BlockedHttpClient.attemptedRequests = 0;
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _NoNetwork();
    // This changes the in-memory identity only; no persistent store is cleared.
    UserSession.instance.setGuest('user');
    binding.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
  });
  tearDown(() {
    binding.platformDispatcher.clearPlatformBrightnessTestValue();
    HttpOverrides.global = previousHttpOverrides;
    expect(
      _BlockedHttpClient.attemptedRequests,
      0,
      reason:
          'Smoke scenarios must not attempt HTTP, even if errors are caught',
    );
  });

  testWidgets(
    'guest Home stays light at 1.3 text with injected local records',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        _app(
          UserHomeScreen(
            resultsLoader: () async {
              loads++;
              return sampleAssessments;
            },
          ),
        ),
      );
      await _checkFrame(tester);
      expect(loads, 1);
      expect(find.text('Evaluate Audio Quality'), findsOneWidget);
      expect(find.text('Generate Audio Settings Suggestion'), findsOneWidget);
      final context = tester.element(find.byType(UserHomeScreen));
      expect(MediaQuery.platformBrightnessOf(context), Brightness.dark);
      expect(MediaQuery.textScalerOf(context).scale(10), 13);
      expect(Theme.of(context).brightness, Brightness.light);
      await screenshot(tester, 'home-dark-system-text130');
      for (final name in sampleAssessments.map(
        (record) => record['test_name'] as String,
      )) {
        await tester.scrollUntilVisible(
          find.text(name),
          200,
          scrollable: find
              .descendant(
                of: find.byType(UserHomeScreen),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 50,
        );
        await _checkFrame(tester);
        expect(find.text(name), findsOneWidget);
      }
    },
  );

  testWidgets(
    'blank signup shows field errors and asks only email and passwords',
    (tester) async {
      final auth = _NoAuth();
      await tester.pumpWidget(_app(SignUpScreen(authApi: auth)));
      await _checkFrame(tester);
      expect(find.byType(TextFormField), findsNWidgets(3));
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      expect(find.textContaining('Username'), findsNothing);
      final submit = find.widgetWithText(
        ElevatedButton,
        'Send Verification Code',
      );
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await _checkFrame(tester);
      expect(find.text('Enter your email address.'), findsOneWidget);
      expect(
        find.text('Password must be between 8 and 128 characters.'),
        findsOneWidget,
      );
      expect(find.text('Confirm your password.'), findsOneWidget);
      expect(auth.calls, 0);
      await screenshot(tester, 'signup-blank-errors');
      await tester.ensureVisible(find.text('Confirm your password.'));
      await _checkFrame(tester);
      await screenshot(tester, 'signup-confirm-error');
    },
  );

  testWidgets('root Login back reaches Home instead of a blank route', (
    tester,
  ) async {
    final auth = _NoAuth();
    await tester.pumpWidget(_app(LoginScreen(authApi: auth)));
    await _checkFrame(tester);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await _checkFrame(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(UserHomeScreen), findsOneWidget);
    expect(find.text('Evaluate Audio Quality'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(auth.calls, 0);
    await screenshot(tester, 'root-login-back-home');
  });

  testWidgets('Results metric sheet shows saved target bounds locally', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const ResultsScreen(
          testName: 'Local smoke fixture',
          isGuest: true,
          isSample: true,
          score: 85,
          featureResults: {
            'loudness': {
              'value': -14.2,
              'score': 85,
              'status': 'good',
              'target_lower': -18.0,
              'target_upper': -12.0,
            },
          },
        ),
      ),
    );
    await _checkFrame(tester);
    await tester.ensureVisible(find.text('Loudness').first);
    await tester.tap(find.text('Loudness').first);
    await _checkFrame(tester);
    expect(find.text('Target lower: -18.00 LUFS'), findsOneWidget);
    expect(find.text('Target upper: -12.00 LUFS'), findsOneWidget);
    expect(find.textContaining('Within this reference range:'), findsOneWidget);
    await screenshot(tester, 'results-target-bounds');
    await tester.ensureVisible(find.text('Close'));
    await _checkFrame(tester);
    await tester.tap(find.text('Close'));
    await _checkFrame(tester);
  });

  testWidgets(
    'synthetic three-hour low-bitrate MP3 rejects before player initialization',
    (tester) async {
      const channel = MethodChannel('com.ryanheise.just_audio.methods');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      var playerInitializations = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'init') playerInitializations++;
        throw StateError('Native player must not be reached for long MP3.');
      });
      final temp = await getTemporaryDirectory();
      final directory = await Directory(temp.path).createTemp('karaok-smoke-');
      try {
        // MPEG-2 Layer III: 8 kbps, 22050 Hz, 576 samples per frame.
        // Frame payloads are zeros: this is a duration-header fixture, not music.
        const sampleRate = 22050;
        const samplesPerFrame = 576;
        const frameBytes = 72000 * 8 ~/ sampleRate;
        final frameCount =
            (const Duration(hours: 3).inSeconds * sampleRate / samplesPerFrame)
                .ceil();
        final bytes = Uint8List(frameCount * frameBytes);
        for (var offset = 0; offset < bytes.length; offset += frameBytes) {
          bytes.setAll(offset, [0xff, 0xf3, 0x10, 0x00]);
        }
        final file = await File(
          '${directory.path}/three-hour-low-bitrate.mp3',
        ).writeAsBytes(bytes);
        expect(await file.length(), lessThan(AudioStagingService.maxBytes));
        final staging = AudioStagingService();
        await expectLater(
          staging.stagePath(
            file.path,
            AudioSourceType.selectedFile,
            temporary: false,
          ),
          throwsA(
            isA<AudioStagingException>().having(
              (error) => error.message,
              'message',
              contains('five-minute'),
            ),
          ),
        );
        expect(playerInitializations, 0);
        expect(staging.current, isNull);
        expect(await file.exists(), isTrue);
      } finally {
        messenger.setMockMethodCallHandler(channel, null);
        // Only this test's unique temporary fixture directory is removed.
        await directory.delete(recursive: true);
      }
    },
  );
}
