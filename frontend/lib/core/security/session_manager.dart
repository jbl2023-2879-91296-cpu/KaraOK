import 'dart:convert';
import 'dart:typed_data';

/// Singleton that holds the currently logged-in user for the app session.
/// Guest users have id == null and isGuest == true.
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  int? id;
  String? username;
  String? name;
  String? firstName;
  String? lastName;
  String? email;
  String? address;
  String? city;
  String? stateProvince;
  String? areaCode;
  String? country;
  String? countryCode;
  String? phoneNumber;
  String? birthday;
  Uint8List? profileImageBytes;
  String? profileImageMime;
  String? userType; // 'user' | 'admin'
  bool isGuest = false;
  bool requiresPasswordChange = false;

  bool get isLoggedIn => id != null || isGuest;

  void setUser({
    required int id,
    required String name,
    required String email,
    required String userType,
    String? username,
    String? firstName,
    String? lastName,
    String? address,
    String? city,
    String? stateProvince,
    String? areaCode,
    String? country,
    String? countryCode,
    String? phoneNumber,
    String? birthday,
    String? profileImageBase64,
    String? profileImageMime,
    bool requiresPasswordChange = false,
  }) {
    this.id = id;
    this.username = username;
    this.name = name;
    this.firstName = firstName;
    this.lastName = lastName;
    this.email = email;
    this.address = address;
    this.city = city;
    this.stateProvince = stateProvince;
    this.areaCode = areaCode;
    this.country = country;
    this.countryCode = countryCode;
    this.phoneNumber = phoneNumber;
    this.birthday = birthday;
    profileImageBytes = profileImageBase64 == null
        ? null
        : base64Decode(profileImageBase64);
    this.profileImageMime = profileImageMime;
    this.userType = userType;
    this.requiresPasswordChange = requiresPasswordChange;
    isGuest = false;
  }

  void setGuest(String userType) {
    id = null;
    username = null;
    name = 'Guest';
    firstName = null;
    lastName = null;
    email = null;
    address = null;
    city = null;
    stateProvince = null;
    areaCode = null;
    country = null;
    countryCode = null;
    phoneNumber = null;
    birthday = null;
    profileImageBytes = null;
    profileImageMime = null;
    this.userType = userType;
    isGuest = true;
    requiresPasswordChange = false;
  }

  void clear() {
    id = null;
    username = null;
    name = null;
    firstName = null;
    lastName = null;
    email = null;
    address = null;
    city = null;
    stateProvince = null;
    areaCode = null;
    country = null;
    countryCode = null;
    phoneNumber = null;
    birthday = null;
    profileImageBytes = null;
    profileImageMime = null;
    userType = null;
    isGuest = false;
    requiresPasswordChange = false;
  }
}
