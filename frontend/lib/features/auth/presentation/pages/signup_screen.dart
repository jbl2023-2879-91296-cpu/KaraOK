import 'dart:convert';

import 'package:country_picker/country_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:karaok_app/features/auth/data/auth_api.dart';
import 'package:karaok_app/features/auth/presentation/pages/login_screen.dart';
import 'package:karaok_app/features/auth/presentation/pages/otp_verification_screen.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  static const _accentColor = Color(0xFF4A90D9);
  static const _maxProfileImageBytes = 2 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateProvinceCtrl = TextEditingController();
  final _areaCodeCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscurePass = true;
  bool _obscureConf = true;
  bool _loading = false;
  String? _error;
  String? _countryCode;
  Uint8List? _profileImage;
  String? _profileImageMime;

  @override
  void dispose() {
    for (final controller in [
      _usernameCtrl,
      _firstNameCtrl,
      _lastNameCtrl,
      _emailCtrl,
      _addressCtrl,
      _cityCtrl,
      _stateProvinceCtrl,
      _areaCodeCtrl,
      _countryCtrl,
      _phoneCtrl,
      _birthdayCtrl,
      _passCtrl,
      _confirmCtrl,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile image must not exceed 2 MB.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a JPEG, PNG, or WebP image.')),
      );
      return;
    }
    setState(() {
      _profileImage = bytes;
      _profileImageMime = mime;
    });
  }

  Future<void> _selectBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)),
      initialDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (selected == null) return;
    _birthdayCtrl.text =
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
          _countryCtrl.text = country.name;
          _countryCode = country.countryCode;
        });
      },
    );
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AuthApi().startRegistration(
        username: _usernameCtrl.text.trim(),
        firstName: _firstNameCtrl.text.trim(),
        lastName: _lastNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        address: _addressCtrl.text.trim(),
        city: _cityCtrl.text.trim(),
        stateProvince: _stateProvinceCtrl.text.trim(),
        areaCode: _areaCodeCtrl.text.trim(),
        country: _countryCtrl.text.trim(),
        countryCode: _countryCode!,
        phoneNumber: _phoneCtrl.text.trim(),
        birthday: _birthdayCtrl.text,
        profileImageBase64: _profileImage == null
            ? null
            : base64Encode(_profileImage!),
        profileImageMime: _profileImageMime,
      );
      if (!mounted) return;
      final serverEmail = response['email'];
      final verificationEmail = serverEmail is String && serverEmail.isNotEmpty
          ? serverEmail
          : _emailCtrl.text.trim().toLowerCase();
      setState(() => _loading = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            email: verificationEmail,
            developmentCode: response['development_code'] as String?,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message.contains('already')
            ? 'An account with this email or phone number already exists.'
            : error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not connect to server.';
        _loading = false;
      });
    }
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? 'Enter $label' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Account',
                  style: const TextStyle(
                    color: _accentColor,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Text(
                  'Create your user profile and save future results',
                  style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _loading ? null : _pickProfileImage,
                        customBorder: const CircleBorder(),
                        child: CircleAvatar(
                          radius: 46,
                          backgroundColor: const Color(0xFF1A1A2E),
                          backgroundImage: _profileImage == null
                              ? null
                              : MemoryImage(_profileImage!),
                          child: _profileImage == null
                              ? const Icon(
                                  Icons.add_a_photo_outlined,
                                  color: _accentColor,
                                  size: 34,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Profile image (optional, max 2 MB)',
                        style: TextStyle(
                          color: Color(0xFF888888),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'First name',
                        controller: _firstNameCtrl,
                        hint: 'e.g. Mary Jane',
                        validator: (value) => _required(value, 'first name'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: 'Last name',
                        controller: _lastNameCtrl,
                        hint: 'Last name',
                        validator: (value) => _required(value, 'last name'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Username',
                  controller: _usernameCtrl,
                  hint: 'Choose a username',
                  validator: (value) {
                    final username = value?.trim() ?? '';
                    return RegExp(r'^[A-Za-z0-9_.-]{3,50}$').hasMatch(username)
                        ? null
                        : 'Use 3-50 letters, numbers, dots, dashes, or underscores';
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Email',
                  controller: _emailCtrl,
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final required = _required(value, 'your email');
                    if (required != null) return required;
                    return value!.contains('@') ? null : 'Enter a valid email';
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Street address',
                  controller: _addressCtrl,
                  hint: 'House/building number and street',
                  suffixIcon: const Icon(Icons.location_on_outlined),
                  validator: (value) => _required(value, 'your street address'),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'City / Municipality',
                        controller: _cityCtrl,
                        hint: 'City',
                        validator: (value) => _required(value, 'your city'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _LabeledField(
                        label: 'Province / State',
                        controller: _stateProvinceCtrl,
                        hint: 'Province or state',
                        validator: (value) =>
                            _required(value, 'your province or state'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _LabeledField(
                        label: 'Country',
                        controller: _countryCtrl,
                        hint: 'Select your country',
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
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_drop_down),
                            const SizedBox(width: 8),
                          ],
                        ),
                        validator: (value) =>
                            _countryCode == null ? 'Select your country' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: _LabeledField(
                        label: 'Postal code',
                        controller: _areaCodeCtrl,
                        hint: 'e.g. 1000',
                        maxLength: 12,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9 -]'),
                          ),
                        ],
                        validator: (value) =>
                            _required(value, 'your postal code'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Phone number',
                  controller: _phoneCtrl,
                  hint: '+63 912 345 6789',
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length >= 7 && digits.length <= 15
                        ? null
                        : 'Enter a valid phone number';
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Birthday',
                  controller: _birthdayCtrl,
                  hint: 'YYYY-MM-DD',
                  readOnly: true,
                  onTap: _selectBirthday,
                  suffixIcon: const Icon(Icons.calendar_month_outlined),
                  validator: (value) => _required(value, 'your birthday'),
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Password',
                  controller: _passCtrl,
                  hint: '12+ characters, mixed case, number and symbol',
                  obscure: _obscurePass,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.length < 12) {
                      return 'Password must be at least 12 characters';
                    }
                    if (!RegExp(r'[A-Z]').hasMatch(password) ||
                        !RegExp(r'[a-z]').hasMatch(password) ||
                        !RegExp(r'\d').hasMatch(password) ||
                        !RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
                      return 'Use upper/lowercase, a number, and a symbol';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _LabeledField(
                  label: 'Confirm password',
                  controller: _confirmCtrl,
                  hint: 'Retype your password',
                  obscure: _obscureConf,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConf ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConf = !_obscureConf),
                  ),
                  validator: (value) =>
                      value == _passCtrl.text ? null : 'Passwords do not match',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text(
                            'Send Verification Code',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(color: Color(0xFF888888)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                      child: const Text('Log In'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
    this.onTap,
    this.readOnly = false,
    this.maxLength,
    this.inputFormatters,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final bool readOnly;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFCCCCCC),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          validator: validator,
          onTap: onTap,
          readOnly: readOnly,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0x52FFFFFF), fontSize: 15),
            suffixIcon: suffixIcon,
            counterText: '',
            filled: true,
            fillColor: const Color(0xFF1C1C2E),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
