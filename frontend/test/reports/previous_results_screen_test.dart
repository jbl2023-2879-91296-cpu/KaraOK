import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/reports/presentation/pages/previous_results_screen.dart';

void main() {
  tearDown(UserSession.instance.clear);

  testWidgets(
    'selects exactly two test instances across sorting and opens that pair',
    (tester) async {
      await _pumpScreen(tester, [
        _record('Same.mp3', 'Acceptable', 81, '2026-09-01T00:00:00Z'),
        _record('Same.mp3', 'Acceptable', 82, '2026-09-02T00:00:00Z'),
        _record('Third.mp3', 'Acceptable', 83, '2026-09-03T00:00:00Z'),
      ]);
      await tester.tap(find.byKey(const Key('compareReports')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('compareSelectedReports')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('selectReport0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('historySort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest first'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('selectReport0'))).value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('selectReport1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('selectReport2')));
      await tester.pump();
      expect(
        tester.widget<Checkbox>(find.byKey(const Key('selectReport2'))).value,
        isFalse,
      );
      expect(find.text('2 of 2 selected'), findsOneWidget);
      await tester.tap(find.byKey(const Key('compareSelectedReports')));
      await tester.pumpAndSettle();
      expect(find.text('A: 81.0/100'), findsOneWidget);
      expect(find.text('B: 82.0/100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancel clears report selection and restores normal records', (
    tester,
  ) async {
    await _pumpScreen(tester, [
      _record('A', 'Acceptable', 81, '2026-09-01T00:00:00Z'),
      _record('B', 'Acceptable', 82, '2026-09-02T00:00:00Z'),
    ]);
    await tester.tap(find.byKey(const Key('compareReports')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('selectReport0')));
    await tester.pump();
    await tester.tap(find.text('Cancel selection'));
    await tester.pump();
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.byKey(const Key('compareReports')));
    await tester.pump();
    expect(find.text('0 of 2 selected'), findsOneWidget);
  });

  testWidgets('name and status controls filter records and update the count', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, [
      _record('Alpha.wav', 'Acceptable', 70.5, '2026-09-01T00:00:00Z'),
      _record('Bravo.wav', 'Needs Improvement', 80.25, '2026-09-03T00:00:00Z'),
      _record('Charlie.wav', 'Problematic', 45, '2026-09-02T00:00:00Z'),
    ]);

    expect(find.text('3 reports'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('historySearchField')),
      ' alp ',
    );
    await tester.pump();

    expect(find.text('Alpha.wav'), findsOneWidget);
    expect(find.text('Bravo.wav'), findsNothing);
    expect(find.text('1 of 3 reports'), findsOneWidget);

    await tester.tap(find.byKey(const Key('historyClearFilters')));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Problematic'));
    await tester.pump();

    expect(find.text('Charlie.wav'), findsOneWidget);
    expect(find.text('Alpha.wav'), findsNothing);
    expect(find.text('1 of 3 reports'), findsOneWidget);
  });

  testWidgets('score filter uses the entered numeric bounds', (tester) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, [
      _record('Below.wav', 'Acceptable', 79.95, '2026-09-01T00:00:00Z'),
      _record('Boundary.wav', 'Acceptable', 79.96, '2026-09-02T00:00:00Z'),
      _record('Above.wav', 'Acceptable', 80.5, '2026-09-03T00:00:00Z'),
    ]);

    await tester.tap(find.byKey(const Key('historyFiltersButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('historyMinimumScore')),
      '79.96',
    );
    await tester.enterText(
      find.byKey(const Key('historyMaximumScore')),
      '79.96',
    );
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();

    expect(find.text('Boundary.wav'), findsOneWidget);
    expect(find.text('79.96/100'), findsOneWidget);
    expect(find.text('Below.wav'), findsNothing);
    expect(find.text('Above.wav'), findsNothing);
  });

  testWidgets('date filter opens a calendar range picker', (tester) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, [
      _record('Alpha.wav', 'Acceptable', 70, '2026-09-02T00:00:00Z'),
    ]);

    await tester.tap(find.byKey(const Key('historyFiltersButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('historyDateRange')));
    await tester.pumpAndSettle();

    expect(find.byType(DateRangePickerDialog), findsOneWidget);
  });

  testWidgets('oldest sorting orders known timestamps chronologically', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, [
      _record('Older.wav', 'Acceptable', 70, '2026-09-01T00:00:00Z'),
      _record('Newer.wav', 'Acceptable', 80, '2026-09-03T00:00:00Z'),
    ]);

    await tester.tap(find.byKey(const Key('historySort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oldest first').last);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Older.wav')).dy,
      lessThan(tester.getTopLeft(find.text('Newer.wav')).dy),
    );
  });

  testWidgets('malformed record values are labelled unavailable', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, const [
      {
        'test_name': 'Damaged.wav',
        'status': '',
        'score': 'NaN',
        'created_at': 'not a date',
      },
    ]);

    expect(find.text('Damaged.wav'), findsOneWidget);
    expect(find.text('Status unavailable'), findsOneWidget);
    expect(find.text('Score unavailable'), findsOneWidget);
    expect(find.text('Date unavailable'), findsOneWidget);
  });

  testWidgets('score label does not round across a status boundary', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    await _pumpScreen(tester, [
      _record(
        'Boundary.wav',
        'Needs Improvement',
        79.9999997,
        '2026-09-02T00:00:00Z',
      ),
    ]);

    expect(find.text('79.9999997/100'), findsOneWidget);
    expect(find.text('80/100'), findsNothing);
  });

  testWidgets('load failure is shown with a retry action', (tester) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    var attempts = 0;
    await _pumpWithLoader(tester, () async {
      attempts++;
      throw Exception('offline');
    });

    expect(find.text('Couldn’t load reports'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });

  testWidgets('guest filtered empty state differs from no stored reports', (
    tester,
  ) async {
    UserSession.instance.setGuest('user');
    await _pumpScreen(tester, [
      _record('Saved.wav', 'Acceptable', 70, '2026-09-01T00:00:00Z'),
    ]);

    expect(
      find.textContaining('remain separate after you sign in'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('historySearchField')),
      'does not exist',
    );
    await tester.pump();

    expect(find.text('No reports match your filters'), findsOneWidget);
    expect(find.text('No guest reports yet'), findsNothing);
  });

  testWidgets('active filters and report values fit a phone-width screen', (
    tester,
  ) async {
    UserSession.instance.setUser(
      id: 7,
      name: 'Singer',
      email: 'singer@example.com',
      userType: 'user',
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: PreviousResultsScreen(
          resultsLoader: () async => [
            _record(
              'Phone recording.wav',
              'Needs Improvement',
              79.9999997,
              '2026-09-02T00:00:00Z',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('historySearchField')),
      'phone',
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Phone recording.wav'), findsOneWidget);
  });
}

Future<void> _pumpScreen(WidgetTester tester, List<dynamic> records) =>
    _pumpWithLoader(tester, () async => records);

Future<void> _pumpWithLoader(
  WidgetTester tester,
  PreviousResultsLoader loader,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(800, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(home: PreviousResultsScreen(resultsLoader: loader)),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _record(
  String name,
  String status,
  num score,
  String createdAt,
) => {
  'test_name': name,
  'status': status,
  'score': score,
  'created_at': createdAt,
};
