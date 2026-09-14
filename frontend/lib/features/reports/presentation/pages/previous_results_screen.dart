import 'report_comparison_screen.dart';
import 'package:flutter/material.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/guest_assessment_store.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';
import 'package:karaok_app/features/assessments/data/assessment_api.dart';
import 'package:karaok_app/features/assessments/presentation/pages/audio_test_screen.dart';
import 'package:karaok_app/features/reports/domain/report_history.dart';
import 'package:karaok_app/features/reports/domain/report_values.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

typedef PreviousResultsLoader = Future<List<dynamic>> Function();

class PreviousResultsScreen extends StatefulWidget {
  const PreviousResultsScreen({
    super.key,
    this.title = 'Reports',
    this.accentColor = const Color(0xFF4A90D9),
    this.resultsLoader,
  });

  final String title;
  final Color accentColor;
  final PreviousResultsLoader? resultsLoader;

  @override
  State<PreviousResultsScreen> createState() => _PreviousResultsScreenState();
}

class _PreviousResultsScreenState extends State<PreviousResultsScreen> {
  static const _standardStatuses = [
    'Acceptable',
    'Needs Improvement',
    'Problematic',
  ];

  final _searchController = TextEditingController();
  String? _status;
  double? _minimumScore;
  double? _maximumScore;
  DateTime? _startDate;
  DateTime? _endDate;
  ReportHistorySort _sortOrder = ReportHistorySort.newest;
  List<dynamic> _results = [];
  bool _selectingReports = false;
  final List<int> _selectedReports = [];
  bool _loading = !UserSession.instance.isGuest;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading =
            _results.isEmpty &&
            !(UserSession.instance.isGuest && widget.resultsLoader == null);
        _loadError = null;
        _selectedReports.clear();
        _selectingReports = false;
      });
    }
    if (widget.resultsLoader case final loader?) {
      try {
        final tests = await loader();
        if (!mounted) return;
        setState(() {
          _results = tests;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = 'Couldn’t load reports';
        });
      }
      return;
    }
    if (UserSession.instance.isGuest) {
      try {
        final tests = await GuestAssessmentStore.instance.guestHistory();
        if (!mounted) return;
        setState(() {
          _results = tests;
          _loading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = 'Couldn’t load reports';
        });
      }
      return;
    }

    final api = AssessmentApi();
    final cached = await api.getCachedAudioTests();
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _results = cached;
        _loading = false;
      });
    }
    try {
      final tests = await api.getAudioTests();
      if (!mounted) return;
      setState(() {
        _results = tests;
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _results.isEmpty
            ? 'Couldn’t load reports'
            : 'Couldn’t refresh reports. Showing saved reports.';
      });
    }
  }

  ReportHistoryQuery get _query => ReportHistoryQuery(
    name: _searchController.text,
    status: _status,
    minimumScore: _minimumScore,
    maximumScore: _maximumScore,
    startDate: _startDate,
    endDate: _endDate,
    sortOrder: _sortOrder,
  );

  List<ReportHistoryEntry> get _filtered =>
      filterReportHistory(_results, _query);

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _status = null;
      _minimumScore = null;
      _maximumScore = null;
      _startDate = null;
      _endDate = null;
    });
  }

  Future<void> _showFilters() async {
    final formKey = GlobalKey<FormState>();
    var minimumText = _minimumScore?.toString() ?? '';
    var maximumText = _maximumScore?.toString() ?? '';
    DateTimeRange? selectedRange = _startDate != null && _endDate != null
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C2E),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          String? validateNumber(String? value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty) return null;
            final number = double.tryParse(text);
            return number == null || !number.isFinite
                ? 'Enter a valid number'
                : null;
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Filter reports',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('historyMinimumScore'),
                              initialValue: minimumText,
                              onChanged: (value) => minimumText = value,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              validator: validateNumber,
                              decoration: const InputDecoration(
                                labelText: 'Minimum score',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              key: const Key('historyMaximumScore'),
                              initialValue: maximumText,
                              onChanged: (value) => maximumText = value,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                              validator: validateNumber,
                              decoration: const InputDecoration(
                                labelText: 'Maximum score',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        key: const Key('historyDateRange'),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100, 12, 31),
                            initialDateRange: selectedRange,
                          );
                          if (range != null) {
                            setSheetState(() => selectedRange = range);
                          }
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text(
                          selectedRange == null
                              ? 'Choose date range'
                              : '${_formatDay(selectedRange!.start)} – '
                                    '${_formatDay(selectedRange!.end)}',
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          if (!formKey.currentState!.validate()) return;
                          final minimum = _parseOptionalNumber(minimumText);
                          final maximum = _parseOptionalNumber(maximumText);
                          if (minimum != null &&
                              maximum != null &&
                              minimum > maximum) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Minimum score cannot exceed maximum score.',
                                ),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _minimumScore = minimum;
                            _maximumScore = maximum;
                            _startDate = selectedRange?.start;
                            _endDate = selectedRange?.end;
                          });
                          Navigator.pop(sheetContext);
                        },
                        child: const Text('Apply filters'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openVerification(SettingsSuggestionInput input) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioTestScreen(
          purpose: AudioAnalysisPurpose.settingsSuggestion,
          genre: input.genre,
          settingsSuggestion: input,
        ),
      ),
    );
  }

  void _openResult(Map<dynamic, dynamic> record) {
    final purpose = record['analysis_purpose'] == 'settings_suggestion'
        ? AudioAnalysisPurpose.settingsSuggestion
        : AudioAnalysisPurpose.qualityEvaluation;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => audioResultDestination(
          record: record,
          purpose: purpose,
          isGuest: UserSession.instance.isGuest,
          onVerify: _openVerification,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final query = _query;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: Text(
          widget.title,
          style: TextStyle(
            color: widget.accentColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (UserSession.instance.isGuest && _results.isNotEmpty)
              const _GuestMigrationPrompt(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                key: const Key('historySearchField'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search report names',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF1C1C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _StatusChip(
                    label: 'All',
                    selected: _status == null,
                    accentColor: widget.accentColor,
                    onSelected: () => setState(() => _status = null),
                  ),
                  for (final status in _standardStatuses)
                    _StatusChip(
                      label: status,
                      selected: _status == status,
                      accentColor: widget.accentColor,
                      onSelected: () => setState(() => _status = status),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      filtered.length == _results.length
                          ? '${_results.length} ${_reportWord(_results.length)}'
                          : '${filtered.length} of ${_results.length} reports',
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (query.hasFilters)
                    TextButton(
                      key: const Key('historyClearFilters'),
                      onPressed: _clearFilters,
                      child: const Text('Clear'),
                    ),
                  OutlinedButton.icon(
                    key: const Key('historyFiltersButton'),
                    onPressed: _showFilters,
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Filter'),
                  ),
                  PopupMenuButton<ReportHistorySort>(
                    key: const Key('historySort'),
                    tooltip: 'Sort reports',
                    initialValue: _sortOrder,
                    onSelected: (value) => setState(() => _sortOrder = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: ReportHistorySort.newest,
                        child: Text('Newest first'),
                      ),
                      PopupMenuItem(
                        value: ReportHistorySort.oldest,
                        child: Text('Oldest first'),
                      ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _sortOrder == ReportHistorySort.newest
                            ? Icons.south
                            : Icons.north,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_loadError != null && _results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      color: Color(0xFFFFB74D),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _loadError!,
                        style: const TextStyle(
                          color: Color(0xFFFFB74D),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            if (_results.whereType<Map>().length >= 2)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (!_selectingReports)
                      TextButton.icon(
                        key: const Key('compareReports'),
                        icon: const Icon(Icons.compare_arrows),
                        label: const Text('Select reports to compare'),
                        onPressed: () =>
                            setState(() => _selectingReports = true),
                      )
                    else ...[
                      Text(
                        '${_selectedReports.length} of 2 selected',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      FilledButton(
                        key: const Key('compareSelectedReports'),
                        onPressed: _selectedReports.length != 2
                            ? null
                            : () {
                                final entries = _selectedReports
                                    .map(
                                      (index) => ReportHistoryEntry.fromRaw(
                                        _results[index],
                                        sourceIndex: index,
                                      ),
                                    )
                                    .toList();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReportComparisonScreen(
                                      entries: entries,
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Compare'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _selectingReports = false;
                          _selectedReports.clear();
                        }),
                        child: const Text('Cancel selection'),
                      ),
                    ],
                  ],
                ),
              ),
            Expanded(child: _buildResults(filtered, query.hasFilters)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(List<ReportHistoryEntry> filtered, bool hasFilters) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: widget.accentColor),
      );
    }
    if (_loadError != null && _results.isEmpty) {
      return _LoadErrorView(onRetry: _load);
    }
    if (_results.isEmpty) {
      return UserSession.instance.isGuest
          ? const _GuestRecordsView()
          : const _EmptyRecordsView();
    }
    if (filtered.isEmpty && hasFilters) return const _NoFilterMatchesView();

    return RefreshIndicator(
      onRefresh: _load,
      color: widget.accentColor,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        itemCount: filtered.length,
        itemBuilder: (_, index) => _ReportCard(
          entry: filtered[index],
          selecting: _selectingReports,
          selected: _selectedReports.contains(filtered[index].sourceIndex),
          onTap: () {
            if (!_selectingReports) {
              _openResult(filtered[index].raw);
              return;
            }
            final sourceIndex = filtered[index].sourceIndex;
            if (!_selectedReports.contains(sourceIndex) &&
                _selectedReports.length == 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Deselect a report before choosing another.'),
                ),
              );
              return;
            }
            setState(() {
              if (_selectedReports.contains(sourceIndex)) {
                _selectedReports.remove(sourceIndex);
              } else {
                _selectedReports.add(sourceIndex);
              }
            });
          },
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.accentColor,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final Color accentColor;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        selectedColor: accentColor,
        backgroundColor: const Color(0xFF1C1C2E),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFFAAAAAA),
          fontSize: 12,
        ),
        side: BorderSide.none,
        showCheckmark: false,
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.entry,
    required this.onTap,
    this.selecting = false,
    this.selected = false,
  });

  final bool selecting;
  final bool selected;

  final ReportHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = entry.status;
    final color = switch (status) {
      'Acceptable' => const Color(0xFF4CAF50),
      'Needs Improvement' => const Color(0xFFFF9800),
      'Problematic' => const Color(0xFFF44336),
      _ => const Color(0xFFAAAAAA),
    };
    return Card(
      color: const Color(0xFF1C1C2E),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              if (selecting)
                Checkbox(
                  key: Key('selectReport${entry.sourceIndex}'),
                  value: selected,
                  onChanged: (_) => onTap(),
                  semanticLabel:
                      'Select ${entry.name ?? 'report'}, ${entry.createdAt?.toLocal() ?? 'date unavailable'}',
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name ?? 'Name unavailable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.createdAt == null
                          ? 'Date unavailable'
                          : _formatTimestamp(entry.createdAt!),
                      style: const TextStyle(
                        color: Color(0xFF777777),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    status ?? 'Status unavailable',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.score == null
                        ? 'Score unavailable'
                        : '${reportScoreLabel(entry.score)}/100',
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF555555),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, color: Color(0xFFFFB74D)),
          const SizedBox(height: 10),
          const Text(
            'Couldn’t load reports',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _NoFilterMatchesView extends StatelessWidget {
  const _NoFilterMatchesView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'No reports match your filters',
        style: TextStyle(color: Color(0xFF888888)),
      ),
    );
  }
}

class _EmptyRecordsView extends StatelessWidget {
  const _EmptyRecordsView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No reports yet', style: TextStyle(color: Color(0xFF888888))),
    );
  }
}

class _GuestRecordsView extends StatelessWidget {
  const _GuestRecordsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Color(0xFF4A90D9),
            ),
            const SizedBox(height: 20),
            const Text(
              'No guest reports yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Completed guest evaluations and visual reports stay on this device so you can reopen them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFAAAAAA), height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SignUpScreen()),
              ),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Create Account'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestMigrationPrompt extends StatelessWidget {
  const _GuestMigrationPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16253A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Guest reports stay on this device and remain separate after you sign in or create an account.',
              style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpScreen()),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

double? _parseOptionalNumber(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : double.parse(trimmed);
}

String _formatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  return '${_formatDay(local)} ${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String _formatDay(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _reportWord(int count) => count == 1 ? 'report' : 'reports';
