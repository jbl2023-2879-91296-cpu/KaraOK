import 'dart:convert';
import 'dart:typed_data';

import 'package:country_picker/country_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/features/account/data/account_api.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, this.forceChange = false});

  final bool forceChange;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const _maxProfileImageBytes = 2 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _profileFormKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _usernameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateProvinceController = TextEditingController();
  final _areaCodeController = TextEditingController();
  final _countryController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _editingProfile = false;
  bool _savingProfile = false;
  bool _profileImageChanged = false;
  String? _error;
  String? _profileError;
  String? _countryCode;
  Uint8List? _draftProfileImage;
  String? _draftProfileImageMime;

  @override
  void initState() {
    super.initState();
    _resetProfileDraft();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _birthdayController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateProvinceController.dispose();
    _areaCodeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  void _resetProfileDraft() {
    final session = UserSession.instance;
    _usernameController.text = session.username ?? '';
    _firstNameController.text = session.firstName ?? '';
    _lastNameController.text = session.lastName ?? '';
    _phoneController.text = session.phoneNumber ?? '';
    _birthdayController.text = session.birthday ?? '';
    _addressController.text = session.address ?? '';
    _cityController.text = session.city ?? '';
    _stateProvinceController.text = session.stateProvince ?? '';
    _areaCodeController.text = session.areaCode ?? '';
    _countryController.text = session.country ?? '';
    _countryCode = session.countryCode;
    _draftProfileImage = session.profileImageBytes == null
        ? null
        : Uint8List.fromList(session.profileImageBytes!);
    _draftProfileImageMime = session.profileImageMime;
    _profileImageChanged = false;
    _profileError = null;
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label.' : null;

  Future<void> _pickProfileImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Profile image',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxProfileImageBytes) {
      setState(() => _profileError = 'Profile image must not exceed 2 MB.');
      return;
    }
    final extension = file.name.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (mime == null) {
      setState(() => _profileError = 'Choose a JPEG, PNG, or WebP image.');
      return;
    }
    setState(() {
      _draftProfileImage = bytes;
      _draftProfileImageMime = mime;
      _profileImageChanged = true;
      _profileError = null;
    });
  }

  Future<void> _selectBirthday() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_birthdayController.text);
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)),
      initialDate: current ?? DateTime(now.year - 18, now.month, now.day),
    );
    if (selected == null) return;
    _birthdayController.text =
        '${selected.year.toString().padLeft(4, '0')}-'
        '${selected.month.toString().padLeft(2, '0')}-'
        '${selected.day.toString().padLeft(2, '0')}';
  }

  void _selectCountry() {
    showCountryPicker(
      context: context,
      showPhoneCode: false,
      onSelect: (country) {
        setState(() {
          _countryController.text = country.name;
          _countryCode = country.countryCode;
        });
      },
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    try {
      final user = await AccountApi().updateProfile(
        username: _usernameController.text.trim(),
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        address: _addressController.text.trim(),
        city: _cityController.text.trim(),
        stateProvince: _stateProvinceController.text.trim(),
        areaCode: _areaCodeController.text.trim(),
        country: _countryController.text.trim(),
        countryCode: _countryCode!,
        phoneNumber: _phoneController.text.trim(),
        birthday: _birthdayController.text,
        profileImageBase64: _profileImageChanged && _draftProfileImage != null
            ? base64Encode(_draftProfileImage!)
            : null,
        profileImageMime: _draftProfileImageMime,
        profileImageChanged: _profileImageChanged,
      );
      final session = UserSession.instance;
      session.setUserFromMap(user);
      if (!mounted) return;
      setState(() {
        _editingProfile = false;
        _savingProfile = false;
        _resetProfileDraft();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account details updated.')));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _profileError = error.message;
        _savingProfile = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileError = 'Could not update account details.';
        _savingProfile = false;
      });
    }
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    if (password.length < 12 ||
        !RegExp(r'[A-Z]').hasMatch(password) ||
        !RegExp(r'[a-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password) ||
        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      return 'Use 12+ characters with mixed case, a number, and a symbol.';
    }
    if (!widget.forceChange && password == _currentController.text) {
      return 'Choose a password different from the current password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthApi().changePassword(
        currentPassword: widget.forceChange ? null : _currentController.text,
        newPassword: _newController.text,
      );
      final email = UserSession.instance.email;
      await AuthApi().clearTokens();
      UserSession.instance.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed. Please log in again.')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => LoginScreen(initialIdentifier: email),
        ),
        (route) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.contains('incorrect')
            ? 'The current password is incorrect.'
            : error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to the server.';
        _loading = false;
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          onPressed: toggle,
          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
        ),
      ),
    );
  }

  Widget _accountDetails(UserSession session) {
    final shownImage = _editingProfile
        ? _draftProfileImage
        : session.profileImageBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFF1A1A2E),
                    backgroundImage: shownImage == null
                        ? null
                        : MemoryImage(shownImage),
                    child: shownImage == null
                        ? const Icon(
                            Icons.person_outline,
                            color: Color(0xFF4A90D9),
                            size: 46,
                          )
                        : null,
                  ),
                  if (_editingProfile)
                    Positioned(
                      right: -6,
                      bottom: -4,
                      child: IconButton.filled(
                        tooltip: 'Choose profile image',
                        onPressed: _savingProfile ? null : _pickProfileImage,
                        icon: const Icon(Icons.camera_alt_outlined, size: 20),
                      ),
                    ),
                ],
              ),
              if (_editingProfile && shownImage != null)
                TextButton(
                  onPressed: _savingProfile
                      ? null
                      : () => setState(() {
                          _draftProfileImage = null;
                          _draftProfileImageMime = null;
                          _profileImageChanged = true;
                        }),
                  child: const Text('Remove photo'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Account Details',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!_editingProfile)
              TextButton.icon(
                onPressed: () => setState(() {
                  _resetProfileDraft();
                  _editingProfile = true;
                }),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF14141F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3E)),
          ),
          child: _AccountDetailRow(
            icon: Icons.lock_outline,
            label: 'Email (cannot be changed)',
            value: session.email ?? 'Not available',
          ),
        ),
        const SizedBox(height: 12),
        if (_editingProfile)
          _editableAccountDetails()
        else
          _readOnlyAccountDetails(session),
      ],
    );
  }

  Widget _readOnlyAccountDetails(UserSession session) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3E)),
      ),
      child: Column(
        children: [
          _AccountDetailRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: session.name ?? 'Not available',
          ),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _AccountDetailRow(
            icon: Icons.alternate_email,
            label: 'Username',
            value: session.username ?? 'Not available',
          ),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _AccountDetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone number',
            value: session.phoneNumber ?? 'Not available',
          ),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _AccountDetailRow(
            icon: Icons.cake_outlined,
            label: 'Birthday',
            value: session.birthday ?? 'Not available',
          ),
          const Divider(height: 24, color: Color(0xFF2A2A3E)),
          _AccountDetailRow(
            icon: Icons.location_on_outlined,
            label: 'Address',
            value: [
              session.address,
              session.city,
              session.stateProvince,
              session.areaCode,
              session.country,
              session.countryCode,
            ].whereType<String>().where((value) => value.isNotEmpty).join(', '),
          ),
        ],
      ),
    );
  }

  Widget _editableAccountDetails() {
    return Form(
      key: _profileFormKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3E)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _profileField(
                    controller: _firstNameController,
                    label: 'First name',
                    validator: (value) => _required(value, 'your first name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _profileField(
                    controller: _lastNameController,
                    label: 'Last name',
                    validator: (value) => _required(value, 'your last name'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _profileField(
              controller: _usernameController,
              label: 'Username',
              validator: (value) {
                final username = value?.trim() ?? '';
                return RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(username)
                    ? null
                    : 'Use 3-50 letters, numbers, dots, dashes, or underscores.';
              },
            ),
            const SizedBox(height: 14),
            _profileField(
              controller: _phoneController,
              label: 'Phone number',
              keyboardType: TextInputType.phone,
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length >= 7 && digits.length <= 15
                    ? null
                    : 'Enter a valid phone number.';
              },
            ),
            const SizedBox(height: 14),
            _profileField(
              controller: _birthdayController,
              label: 'Birthday',
              readOnly: true,
              onTap: _selectBirthday,
              suffixIcon: const Icon(Icons.calendar_month_outlined),
              validator: (value) => _required(value, 'your birthday'),
            ),
            const SizedBox(height: 14),
            _profileField(
              controller: _addressController,
              label: 'Street address',
              validator: (value) => _required(value, 'your street address'),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _profileField(
                    controller: _cityController,
                    label: 'City / Municipality',
                    validator: (value) => _required(value, 'your city'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _profileField(
                    controller: _stateProvinceController,
                    label: 'Province / State',
                    validator: (value) =>
                        _required(value, 'your province or state'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _profileField(
                    controller: _countryController,
                    label: 'Country',
                    readOnly: true,
                    onTap: _selectCountry,
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_countryCode != null)
                          Text(
                            _countryCode!,
                            style: const TextStyle(
                              color: Color(0xFFAAAAAA),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                    validator: (_) =>
                        _countryCode == null ? 'Select your country.' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _profileField(
                    controller: _areaCodeController,
                    label: 'Postal code',
                    validator: (value) => _required(value, 'your postal code'),
                  ),
                ),
              ],
            ),
            if (_profileError != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _profileError!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _savingProfile
                        ? null
                        : () => setState(() {
                            _resetProfileDraft();
                            _editingProfile = false;
                          }),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _savingProfile ? null : _saveProfile,
                    child: _savingProfile
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(labelText: label, suffixIcon: suffixIcon),
    );
  }

  Future<void> _logOut() async {
    final lastIdentifier = UserSession.instance.email;
    if (lastIdentifier != null) {
      try {
        await SecureTokenStore.instance.saveLastIdentifier(lastIdentifier);
      } catch (_) {
        // Logging out must still complete if the convenience value cannot save.
      }
    }
    try {
      await AuthApi().logout();
    } catch (_) {
      // Local logout still completes when the server is unavailable.
    } finally {
      UserSession.instance.setGuest('user');
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AppShell()),
      (route) => false,
    );
  }

  Widget _guestSettings() {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 38,
                  backgroundColor: Color(0xFF1A1A2E),
                  child: Icon(
                    Icons.person_outline,
                    color: Color(0xFF4A90D9),
                    size: 38,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'You are using KaraOK as a guest',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Create an account to save records, keep your results, and continue evaluating audio after your guest attempts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFAAAAAA), height: 1.5),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SignUpScreen()),
                    ),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create Account'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    icon: const Icon(Icons.login),
                    label: const Text('Log In'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    if (session.isGuest && !widget.forceChange) return _guestSettings();

    return PopScope(
      canPop: !widget.forceChange,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0D0D),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: const Color(0xFF0D0D0D),
          title: Text(
            widget.forceChange ? 'Password Change Required' : 'Settings',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (!widget.forceChange) ...[
                  _accountDetails(session),
                  const SizedBox(height: 28),
                  const Text(
                    'Change Password',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  widget.forceChange
                      ? 'You signed in with a temporary password. Change it now before continuing.'
                      : 'Enter your current password, then choose a new secure password.',
                  style: const TextStyle(color: Color(0xFFAAAAAA), height: 1.4),
                ),
                const SizedBox(height: 24),
                if (!widget.forceChange) ...[
                  _passwordField(
                    controller: _currentController,
                    label: 'Current password',
                    obscure: _obscureCurrent,
                    toggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter your current password.'
                        : null,
                  ),
                  const SizedBox(height: 16),
                ],
                _passwordField(
                  controller: _newController,
                  label: 'New password',
                  obscure: _obscureNew,
                  toggle: () => setState(() => _obscureNew = !_obscureNew),
                  validator: _validateNewPassword,
                ),
                const SizedBox(height: 16),
                _passwordField(
                  controller: _confirmController,
                  label: 'Retype new password',
                  obscure: _obscureConfirm,
                  toggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (value) => value != _newController.text
                      ? 'The new passwords do not match.'
                      : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  key: const ValueKey('change-password-submit'),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Confirm password change'),
                ),
                if (!widget.forceChange) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _logOut,
                    icon: const Icon(Icons.logout, color: Colors.redAccent),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF4A90D9), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF888888), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
