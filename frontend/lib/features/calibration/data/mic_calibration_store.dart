import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MicCalibration {
  const MicCalibration({
    required this.measurementId,
    required this.noiseFloorDbfs,
    required this.calibratedAt,
    this.correction,
  });

  factory MicCalibration.fromJson(Map<String, dynamic> json, DateTime at) =>
      MicCalibration(
        measurementId: json['measurement_id'] as String,
        noiseFloorDbfs: (json['noise_floor_dbfs'] as num).toDouble(),
        calibratedAt: at,
        correction: (json['correction'] as Map?)?.cast<String, dynamic>(),
      );

  final String measurementId;
  final double noiseFloorDbfs;
  final DateTime calibratedAt;
  final Map<String, dynamic>? correction;

  Map<String, dynamic> toJson() => {
    'measurement_id': measurementId,
    'noise_floor_dbfs': noiseFloorDbfs,
    'calibrated_at': correction == null
        ? null
        : calibratedAt.toUtc().toIso8601String(),
    'correction': correction,
  };
}

class MicCalibrationStore {
  const MicCalibrationStore();

  static const instance = MicCalibrationStore();
  static const _recordKey = 'karaok_mic_calibration_v1';
  static const _skipKey = 'karaok_mic_calibration_skip_v1';
  static const _storage = FlutterSecureStorage();

  Future<MicCalibration?> load() async {
    try {
      if (!await _hasInstall()) return null;
      final raw = await _storage.read(key: _recordKey);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return MicCalibration.fromJson(
        data,
        DateTime.tryParse(data['calibrated_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> save(MicCalibration value) async {
    await _rememberInstall();
    await _storage.write(key: _recordKey, value: jsonEncode(value.toJson()));
    await _storage.delete(key: _skipKey);
  }

  Future<void> clear() async {
    await _storage.delete(key: _recordKey);
    await _storage.delete(key: _skipKey);
  }

  Future<void> skip({DateTime? now}) async {
    await _rememberInstall();
    await _storage.write(
      key: _skipKey,
      value: (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
  }

  Future<bool> shouldPrompt({DateTime? now}) async {
    if (!await _hasInstall()) return true;
    if ((await load())?.correction != null) return false;
    final since = DateTime.tryParse(await _storage.read(key: _skipKey) ?? '');
    return since == null ||
        (now ?? DateTime.now()).difference(since) >= const Duration(days: 7);
  }

  // Keychain items may survive app removal on iOS. The sandbox marker cannot.
  bool get _needsInstallMarker => !kIsWeb && Platform.isIOS;

  Future<File> _installMarker() async => File(
    path.join(
      (await getApplicationSupportDirectory()).path,
      'karaok_mic_calibration_install_v1',
    ),
  );

  Future<bool> _hasInstall() async =>
      !_needsInstallMarker || await (await _installMarker()).exists();

  Future<void> _rememberInstall() async {
    if (!_needsInstallMarker) return;
    final marker = await _installMarker();
    if (await marker.exists()) return;
    await clear();
    await marker.parent.create(recursive: true);
    await marker.writeAsString('1');
  }
}
