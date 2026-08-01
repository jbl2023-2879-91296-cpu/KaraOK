import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ProfileImagePickResult {
  const ProfileImagePickResult.success(this.bytes, this.mimeType)
    : error = null;

  const ProfileImagePickResult.failure(this.error)
    : bytes = null,
      mimeType = null;

  final Uint8List? bytes;
  final String? mimeType;
  final String? error;

  bool get isSuccess => bytes != null && mimeType != null;
}

/// Camera/gallery picker and content-based validation for profile images.
abstract final class ProfileImagePicker {
  static const maxBytes = 5 * 1024 * 1024;

  static Future<ProfileImagePickResult?> pick(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1C2E),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return null;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length > maxBytes) {
        return const ProfileImagePickResult.failure(
          'Profile image must not exceed 5 MB.',
        );
      }
      final mimeType = _detectMimeType(bytes);
      if (mimeType == null) {
        return const ProfileImagePickResult.failure(
          'Choose a common phone image: JPEG, PNG, WebP, GIF, HEIC/HEIF, AVIF, or BMP.',
        );
      }
      return ProfileImagePickResult.success(bytes, mimeType);
    } on PlatformException catch (error) {
      return ProfileImagePickResult.failure(
        error.code == 'camera_access_denied'
            ? 'Camera access was denied.'
            : 'Could not open that image.',
      );
    } catch (_) {
      return const ProfileImagePickResult.failure('Could not open that image.');
    }
  }

  static String? _detectMimeType(Uint8List bytes) {
    bool startsWith(List<int> signature) {
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }

    if (startsWith([0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (startsWith([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (startsWith([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        startsWith([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
      return 'image/gif';
    }
    if (startsWith([0x42, 0x4D])) return 'image/bmp';
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if ({'avif', 'avis'}.contains(brand)) return 'image/avif';
      if ({
        'heic',
        'heix',
        'hevc',
        'hevx',
        'heim',
        'heis',
        'mif1',
        'msf1',
      }.contains(brand)) {
        return 'image/heic';
      }
    }
    return null;
  }
}
