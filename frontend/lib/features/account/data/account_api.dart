import 'package:karaok_app/core/network/api_service.dart';

class AccountApi {
  AccountApi({ApiService? client}) : _client = client ?? ApiService();

  final ApiService _client;

  Future<Map<String, dynamic>> updateProfile({
    required String username,
    required String firstName,
    required String lastName,
    required String address,
    required String city,
    required String stateProvince,
    required String areaCode,
    required String country,
    required String countryCode,
    required String phoneNumber,
    required String birthday,
    String? profileImageBase64,
    String? profileImageMime,
    bool profileImageChanged = false,
  }) => _client.updateProfile(
    username: username,
    firstName: firstName,
    lastName: lastName,
    address: address,
    city: city,
    stateProvince: stateProvince,
    areaCode: areaCode,
    country: country,
    countryCode: countryCode,
    phoneNumber: phoneNumber,
    birthday: birthday,
    profileImageBase64: profileImageBase64,
    profileImageMime: profileImageMime,
    profileImageChanged: profileImageChanged,
  );
}
