/// Singleton that holds the currently logged-in user for the app session.
/// Guest users have id == null and isGuest == true.
class UserSession {
  UserSession._();
  static final UserSession instance = UserSession._();

  int?   id;
  String? name;
  String? email;
  String? userType; // 'technician' | 'owner'
  bool   isGuest = false;

  bool get isLoggedIn => id != null || isGuest;

  void setUser({
    required int id,
    required String name,
    required String email,
    required String userType,
  }) {
    this.id       = id;
    this.name     = name;
    this.email    = email;
    this.userType = userType;
    isGuest       = false;
  }

  void setGuest(String userType) {
    id            = null;
    name          = 'Guest';
    email         = null;
    this.userType = userType;
    isGuest       = true;
  }

  void clear() {
    id       = null;
    name     = null;
    email    = null;
    userType = null;
    isGuest  = false;
  }
}
