import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:karaok_app/core/network/api_exception.dart';
import 'package:karaok_app/core/security/auth_limits.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';

class SubmitGuard extends ChangeNotifier {
  SubmitGuard(this.action, {SecureTokenStore? store, DateTime Function()? now})
    : _store = store ?? SecureTokenStore.instance,
      _now = now ?? DateTime.now;

  final String action;
  final SecureTokenStore _store;
  final DateTime Function() _now;
  final _ticks = StreamController<Duration>.broadcast();
  Timer? _timer;
  Future<void>? _restoring;
  int _window = 0;
  int _lastAttempt = 0;
  int _hits = 0;
  int _strikes = 0;
  int _until = 0;
  bool _disposed = false;

  String get _key => 'karaok_submit_$action';
  int get _time => _now().millisecondsSinceEpoch;
  Duration get remaining =>
      Duration(milliseconds: (_until - _time).clamp(0, 86400000));
  bool get isLocked => remaining > Duration.zero;
  String label(String normal) =>
      isLocked ? 'Try again in ${countdownLabel(remaining)}' : normal;
  Stream<Duration> get ticks => _ticks.stream;

  Future<void> restore() => _restoring ??= _restore();

  Future<void> _restore() async {
    try {
      final saved = await _store.readAuthState(_key);
      if (saved == null) return;
      final state = jsonDecode(saved) as Map<String, dynamic>;
      _window = state['window'] as int;
      _lastAttempt = state['last'] as int;
      _hits = state['hits'] as int;
      _strikes = state['strikes'] as int;
      _until = state['until'] as int;
      _update();
    } catch (_) {
      // The server still enforces the limits if the local state is unavailable.
    }
  }

  Future<Duration?> recordAttempt() async {
    await restore();
    if (_disposed) return Duration.zero;
    if (isLocked) return remaining;
    final time = _time;
    if (time - _lastAttempt >= authStrikeReset.inMilliseconds) _strikes = 0;
    if (_until != 0 || time - _window >= authBurstWindow.inMilliseconds) {
      _until = 0;
      _window = time;
      _hits = 0;
    }
    _lastAttempt = time;
    _hits++;
    Duration? lock;
    if (_hits > authBurstLimit) {
      lock = _strikes++ == 0 ? authFirstLock : authRepeatLock;
      _until = time + lock.inMilliseconds;
    }
    _update();
    await _save();
    return lock;
  }

  Future<void> applyServerRetryAfter(int seconds) async {
    await restore();
    final time = _time;
    _until = time + Duration(seconds: seconds).inMilliseconds;
    _lastAttempt = time;
    if (_strikes == 0) _strikes = 1;
    _update();
    await _save();
  }

  Future<void> _save() async {
    try {
      await _store.writeAuthState(
        _key,
        jsonEncode({
          'window': _window,
          'last': _lastAttempt,
          'hits': _hits,
          'strikes': _strikes,
          'until': _until,
        }),
      );
    } catch (_) {
      // In-memory state still covers the current session.
    }
  }

  void _update() {
    if (_disposed) return;
    final time = remaining;
    _ticks.add(time);
    notifyListeners();
    if (time == Duration.zero) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _update());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_ticks.close());
    super.dispose();
  }
}

mixin GuardedSubmit<T extends StatefulWidget> on State<T> {
  Iterable<String> get submitActions;
  final _guards = <String, SubmitGuard>{};

  SubmitGuard guard(String action) => _guards[action]!;

  @override
  void initState() {
    super.initState();
    for (final action in submitActions) {
      final guard = _guards[action] = SubmitGuard(action);
      guard.addListener(_refreshGuard);
      unawaited(guard.restore());
    }
  }

  void _refreshGuard() {
    if (mounted) setState(() {});
  }

  Future<void> applyRetryAfter(String action, ApiException error) async {
    if (error.statusCode == 429) {
      await guard(action).applyServerRetryAfter(
        error.retryAfterSeconds ?? authDefaultRetrySeconds,
      );
    }
  }

  @override
  void dispose() {
    for (final guard in _guards.values) {
      guard.dispose();
    }
    super.dispose();
  }
}
