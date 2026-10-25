import 'package:karaok_app/features/reports/presentation/pages/glossary_screen.dart';
import 'package:karaok_app/shared/widgets/app_widgets.dart';
import 'package:karaok_app/features/assessments/data/audio_staging_service.dart';
import 'package:karaok_app/app/app_theme.dart';
import 'package:karaok_app/shared/widgets/form_feedback.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import 'package:karaok_app/app/app_shell.dart';
import 'package:karaok_app/core/media/profile_image_picker.dart';
import 'package:karaok_app/core/security/password_policy.dart';
import 'package:karaok_app/core/security/secure_token_store.dart';
import 'package:karaok_app/core/security/session_manager.dart';
import 'package:karaok_app/core/storage/analysis_cache.dart';
import 'package:karaok_app/features/account/data/account_api.dart';
import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/signup_screen.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({
    super.key,
    this.forceChange = false,
    this.editProfile = false,
    this.authApi,
    this.accountApi,
    this.audioStagingService,
    this.analysisCache,
  });

  final bool forceChange;
  final bool editProfile;
  final AuthApi? authApi;
  final AccountApi? accountApi;
  final AudioStagingService? audioStagingService;
  final AnalysisCache? analysisCache;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _passwordFeedback = FormFeedback();
  final _profileFeedback = FormFeedback();
  final _pageTop = GlobalKey();
  bool _loggingOut = false;
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
  int _sessionRevision = 0;
  late (int?, String?, String?, bool) _sessionIdentity;

  (int?, String?, String?, bool) get _currentSessionIdentity {
    final session = UserSession.instance;
    return (session.id, session.email, session.userType, session.isGuest);
  }

  void _sessionChanged() {
    final identity = _currentSessionIdentity;
    if (identity != _sessionIdentity) {
      _sessionIdentity = identity;
      _sessionRevision++;
    }
  }

  bool _isCurrentSession(int revision) =>
      mounted &&
      _sessionRevision == revision &&
      UserSession.instance.id != null &&
      !UserSession.instance.isGuest;

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
    _sessionIdentity = _currentSessionIdentity;
    UserSession.instance.addListener(_sessionChanged);
    _resetProfileDraft();
    _editingProfile = widget.editProfile && !widget.forceChange;
  }

  @override
  void dispose() {
    UserSession.instance.removeListener(_sessionChanged);
    _passwordFeedback.dispose();
    _profileFeedback.dispose();
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
    _profileFeedback.clear();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label.' : null;

  Future<void> _pickProfileImage() async {
    final result = await ProfileImagePicker.pick(context);
    if (!mounted) return;
    if (result == null) return;
    if (!result.isSuccess) {
      setState(() => _profileError = result.error);
      return;
    }
    setState(() {
      _draftProfileImage = result.bytes;
      _draftProfileImageMime = result.mimeType;
      _profileImageChanged = true;
      _profileFeedback.errors.remove('profile_image');
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
    if (selected == null || !mounted) return;
    setState(() => _profileFeedback.errors.remove('birthday'));
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
          _profileFeedback.errors.remove('country');
        });
      },
    );
  }

  Future<void> _saveProfile() async {
    if (_savingProfile) return;
    setState(_profileFeedback.clear);
    if (!_profileFormKey.currentState!.validate()) {
      _profileFeedback.reveal();
      return;
    }
    setState(() {
      _savingProfile = true;
      _profileError = null;
    });
    final revision = _sessionRevision;
    try {
      final user = await (widget.accountApi ?? AccountApi()).updateProfile(
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
      if (!mounted || !_isCurrentSession(revision)) return;
      UserSession.instance.setUserFromMap(user);
      setState(() {
        _editingProfile = false;
        _savingProfile = false;
        _resetProfileDraft();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account details updated.')));
    } on ApiException catch (error) {
      if (!mounted || !_isCurrentSession(revision)) return;
      setState(() {
        _profileFeedback.receive(
          error,
          aliases: {
            'country_code': 'country',
            'profile_image_base64': 'profile_image',
            'profile_image_mime': 'profile_image',
          },
        );
        _profileError = _profileFeedback.banner;
        _savingProfile = false;
      });
      _profileFeedback.reveal();
      if (_profileError != null) _revealBanner();
    } catch (_) {
      if (!mounted || !_isCurrentSession(revision)) return;
      setState(() {
        _profileError = 'Could not update account details.';
        _savingProfile = false;
      });
      _revealBanner();
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  String? _validateNewPassword(String? value) {
    final password = value ?? '';
    final policyError = PasswordPolicy.validate(password);
    if (policyError != null) return policyError;
    if (!widget.forceChange && password == _currentController.text) {
      return 'Choose a password different from the current password.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_loading) return;
    setState(_passwordFeedback.clear);
    if (!_formKey.currentState!.validate()) {
      _passwordFeedback.reveal();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final revision = _sessionRevision;
    try {
      await (widget.authApi ?? AuthApi()).changePassword(
        currentPassword: widget.forceChange ? null : _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted || !_isCurrentSession(revision)) return;
      final email = UserSession.instance.email;
      try {
        await (widget.analysisCache ?? AnalysisCache.instance)
            .clearCurrentUser();
      } catch (_) {
        // A successful password change must still invalidate local credentials.
      }
      if (!mounted || !_isCurrentSession(revision)) return;
      await (widget.authApi ?? AuthApi()).clearTokens();
      if (!mounted || !_isCurrentSession(revision)) return;
      UserSession.instance.clear();
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
      if (!mounted || !_isCurrentSession(revision)) return;
      setState(() {
        _passwordFeedback.receive(error, aliases: {'password': 'new_password'});
        _error = _passwordFeedback.banner;
        _loading = false;
      });
      _passwordFeedback.reveal();
      if (_error != null) _revealBanner();
    } catch (_) {
      if (!mounted || !_isCurrentSession(revision)) return;
      setState(() {
        _error = 'Could not connect to the server.';
        _loading = false;
      });
      _revealBanner();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _revealBanner() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final anchor = _pageTop.currentContext;
      if (mounted && anchor != null) {
        Scrollable.ensureVisible(
          anchor,
          alignment: 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _fieldName(TextEditingController controller) {
    final fields = <TextEditingController, String>{
      _currentController: 'current_password',
      _newController: 'new_password',
      _confirmController: 'confirm_password',
      _usernameController: 'username',
      _firstNameController: 'first_name',
      _lastNameController: 'last_name',
      _phoneController: 'phone_number',
      _birthdayController: 'birthday',
      _addressController: 'address',
      _cityController: 'city',
      _stateProvinceController: 'state_province',
      _areaCodeController: 'area_code',
      _countryController: 'country',
    };
    return fields[controller]!;
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggle,
    String? Function(String?)? validator,
    int? maxLength,
  }) {
    final field = _fieldName(controller);
    return TextFormField(
      key: _passwordFeedback.key(field),
      focusNode: _passwordFeedback.focus(field),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) => setState(() => _passwordFeedback.errors.remove(field)),
      controller: controller,
      obscureText: obscure,
      validator: (value) =>
          _passwordFeedback.errors[field] ?? validator?.call(value),
      maxLength: maxLength,
      decoration: InputDecoration(
        errorText: _passwordFeedback.errors[field],
        labelText: label,
        counterText: maxLength == null ? null : '',
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
                    backgroundColor: AppColors.surface,
                    backgroundImage: shownImage == null
                        ? null
                        : MemoryImage(shownImage),
                    child: shownImage == null
                        ? const Icon(
                            Icons.person_outline,
                            color: AppColors.primary,
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
                          _profileFeedback.errors.remove('profile_image');
                        }),
                  child: const Text('Remove photo'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        AppSectionHeader(
          title: 'Account Details',
          action: !_editingProfile
              ? AppSecondaryButton(
                  label: 'Edit',
                  icon: Icons.edit_outlined,
                  onPressed: () => setState(() {
                    _resetProfileDraft();
                    _editingProfile = true;
                  }),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          _AccountDetailRow(
            icon: Icons.person_outline,
            label: 'Name',
            value: session.name ?? 'Not available',
          ),
          const Divider(height: 24, color: AppColors.outline),
          _AccountDetailRow(
            icon: Icons.alternate_email,
            label: 'Username',
            value: session.username ?? 'Not available',
          ),
          const Divider(height: 24, color: AppColors.outline),
          _AccountDetailRow(
            icon: Icons.phone_outlined,
            label: 'Phone number',
            value: session.phoneNumber ?? 'Not available',
          ),
          const Divider(height: 24, color: AppColors.outline),
          _AccountDetailRow(
            icon: Icons.cake_outlined,
            label: 'Birthday',
            value: session.birthday ?? 'Not available',
          ),
          const Divider(height: 24, color: AppColors.outline),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          children: [
            FormField<String>(
              key: _profileFeedback.key('profile_image'),
              forceErrorText: _profileFeedback.errors['profile_image'],
              builder: (field) => Focus(
                focusNode: _profileFeedback.focus('profile_image'),
                child: field.hasError
                    ? Text(
                        field.errorText!,
                        style: const TextStyle(color: AppColors.error),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

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
                              color: AppColors.muted,
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    label: 'Cancel',
                    onPressed: _savingProfile
                        ? null
                        : () => setState(() {
                            _resetProfileDraft();
                            _editingProfile = false;
                          }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppPrimaryButton(
                    label: 'Save Changes',
                    isLoading: _savingProfile,
                    onPressed: _saveProfile,
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
    final field = _fieldName(controller);
    return TextFormField(
      key: _profileFeedback.key(field),
      focusNode: _profileFeedback.focus(field),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      onChanged: (_) => setState(() => _profileFeedback.errors.remove(field)),
      controller: controller,
      validator: (value) =>
          _profileFeedback.errors[field] ?? validator?.call(value),
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        errorText: _profileFeedback.errors[field],
        labelText: label,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Future<void> _logOut() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    // Discard pending account responses as soon as logout begins.
    _sessionRevision++;
    final lastIdentifier = UserSession.instance.email;
    if (lastIdentifier != null) {
      try {
        await SecureTokenStore.instance.saveLastIdentifier(lastIdentifier);
      } catch (_) {
        // Logging out must still complete if the convenience value cannot save.
      }
    }
    try {
      await (widget.audioStagingService ?? AudioStagingService())
          .cleanupStaleRecordings()
          .timeout(AudioStagingService.operationTimeout);
    } catch (_) {
      // Recording cleanup must never prevent token clearing and logout.
    }
    try {
      await (widget.analysisCache ?? AnalysisCache.instance).clearCurrentUser();
    } catch (_) {
      // Cache cleanup is best effort; authentication still needs to end.
    }
    try {
      await (widget.authApi ?? AuthApi()).logout();
    } catch (_) {
      // Keep local credentials cleared even if an injected/server logout fails.
      try {
        await (widget.authApi ?? AuthApi()).clearTokens();
      } catch (_) {}
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

  Widget _glossaryLink() => ListTile(
    leading: const Icon(Icons.menu_book_outlined),
    title: const Text('Glossary of terms'),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => GlossaryScreen.open(context),
  );

  Widget _guestSettings() => AppPageScaffold(
    title: 'Settings',
    automaticallyImplyLeading: false,
    child: AppEmptyState(
      title: 'You are using KaraOK as a guest',
      message:
          'Create an account to save future records and continue evaluating audio after your guest attempts. Existing guest-only reports stay on this device and remain separate from your account history.',
      icon: Icons.person_outline,
      action: Column(
        children: [
          _glossaryLink(),
          AppPrimaryButton(
            label: 'Create Account',
            icon: Icons.person_add_alt_1,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignUpScreen()),
            ),
          ),
          const SizedBox(height: 12),
          AppSecondaryButton(
            label: 'Log In',
            icon: Icons.login,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final session = UserSession.instance;
    if (session.isGuest && !widget.forceChange) return _guestSettings();

    return PopScope(
      canPop: !widget.forceChange,
      child: AppPageScaffold(
        title: widget.forceChange ? 'Password Change Required' : 'Settings',
        automaticallyImplyLeading: false,
        child: Form(
          key: _formKey,
          child: Column(
            key: _pageTop,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_profileError != null)
                AppErrorState(
                  title: 'Could not save account details',
                  message: _profileError!,
                  onRetry: _savingProfile ? null : _saveProfile,
                ),
              if (_error != null)
                AppErrorState(
                  title: 'Could not change password',
                  message: _error!,
                  onRetry: _loading ? null : _submit,
                ),
              if (!widget.forceChange && session.needsProfileCompletion)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finish your profile',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Text(
                          'Add your details when you are ready. You can keep using KaraOK.',
                        ),
                        TextButton(
                          onPressed: _editingProfile
                              ? null
                              : () => setState(() {
                                  _resetProfileDraft();
                                  _editingProfile = true;
                                }),
                          child: const Text('Complete profile'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!widget.forceChange) ...[
                _glossaryLink(),
                _accountDetails(session),
                const SizedBox(height: 28),
                const AppSectionHeader(title: 'Change Password'),
                const SizedBox(height: 8),
              ],
              Text(
                widget.forceChange
                    ? 'You signed in with a temporary password. Change it now before continuing.'
                    : 'Enter your current password, then choose a new secure password.',
                style: const TextStyle(color: AppColors.muted, height: 1.4),
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
                maxLength: PasswordPolicy.maximumLength,
                toggle: () => setState(() => _obscureNew = !_obscureNew),
                validator: _validateNewPassword,
              ),
              const SizedBox(height: 16),
              PasswordChecklist(controller: _newController),
              _passwordField(
                controller: _confirmController,
                label: 'Retype new password',
                obscure: _obscureConfirm,
                maxLength: PasswordPolicy.maximumLength,
                toggle: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (value) => value != _newController.text
                    ? 'The new passwords do not match.'
                    : null,
              ),
              const SizedBox(height: 24),
              AppPrimaryButton(
                key: const ValueKey('change-password-submit'),
                label: 'Confirm password change',
                isLoading: _loading,
                onPressed: _loggingOut ? null : _submit,
              ),
              if (!widget.forceChange) ...[
                const SizedBox(height: 16),
                AppSecondaryButton(
                  label: 'Log Out',
                  icon: Icons.logout,
                  isLoading: _loggingOut,
                  onPressed: _loading ? null : _logOut,
                ),
              ],
            ],
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
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.ink,
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
