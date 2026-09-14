enum ReportHistorySort { newest, oldest }

class ReportHistoryQuery {
  const ReportHistoryQuery({
    this.name = '',
    this.status,
    this.minimumScore,
    this.maximumScore,
    this.startDate,
    this.endDate,
    this.sortOrder = ReportHistorySort.newest,
  });

  final String name;
  final String? status;
  final double? minimumScore;
  final double? maximumScore;
  final DateTime? startDate;
  final DateTime? endDate;
  final ReportHistorySort sortOrder;

  bool get hasFilters =>
      name.trim().isNotEmpty ||
      status != null ||
      minimumScore != null ||
      maximumScore != null ||
      startDate != null ||
      endDate != null;
}

class ReportHistoryEntry {
  ReportHistoryEntry._({
    required this.raw,
    required this.name,
    required this.status,
    required this.score,
    required this.createdAt,
    required this.sourceIndex,
  });

  factory ReportHistoryEntry.fromRaw(
    Map<dynamic, dynamic> raw, {
    int sourceIndex = 0,
  }) {
    return ReportHistoryEntry._(
      raw: raw,
      name: _nonEmptyString(raw['test_name']),
      status: _nonEmptyString(raw['status']),
      score: _finiteDouble(raw['score']),
      createdAt: _parseTimestamp(raw['created_at']),
      sourceIndex: sourceIndex,
    );
  }

  final Map<dynamic, dynamic> raw;
  final String? name;
  final String? status;
  final double? score;
  final DateTime? createdAt;
  final int sourceIndex;
}

List<ReportHistoryEntry> filterReportHistory(
  List<dynamic> records,
  ReportHistoryQuery query,
) {
  final searchedName = query.name.trim().toLowerCase();
  final start = query.startDate == null
      ? null
      : DateTime(
          query.startDate!.year,
          query.startDate!.month,
          query.startDate!.day,
        );
  final endExclusive = query.endDate == null
      ? null
      : DateTime(
          query.endDate!.year,
          query.endDate!.month,
          query.endDate!.day + 1,
        );

  final entries = <ReportHistoryEntry>[];
  for (var index = 0; index < records.length; index++) {
    final raw = records[index];
    if (raw is! Map) continue;
    final entry = ReportHistoryEntry.fromRaw(raw, sourceIndex: index);
    if (searchedName.isNotEmpty &&
        !(entry.name?.toLowerCase().contains(searchedName) ?? false)) {
      continue;
    }
    if (query.status != null && entry.status != query.status) continue;
    if (query.minimumScore != null &&
        (entry.score == null || entry.score! < query.minimumScore!)) {
      continue;
    }
    if (query.maximumScore != null &&
        (entry.score == null || entry.score! > query.maximumScore!)) {
      continue;
    }
    if (start != null || endExclusive != null) {
      final localDate = entry.createdAt?.toLocal();
      if (localDate == null) continue;
      if (start != null && localDate.isBefore(start)) continue;
      if (endExclusive != null && !localDate.isBefore(endExclusive)) continue;
    }
    entries.add(entry);
  }

  entries.sort((left, right) {
    final leftDate = left.createdAt;
    final rightDate = right.createdAt;
    if (leftDate == null && rightDate == null) {
      return left.sourceIndex.compareTo(right.sourceIndex);
    }
    if (leftDate == null) return 1;
    if (rightDate == null) return -1;
    final comparison = leftDate.compareTo(rightDate);
    if (comparison == 0) return left.sourceIndex.compareTo(right.sourceIndex);
    return query.sortOrder == ReportHistorySort.newest
        ? -comparison
        : comparison;
  });
  return entries;
}

String? _nonEmptyString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

double? _finiteDouble(Object? value) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String string => double.tryParse(string.trim()),
    _ => null,
  };
  return parsed?.isFinite == true ? parsed : null;
}

DateTime? _parseTimestamp(Object? value) {
  if (value is DateTime) return value;
  if (value is! String || value.trim().isEmpty) return null;
  final text = value.trim();
  final isoDate = RegExp(r'^([+-]?\d{4,6})-(\d{2})-(\d{2})').firstMatch(text);
  if (isoDate != null) {
    final year = int.parse(isoDate.group(1)!);
    final month = int.parse(isoDate.group(2)!);
    final day = int.parse(isoDate.group(3)!);
    final calendarDate = DateTime.utc(year, month, day);
    if (calendarDate.year != year ||
        calendarDate.month != month ||
        calendarDate.day != day) {
      return null;
    }
    final isoTime = RegExp(
      r'^[+-]?\d{4,6}-\d{2}-\d{2}[T ](\d{2})(?::?(\d{2}))?(?::?(\d{2}))?',
    ).firstMatch(text);
    if (isoTime != null &&
        (int.parse(isoTime.group(1)!) > 23 ||
            int.parse(isoTime.group(2) ?? '0') > 59 ||
            int.parse(isoTime.group(3) ?? '0') > 59)) {
      return null;
    }
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso;
  return _tryParseRfc1123(text);
}

DateTime? _tryParseRfc1123(String text) {
  const months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };
  const weekdays = {
    'Mon': DateTime.monday,
    'Tue': DateTime.tuesday,
    'Wed': DateTime.wednesday,
    'Thu': DateTime.thursday,
    'Fri': DateTime.friday,
    'Sat': DateTime.saturday,
    'Sun': DateTime.sunday,
  };
  final match = RegExp(
    r'^(Mon|Tue|Wed|Thu|Fri|Sat|Sun), (\d{2}) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(text);
  if (match == null) return null;
  final day = int.parse(match.group(2)!);
  final month = months[match.group(3)]!;
  final year = int.parse(match.group(4)!);
  final hour = int.parse(match.group(5)!);
  final minute = int.parse(match.group(6)!);
  final second = int.parse(match.group(7)!);
  if (hour > 23 || minute > 59 || second > 59) return null;
  final timestamp = DateTime.utc(year, month, day, hour, minute, second);
  if (timestamp.year != year ||
      timestamp.month != month ||
      timestamp.day != day ||
      timestamp.weekday != weekdays[match.group(1)]) {
    return null;
  }
  return timestamp;
}
