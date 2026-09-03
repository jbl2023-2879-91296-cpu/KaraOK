import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/network/api_exception.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_settings_suggestion_screen.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/sound_settings/data/guest_amplifier_store.dart';
import 'package:karaok_app/features/sound_settings/data/settings_api.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_profile_metadata.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';
import 'package:karaok_app/features/sound_settings/presentation/pages/settings_setup_screen.dart';

void main() {
  late _FakeSettingsApi settingsApi;
  late _FakeGuestAmplifierStore guestStore;

  setUp(() {
    UserSession.instance.setGuest('user');
    settingsApi = _FakeSettingsApi();
    guestStore = _FakeGuestAmplifierStore();
  });

  tearDown(UserSession.instance.clear);

  _tallTestWidgets('requires genre and all five current positions', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('settings-continue')));
    await tester.tap(find.byKey(const Key('settings-continue')));
    await tester.pump();

    expect(find.text('Select a genre.'), findsOneWidget);
    expect(find.text('Enter all five current knob positions.'), findsOneWidget);
  });

  _tallTestWidgets(
    'builds normalized suggestion input and saves guest profile',
    (tester) async {
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillGenreAndFivePositions(tester);
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(submitted, isNotNull);
      expect(submitted!.genre, 'rock');
      expect(submitted!.current.bass, 4);
      expect(
        submitted!.amplifierScale,
        const AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
      );
      expect(guestStore.saved?.name, 'My Amplifier');
      expect(guestStore.saved?.lastPositions?.treble, 6);
    },
  );

  _tallTestWidgets('renders only genres enabled by profile metadata', (
    tester,
  ) async {
    settingsApi.enabledGenres = const ['hip-hop', 'rock'];
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('genre-dropdown')));
    await tester.pumpAndSettle();

    expect(find.text('Rock'), findsOneWidget);
    expect(find.text('Hip-Hop'), findsOneWidget);
    expect(find.text('Classical'), findsNothing);
    expect(find.text('Pop'), findsNothing);
  });

  _tallTestWidgets(
    'keeps genre selection available when saved profiles fail to load',
    (tester) async {
      UserSession.instance.setUser(
        id: 7,
        name: 'Singer',
        email: 'singer@example.com',
        userType: 'user',
      );
      settingsApi.profilesError = const ApiException(
        500,
        'Could not load profiles.',
      );

      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('genre-dropdown')));
      await tester.tap(find.byKey(const Key('genre-dropdown')));
      await tester.pumpAndSettle();

      expect(find.text('Rock'), findsOneWidget);
      expect(
        find.text(
          'Saved amplifier profiles could not be loaded. '
          'You can still create a new amplifier.',
        ),
        findsOneWidget,
      );
      final continueButton = tester.widget<FilledButton>(
        find.byKey(const Key('settings-continue')),
      );
      expect(continueButton.onPressed, isNotNull);
    },
  );

  _tallTestWidgets('disabled metadata endpoint disables setup continuation', (
    tester,
  ) async {
    settingsApi.metadataError = const ApiException(404, 'Not found');
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings generation is not enabled'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('settings-continue')),
    );
    expect(button.onPressed, isNull);
  });

  _tallTestWidgets('retry reloads genres after a temporary metadata failure', (
    tester,
  ) async {
    settingsApi.metadataError = const ApiException(503, 'Service unavailable.');
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load settings profiles.'), findsOneWidget);
    settingsApi.metadataError = null;
    await tester.tap(find.byKey(const Key('settings-load-retry')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('genre-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('Hip-Hop'), findsOneWidget);
    expect(find.text('Pop'), findsOneWidget);
    expect(find.text('Rock'), findsOneWidget);
  });

  _tallTestWidgets(
    'authenticated setup creates My Amplifier before continuing',
    (tester) async {
      UserSession.instance.setUser(
        id: 7,
        name: 'Singer',
        email: 'singer@example.com',
        userType: 'user',
      );
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillGenreAndFivePositions(tester);
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(settingsApi.created?.name, 'My Amplifier');
      expect(settingsApi.created?.lastPositions?.flatness, 5);
      expect(submitted?.amplifierProfileId, 22);
      expect(submitted?.amplifierScale, isNull);
    },
  );

  _tallTestWidgets(
    'authenticated users can create an amplifier when profiles already exist',
    (tester) async {
      UserSession.instance.setUser(
        id: 7,
        name: 'Singer',
        email: 'singer@example.com',
        userType: 'user',
      );
      settingsApi.profiles = const [
        AmplifierProfile(
          id: 9,
          name: 'Living Room',
          scale: AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
        ),
      ];
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('amplifier-profile-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create My Amplifier').last);
      await tester.pumpAndSettle();
      await _fillGenreAndFivePositions(tester);
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(settingsApi.created?.name, 'My Amplifier');
      expect(submitted?.amplifierProfileId, 22);
    },
  );

  _tallTestWidgets('shows controlled recording guidance', (tester) async {
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Play the same karaoke instrumental song section for both recordings.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Play only the instrumental or MIDI accompaniment.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Keep the phone in the same position relative to the speakers.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Keep the room and playback source unchanged.'),
      findsOneWidget,
    );
  });

  _tallTestWidgets('orchestrator carries setup input into recording builder', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        AudioSettingsSuggestionScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          audioScreenBuilder: (input) => Scaffold(
            body: Text('Recording ${input.genre} bass ${input.current.bass}'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _fillGenreAndFivePositions(tester);
    await tester.ensureVisible(find.byKey(const Key('settings-continue')));
    await tester.tap(find.byKey(const Key('settings-continue')));
    await tester.pumpAndSettle();

    expect(find.text('Recording rock bass 4.0'), findsOneWidget);
  });

  _tallTestWidgets(
    'default recording screen retains the complete setup input',
    (tester) async {
      await tester.pumpWidget(
        _testApp(
          AudioSettingsSuggestionScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _fillGenreAndFivePositions(tester);
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      final audioScreen = tester.widget<AudioTestScreen>(
        find.byType(AudioTestScreen),
      );
      expect(audioScreen.purpose, AudioAnalysisPurpose.settingsSuggestion);
      expect(audioScreen.settingsSuggestion?.genre, 'rock');
      expect(audioScreen.settingsSuggestion?.current.flatness, 5);
    },
  );

  _tallTestWidgets('changing a populated preset requires explicit rescaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('knob-volume')), '5');

    await tester.tap(find.byKey(const Key('scale-preset-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('0–100').last);
    await tester.pumpAndSettle();

    expect(find.text('Change amplifier scale?'), findsOneWidget);
    expect(find.text('Rescale Values'), findsOneWidget);
    expect(find.text('Keep Values'), findsOneWidget);

    await tester.tap(find.text('Rescale Values'));
    await tester.pumpAndSettle();
    final volume = tester.widget<TextFormField>(
      find.byKey(const Key('knob-volume')),
    );
    expect(volume.controller?.text, '50');
  });

  _tallTestWidgets(
    '0-100 preset applies its scale to five submitted positions',
    (tester) async {
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scale-preset-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0–100').last);
      await tester.pumpAndSettle();
      await _selectGenre(tester, 'Rock');
      await _enterPositions(tester, const {
        'volume': '55',
        'bass': '40',
        'treble': '60',
        'sharpness': '50',
        'flatness': '50',
      });
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(submitted?.amplifierScale?.maximum, 100);
      expect(submitted?.current.volume, 55);
    },
  );

  for (final scenario
      in <
        ({
          String name,
          Future<void> Function(WidgetTester) selectScale,
          Map<String, String> expected,
        })
      >[
        (
          name: '0-10',
          selectScale: (_) async {},
          expected: const {
            'volume': '4',
            'bass': '5',
            'treble': '5',
            'sharpness': '5',
            'flatness': '5',
          },
        ),
        (
          name: '0-100',
          selectScale: (tester) => _selectScale(tester, '0–100'),
          expected: const {
            'volume': '40',
            'bass': '50',
            'treble': '50',
            'sharpness': '50',
            'flatness': '50',
          },
        ),
        (
          name: 'custom 2-12',
          selectScale: (tester) async {
            await _selectScale(tester, 'Custom');
            await tester.enterText(find.byKey(const Key('scale-minimum')), '2');
            await tester.enterText(
              find.byKey(const Key('scale-maximum')),
              '12',
            );
            await tester.enterText(find.byKey(const Key('scale-step')), '0.5');
            await tester.pump();
          },
          expected: const {
            'volume': '6',
            'bass': '7',
            'treble': '7',
            'sharpness': '7',
            'flatness': '7',
          },
        ),
      ]) {
    _tallTestWidgets(
      'researched starting point uses the ${scenario.name} scale',
      (tester) async {
        await tester.pumpWidget(
          _testApp(
            SettingsSetupScreen(
              settingsApi: settingsApi,
              guestStore: guestStore,
              onContinue: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await scenario.selectScale(tester);

        await tester.ensureVisible(
          find.byKey(const Key('use-researched-starting-point')),
        );
        await tester.tap(
          find.byKey(const Key('use-researched-starting-point')),
        );
        await tester.pump();

        for (final entry in scenario.expected.entries) {
          expect(_knobText(tester, entry.key), entry.value);
        }
        expect(
          find.byKey(const Key('starting-point-acknowledgement')),
          findsOneWidget,
        );
      },
    );
  }

  _tallTestWidgets(
    'saved positions load without automatic starting-point replacement',
    (tester) async {
      guestStore.stored = const AmplifierProfile(
        name: 'My Amplifier',
        scale: AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
        lastPositions: KnobSettings(
          volume: 8,
          bass: 3,
          treble: 6,
          sharpness: 4,
          flatness: 2,
        ),
      );

      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_knobText(tester, 'volume'), '8');
      expect(_knobText(tester, 'bass'), '3');
      expect(_knobText(tester, 'flatness'), '2');
      expect(
        find.byKey(const Key('starting-point-acknowledgement')),
        findsNothing,
      );
    },
  );

  _tallTestWidgets(
    'switching to a profile without positions clears every inherited knob and acknowledgement',
    (tester) async {
      UserSession.instance.setUser(
        id: 7,
        name: 'Singer',
        email: 'singer@example.com',
        userType: 'user',
      );
      settingsApi.profiles = const [
        AmplifierProfile(
          id: 9,
          name: 'Populated 0-100',
          scale: AmplifierScale(minimum: 0, maximum: 100, step: 1),
          lastPositions: KnobSettings(
            volume: 40,
            bass: 50,
            treble: 60,
            sharpness: 70,
            flatness: 80,
          ),
        ),
        AmplifierProfile(
          id: 10,
          name: 'Empty 0-10',
          scale: AmplifierScale(minimum: 0, maximum: 10, step: 0.5),
        ),
      ];
      await tester.pumpWidget(_testApp(SettingsSetupScreen(
        settingsApi: settingsApi,
        guestStore: guestStore,
        onContinue: (_) {},
      )));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('use-researched-starting-point')),
      );
      await tester.tap(find.byKey(const Key('use-researched-starting-point')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('starting-point-acknowledgement')),
      );
      await tester.tap(find.byKey(const Key('starting-point-acknowledgement')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('amplifier-profile-dropdown')),
      );
      await tester.tap(find.byKey(const Key('amplifier-profile-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty 0-10').last);
      await tester.pumpAndSettle();

      for (final name in ['volume', 'bass', 'treble', 'sharpness', 'flatness']) {
        expect(_knobText(tester, name), isEmpty);
      }
      expect(find.byKey(const Key('starting-point-acknowledgement')), findsNothing);
    },
  );

  _tallTestWidgets(
    'researched positions require physical acknowledgement before continuing',
    (tester) async {
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectGenre(tester, 'Rock');
      await tester.tap(find.byKey(const Key('use-researched-starting-point')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pump();

      expect(submitted, isNull);
      expect(
        find.text(
          'Confirm that the five physical controls match these positions.',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('starting-point-acknowledgement')),
      );
      await tester.tap(find.byKey(const Key('starting-point-acknowledgement')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(submitted?.current.volume, 4);
      expect(guestStore.saved?.lastPositions?.bass, 5);
    },
  );

  _tallTestWidgets(
    'authenticated researched positions continue after acknowledgement',
    (tester) async {
      UserSession.instance.setUser(
        id: 7,
        name: 'Test User',
        email: 'test@example.com',
        userType: 'user',
      );
      SettingsSuggestionInput? submitted;
      await tester.pumpWidget(
        _testApp(
          SettingsSetupScreen(
            settingsApi: settingsApi,
            guestStore: guestStore,
            onContinue: (value) => submitted = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectGenre(tester, 'Rock');
      await tester.tap(find.byKey(const Key('use-researched-starting-point')));
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('starting-point-acknowledgement')),
      );
      await tester.tap(find.byKey(const Key('starting-point-acknowledgement')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('settings-continue')));
      await tester.tap(find.byKey(const Key('settings-continue')));
      await tester.pumpAndSettle();

      expect(settingsApi.created?.lastPositions?.volume, 4);
      expect(submitted?.amplifierProfileId, 22);
    },
  );

  _tallTestWidgets('editing a researched knob clears acknowledgement', (
    tester,
  ) async {
    await _pumpAndAcknowledgeStartingPoint(tester, settingsApi, guestStore);

    await tester.enterText(find.byKey(const Key('knob-volume')), '4.5');
    await tester.pump();

    expect(
      find.byKey(const Key('starting-point-acknowledgement')),
      findsNothing,
    );
  });

  _tallTestWidgets('changing scale after acknowledgement clears it', (
    tester,
  ) async {
    await _pumpAndAcknowledgeStartingPoint(tester, settingsApi, guestStore);

    await _selectScale(tester, 'Custom');

    expect(
      find.byKey(const Key('starting-point-acknowledgement')),
      findsNothing,
    );
  });

  _tallTestWidgets('manual positions do not require acknowledgement', (
    tester,
  ) async {
    SettingsSuggestionInput? submitted;
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (value) => submitted = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _fillGenreAndFivePositions(tester);

    expect(
      find.byKey(const Key('starting-point-acknowledgement')),
      findsNothing,
    );
    await tester.ensureVisible(find.byKey(const Key('settings-continue')));
    await tester.tap(find.byKey(const Key('settings-continue')));
    await tester.pumpAndSettle();

    expect(submitted, isNotNull);
  });

  _tallTestWidgets('uses instrumental-only controlled-comparison copy', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        SettingsSetupScreen(
          settingsApi: settingsApi,
          guestStore: guestStore,
          onContinue: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final renderedCopy = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n')
        .toLowerCase();
    expect(renderedCopy, contains('karaoke instrumental playback'));
    expect(renderedCopy, isNot(contains('singer')));
    expect(renderedCopy, isNot(contains('microphone direction')));
    expect(
      find.text('Play only the instrumental or MIDI accompaniment.'),
      findsOneWidget,
    );
  });

  test('settings upload describes rendered instrumental audio', () {
    expect(
      AudioAnalysisPurpose.settingsSuggestion.description,
      'Record the karaoke machine\'s rendered instrumental playback or '
      'select a rendered audio file to generate five amplifier settings.',
    );
  });
}

Widget _testApp(Widget home) => MaterialApp(home: home);

void _tallTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    addTearDown(tester.view.resetPhysicalSize);
    await callback(tester);
  });
}

Future<void> _fillGenreAndFivePositions(WidgetTester tester) async {
  await _selectGenre(tester, 'Rock');
  await _enterPositions(tester, const {
    'volume': '5',
    'bass': '4',
    'treble': '6',
    'sharpness': '5',
    'flatness': '5',
  });
}

Future<void> _selectGenre(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byKey(const Key('genre-dropdown')));
  await tester.tap(find.byKey(const Key('genre-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _enterPositions(
  WidgetTester tester,
  Map<String, String> values,
) async {
  for (final entry in values.entries) {
    final field = find.byKey(Key('knob-${entry.key}'));
    await tester.ensureVisible(field);
    await tester.enterText(field, entry.value);
  }
  await tester.pump();
}

String _knobText(WidgetTester tester, String name) {
  final field = tester.widget<TextFormField>(find.byKey(Key('knob-$name')));
  return field.controller!.text;
}

Future<void> _selectScale(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byKey(const Key('scale-preset-dropdown')));
  await tester.tap(find.byKey(const Key('scale-preset-dropdown')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _pumpAndAcknowledgeStartingPoint(
  WidgetTester tester,
  SettingsApi settingsApi,
  GuestAmplifierStore guestStore,
) async {
  await tester.pumpWidget(
    _testApp(
      SettingsSetupScreen(
        settingsApi: settingsApi,
        guestStore: guestStore,
        onContinue: (_) {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const Key('use-researched-starting-point')),
  );
  await tester.tap(find.byKey(const Key('use-researched-starting-point')));
  await tester.pump();
  await tester.ensureVisible(
    find.byKey(const Key('starting-point-acknowledgement')),
  );
  await tester.tap(find.byKey(const Key('starting-point-acknowledgement')));
  await tester.pump();
}

class _FakeSettingsApi extends SettingsApi {
  List<String> enabledGenres = const ['hip-hop', 'pop', 'rock'];
  ApiException? metadataError;
  ApiException? profilesError;
  List<AmplifierProfile> profiles = const [];
  AmplifierProfile? created;

  @override
  Future<SettingsProfileMetadata> getProfileMetadata() async {
    if (metadataError case final error?) throw error;
    final metadata = Map<String, dynamic>.from(
      jsonDecode(
            File(
              'test/fixtures/settings_profile_metadata_response.json',
            ).readAsStringSync(),
          )
          as Map,
    )..['enabled_genres'] = enabledGenres;
    return SettingsProfileMetadata.fromJson(metadata);
  }

  @override
  Future<List<AmplifierProfile>> listProfiles() async {
    if (profilesError case final error?) throw error;
    return profiles;
  }

  @override
  Future<AmplifierProfile> createProfile(AmplifierProfile profile) async {
    created = profile;
    return AmplifierProfile(
      id: 22,
      name: profile.name,
      scale: profile.scale,
      lastPositions: profile.lastPositions,
    );
  }
}

class _FakeGuestAmplifierStore extends GuestAmplifierStore {
  _FakeGuestAmplifierStore()
    : super(directoryProvider: () async => Directory.systemTemp);

  AmplifierProfile? stored;
  AmplifierProfile? saved;

  @override
  Future<AmplifierProfile?> read() async => stored;

  @override
  Future<void> save(AmplifierProfile profile) async {
    saved = profile;
    stored = profile;
  }
}
