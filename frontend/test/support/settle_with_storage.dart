import 'package:flutter_test/flutter_test.dart';

/// Let platform-channel futures and real filesystem IO complete between frames.
Future<void> settleWithStorage(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}
