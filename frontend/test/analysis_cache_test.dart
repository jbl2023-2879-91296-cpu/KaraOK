import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/password_policy.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/analysis_cache.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';

void main() {
  late Directory supportDirectory;
  late AnalysisCache cache;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'karaok-analysis-cache-',
    );
    cache = AnalysisCache(
      supportDirectoryProvider: () async => supportDirectory,
    );
    UserSession.instance.setUser(
      id: 7,
      name: 'Cache User',
      email: 'cache@example.com',
      userType: 'user',
    );
  });

  tearDown(() async {
    UserSession.instance.clear();
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('history metadata persists per authenticated user', () async {
    final history = <dynamic>[
      {'id': 11, 'test_name': 'Cached analysis', 'score': 88},
    ];

    await cache.saveHistory(history);

    expect(await cache.readHistory(), history);
  });

  test('visualization downloads once and survives cache recreation', () async {
    var fetchCount = 0;
    final expected = Uint8List.fromList([1, 2, 3, 4]);

    final first = await cache.visualization(
      assessmentId: 11,
      kind: 'waveform',
      fetch: () async {
        fetchCount++;
        return expected;
      },
    );
    final recreatedCache = AnalysisCache(
      supportDirectoryProvider: () async => supportDirectory,
    );
    final second = await recreatedCache.visualization(
      assessmentId: 11,
      kind: 'waveform',
      fetch: () async {
        fetchCount++;
        return Uint8List(0);
      },
    );

    expect(first, expected);
    expect(second, expected);
    expect(fetchCount, 1);
  });

  test('password policy requires exactly eight mixed characters', () {
    expect(PasswordPolicy.validate('Good#A1b'), isNull);
    expect(PasswordPolicy.validate('Good#A1'), isNotNull);
    expect(PasswordPolicy.validate('Good#A1bc'), isNotNull);
    expect(PasswordPolicy.validate('abcdefgh'), isNotNull);
  });

  test(
    'guest reports persist locally and remain after account claim',
    () async {
      final guestStore = GuestAssessmentStore(
        supportDirectoryProvider: () async => supportDirectory,
      );
      final image = base64Encode(Uint8List.fromList([1, 2, 3, 4]));
      await guestStore.saveCompleted({
        'test_name': 'Guest evaluation',
        'status': 'Acceptable',
        'score': 84,
        'guest_import_receipt': 'signed-receipt',
        'visualizations': {'waveform': image, 'spectrogram': image},
      });

      final history = await guestStore.guestHistory();
      expect(history, hasLength(1));
      expect(history.single['test_name'], 'Guest evaluation');
      expect(history.single['visualizations']['waveform'], image);

      await guestStore.claimUnownedForUser(7);
      expect(await guestStore.guestHistory(), isEmpty);
      final pending = await guestStore.pendingForUser(7);
      expect(pending, hasLength(1));
      final localId = pending.single['local_guest_id'].toString();
      await guestStore.markSynced(localId: localId, assessmentId: 41);

      expect(await guestStore.pendingForUser(7), isEmpty);
      expect(
        await guestStore.visualizationBytes(localId, 'waveform'),
        Uint8List.fromList([1, 2, 3, 4]),
      );
    },
  );
}
