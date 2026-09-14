import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/features/reports/domain/report_history.dart';

void main() {
  group('ReportHistoryEntry', () {
    test('parses ISO and Flask RFC timestamps as real instants', () {
      final iso = ReportHistoryEntry.fromRaw(const {
        'test_name': 'ISO',
        'created_at': '2026-09-02T03:04:05Z',
      });
      final rfc = ReportHistoryEntry.fromRaw(const {
        'test_name': 'RFC',
        'created_at': 'Wed, 02 Sep 2026 03:04:05 GMT',
      });

      expect(iso.createdAt, DateTime.utc(2026, 9, 2, 3, 4, 5));
      expect(rfc.createdAt, DateTime.utc(2026, 9, 2, 3, 4, 5));
    });

    test('does not invent values for malformed fields', () {
      final malformed = ReportHistoryEntry.fromRaw(const {
        'test_name': 19,
        'status': '   ',
        'score': 'NaN',
        'created_at': 'not a timestamp',
      });
      final infinite = ReportHistoryEntry.fromRaw(const {
        'score': double.infinity,
      });

      expect(malformed.name, isNull);
      expect(malformed.status, isNull);
      expect(malformed.score, isNull);
      expect(malformed.createdAt, isNull);
      expect(infinite.score, isNull);
    });

    test('rejects ISO timestamps with impossible calendar dates', () {
      final entry = ReportHistoryEntry.fromRaw(const {
        'created_at': '2026-02-30T08:30:00Z',
      });

      expect(entry.createdAt, isNull);
    });
  });

  group('filterReportHistory', () {
    test('combines name, status, and inclusive numeric score bounds', () {
      final records = [
        _record('Warm Up.wav', 'Acceptable', 70, '2026-09-01T00:00:00Z'),
        _record(
          'Warm Mix.wav',
          'Needs Improvement',
          80,
          '2026-09-02T00:00:00Z',
        ),
        _record('Final Mix.wav', 'Acceptable', 90, '2026-09-03T00:00:00Z'),
      ];

      final result = filterReportHistory(
        records,
        const ReportHistoryQuery(
          name: ' warm ',
          status: 'Acceptable',
          minimumScore: 70,
          maximumScore: 70,
        ),
      );

      expect(result.map((entry) => entry.name), ['Warm Up.wav']);
    });

    test('uses inclusive local calendar bounds for timestamped records', () {
      final localDay = DateTime(2026, 9, 2);
      final atStart = localDay.toUtc().toIso8601String();
      final atEnd = localDay
          .add(const Duration(days: 1))
          .subtract(const Duration(milliseconds: 1))
          .toUtc()
          .toIso8601String();
      final before = localDay
          .subtract(const Duration(milliseconds: 1))
          .toUtc()
          .toIso8601String();

      final result = filterReportHistory([
        _record('start', 'Acceptable', 1, atStart),
        _record('end', 'Acceptable', 2, atEnd),
        _record('before', 'Acceptable', 3, before),
      ], ReportHistoryQuery(startDate: localDay, endDate: localDay));

      expect(result.map((entry) => entry.name), ['end', 'start']);
    });

    test('sorts chronologically and keeps unknown dates at the end', () {
      final records = [
        _record('unknown first', 'Acceptable', 1, 'bad'),
        _record('older', 'Acceptable', 2, '2026-09-01T00:00:00Z'),
        _record('unknown second', 'Acceptable', 3, null),
        _record('newer', 'Acceptable', 4, '2026-09-03T00:00:00Z'),
      ];

      final newest = filterReportHistory(records, const ReportHistoryQuery());
      final oldest = filterReportHistory(
        records,
        const ReportHistoryQuery(sortOrder: ReportHistorySort.oldest),
      );

      expect(newest.map((entry) => entry.name), [
        'newer',
        'older',
        'unknown first',
        'unknown second',
      ]);
      expect(oldest.map((entry) => entry.name), [
        'older',
        'newer',
        'unknown first',
        'unknown second',
      ]);
    });

    test('excludes records missing required filter values', () {
      final result = filterReportHistory([
        const {'test_name': 'missing all'},
        const {'test_name': 'missing score', 'status': 'Acceptable'},
        const {'test_name': 'missing status', 'score': 88},
        const {'test_name': 'complete', 'status': 'Acceptable', 'score': 88},
      ], const ReportHistoryQuery(status: 'Acceptable', minimumScore: 80));

      expect(result.map((entry) => entry.name), ['complete']);
    });
  });
}

Map<String, dynamic> _record(
  String name,
  String status,
  num score,
  String? createdAt,
) => {
  'test_name': name,
  'status': status,
  'score': score,
  'created_at': createdAt,
};
