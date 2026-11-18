import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/presentation/pages/results_screen.dart';
import 'package:karaok_app/features/reports/presentation/widgets/noise_guard_card.dart';

void main() {
  Future<void> showCard(WidgetTester tester, NoiseGuardCard card) {
    return tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));
  }

  testWidgets('shows high confidence and the usable percentage', (
    tester,
  ) async {
    await showCard(
      tester,
      const NoiseGuardCard(
        usablePercentage: 96,
        confidence: 'high',
        prerollNoiseDbfs: -48,
      ),
    );

    expect(find.text('Noise guard: High confidence'), findsOneWidget);
    expect(find.text('96% of the recording was used'), findsOneWidget);
  });

  testWidgets('gives placement advice with low confidence', (tester) async {
    await showCard(
      tester,
      const NoiseGuardCard(
        usablePercentage: 75,
        confidence: 'low',
        prerollNoiseDbfs: -33,
      ),
    );

    expect(find.text('Noise guard: Low confidence'), findsOneWidget);
    expect(
      find.text(
        'Results may be affected by background noise. Try again closer to the speaker.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('explains when the noise check is unusable', (tester) async {
    await showCard(
      tester,
      const NoiseGuardCard(
        usablePercentage: 99,
        confidence: 'medium',
        prerollNoiseDbfs: null,
      ),
    );

    expect(
      find.text('No usable background-noise check'),
      findsOneWidget,
    );
  });

  testWidgets('leaves legacy reports without a card', (tester) async {
    await showCard(
      tester,
      const NoiseGuardCard(
        usablePercentage: null,
        confidence: null,
        prerollNoiseDbfs: null,
      ),
    );

    expect(find.byType(Card), findsNothing);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows the supplied warnings verbatim', (tester) async {
    await showCard(
      tester,
      const NoiseGuardCard(
        usablePercentage: 82,
        confidence: 'medium',
        prerollNoiseDbfs: -39,
        warnings: [
          'Ambient noise detected.',
          'Some sudden sounds were skipped.',
        ],
      ),
    );

    expect(find.text('Ambient noise detected.'), findsOneWidget);
    expect(find.text('Some sudden sounds were skipped.'), findsOneWidget);
  });

  testWidgets('opens the noise guard card from a new result', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'score': 86,
          'noise_guard_usable_percentage': 96.1,
          'noise_guard_confidence': 'high',
          'preroll_noise_dbfs': -48.0,
          'noise_guard_warnings': ['Some sudden sounds were skipped.'],
        }),
      ),
    );
    await tester.ensureVisible(find.text('View Visual Report'));
    await tester.tap(find.text('View Visual Report'));
    await tester.pumpAndSettle();

    expect(find.text('Noise guard: High confidence'), findsOneWidget);
    expect(find.text('96% of the recording was used'), findsOneWidget);
    expect(find.text('Some sudden sounds were skipped.'), findsOneWidget);
  });

  testWidgets('opens the noise guard card from a saved result', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ResultsScreen.fromRecord({
          'score': 86,
          'noise_guard_usable_percentage': '98',
          'noise_guard_confidence': 'medium',
          'preroll_noise_dbfs': null,
        }),
      ),
    );
    await tester.ensureVisible(find.text('View Visual Report'));
    await tester.tap(find.text('View Visual Report'));
    await tester.pumpAndSettle();

    expect(find.text('Noise guard: Medium confidence'), findsOneWidget);
    expect(find.text('98% of the recording was used'), findsOneWidget);
    expect(
      find.text('No usable background-noise check'),
      findsOneWidget,
    );
  });
}
