import 'dart:typed_data';

import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/core/storage/analysis_cache.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

export 'package:karaok_app/core/network/api_exception.dart';

/// Audio-assessment API surface, isolated from authentication and settings.
class AssessmentApi {
  AssessmentApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<List<dynamic>?> getCachedAudioTests() =>
      AnalysisCache.instance.readHistory();

  Future<List<dynamic>> getAudioTests() async {
    final tests = await _client.getAudioTests();
    await AnalysisCache.instance.saveHistory(tests);
    return tests;
  }

  Future<Map<String, dynamic>> getAudioTest(int testId) =>
      _client.getAudioTest(testId);

  Future<Uint8List> getAudioVisualization(int testId, String kind) =>
      AnalysisCache.instance.visualization(
        assessmentId: testId,
        kind: kind,
        fetch: () => _client.getAudioVisualization(testId, kind),
      );

  Future<void> deleteAudioTest(int testId) async {
    await _client.deleteAudioTest(testId);
    await AnalysisCache.instance.removeAssessment(testId);
  }

  Future<Map<String, dynamic>> submitAudio({
    required String filePath,
    required String fileName,
    Uint8List? fileBytes,
    required int durationSeconds,
    String? genre,
    String analysisPurpose = 'quality_evaluation',
    bool guest = false,
    SettingsSuggestionInput? settingsSuggestion,
  }) {
    if (analysisPurpose == 'settings_suggestion') {
      if (settingsSuggestion == null) {
        throw ArgumentError(
          'settingsSuggestion is required for settings_suggestion.',
        );
      }
      if (guest && settingsSuggestion.amplifierScale == null) {
        throw ArgumentError(
          'Guest suggestions require a local amplifier scale.',
        );
      }
      if (!guest && settingsSuggestion.amplifierProfileId == null) {
        throw ArgumentError(
          'Authenticated suggestions require an amplifier profile.',
        );
      }
    }
    return _client.submitAudio(
      filePath: filePath,
      fileName: fileName,
      fileBytes: fileBytes,
      durationSeconds: durationSeconds,
      genre: genre,
      analysisPurpose: analysisPurpose,
      guest: guest,
      settingsSuggestionFields: analysisPurpose == 'settings_suggestion'
          ? settingsSuggestion!.toMultipartFields()
          : null,
    );
  }
}
