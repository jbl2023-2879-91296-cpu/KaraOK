import 'package:karaok_app/core/network/api_service.dart';
import 'package:karaok_app/features/sound_settings/domain/amplifier_profile.dart';
import 'package:karaok_app/features/sound_settings/domain/settings_recommendation.dart';

/// Typed client for amplifier profiles and generated settings.
class SettingsApi {
  SettingsApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> getProfileMetadata() =>
      _client.getSettingsProfileMetadata();

  Future<List<AmplifierProfile>> listProfiles() async {
    final profiles = await _client.listAmplifierProfiles();
    return profiles
        .map((profile) {
          if (profile is! Map) {
            throw const FormatException('Invalid amplifier profile response.');
          }
          return AmplifierProfile.fromJson(Map<String, dynamic>.from(profile));
        })
        .toList(growable: false);
  }

  Future<AmplifierProfile> createProfile(AmplifierProfile profile) async {
    final payload = profile.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    return AmplifierProfile.fromJson(
      await _client.createAmplifierProfile(payload),
    );
  }

  Future<AmplifierProfile> updateProfile(
    int profileId,
    AmplifierProfile profile,
  ) async {
    if (profileId < 1) {
      throw ArgumentError.value(profileId, 'profileId', 'Must be positive.');
    }
    final payload = profile.toJson()
      ..remove('id')
      ..remove('created_at')
      ..remove('updated_at');
    return AmplifierProfile.fromJson(
      await _client.updateAmplifierProfile(profileId, payload),
    );
  }

  Future<void> deleteProfile(int profileId) {
    if (profileId < 1) {
      throw ArgumentError.value(profileId, 'profileId', 'Must be positive.');
    }
    return _client.deleteAmplifierProfile(profileId);
  }

  Future<SettingsRecommendation> getRecommendation(int recommendationId) async {
    if (recommendationId < 1) {
      throw ArgumentError.value(
        recommendationId,
        'recommendationId',
        'Must be positive.',
      );
    }
    return SettingsRecommendation.fromJson(
      await _client.getSettingsRecommendation(recommendationId),
    );
  }

  Future<SettingsRecommendation> applyRecommendation(
    int recommendationId,
  ) async {
    if (recommendationId < 1) {
      throw ArgumentError.value(
        recommendationId,
        'recommendationId',
        'Must be positive.',
      );
    }
    return SettingsRecommendation.fromJson(
      await _client.applySettingsRecommendation(recommendationId),
    );
  }
}
