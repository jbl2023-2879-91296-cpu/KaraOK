import 'package:karaok_app/core/network/api_service.dart';

/// Recommended sound-settings API surface.
class SettingsApi {
  SettingsApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> getGenreSettings(String genre) =>
      _client.getGenreSettings(genre);

  Future<List<dynamic>> getAllGenreSettings() => _client.getAllGenreSettings();

  Future<Map<String, dynamic>> saveGenreSettings({
    required String genre,
    required int volume,
    required int bass,
    required int treble,
    required int flatness,
    required int sharpness,
  }) => _client.saveGenreSettings(
    genre: genre,
    volume: volume,
    bass: bass,
    treble: treble,
    flatness: flatness,
    sharpness: sharpness,
  );
}
