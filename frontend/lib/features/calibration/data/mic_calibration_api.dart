import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:karaok_app/core/network/api_service.dart';

class MicCalibrationApi {
  MicCalibrationApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> measure(
    String filePath, {
    Uint8List? bytes,
    required bool guest,
  }) => _client.uploadMicCalibration(
    filePath: filePath,
    fileBytes: bytes,
    guest: guest,
    deviceLabel: kIsWeb
        ? 'Web (${defaultTargetPlatform.name})'
        : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
  );
}
