import 'dart:typed_data';

import 'package:karaok_app/core/network/api_service.dart';

export 'package:karaok_app/core/network/api_exception.dart';

/// Audio-assessment API surface, isolated from authentication and settings.
class AssessmentApi {
  AssessmentApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<List<dynamic>> getAudioTests() => _client.getAudioTests();

  Future<Map<String, dynamic>> getAudioTest(int testId) =>
      _client.getAudioTest(testId);

  Future<Uint8List> getAudioVisualization(int testId, String kind) =>
      _client.getAudioVisualization(testId, kind);

  Future<void> deleteAudioTest(int testId) => _client.deleteAudioTest(testId);

  Future<Map<String, dynamic>> submitAudio({
    required String filePath,
    required String fileName,
    Uint8List? fileBytes,
    required int durationSeconds,
    String? genre,
    String analysisPurpose = 'quality_evaluation',
    bool guest = false,
  }) => _client.submitAudio(
    filePath: filePath,
    fileName: fileName,
    fileBytes: fileBytes,
    durationSeconds: durationSeconds,
    genre: genre,
    analysisPurpose: analysisPurpose,
    guest: guest,
  );
}
