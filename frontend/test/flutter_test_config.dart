import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/security/device_id.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Widget tests run on a phone-sized screen (390 x 844 logical pixels) unless a
/// test sets `tester.view.physicalSize` itself. Flutter's default 800 x 600
/// surface is wider than `AppBreakpoints.medium`, which would put every test in
/// the tablet layout (navigation rail instead of the bottom bar).
const _phoneSize = Size(1170, 2532);
const _phonePixelRatio = 3.0;

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    DeviceId.resetForTesting();
    final view = binding.platformDispatcher.implicitView!;
    view.physicalSize = _phoneSize;
    view.devicePixelRatio = _phonePixelRatio;
  });
  tearDown(() {
    final view = binding.platformDispatcher.implicitView!;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  final supportDirectory = Directory(
    path.join(Directory.systemTemp.path, 'karaok-widget-tests-$pid'),
  );
  await supportDirectory.create(recursive: true);
  PathProviderPlatform.instance = _TestPathProvider(supportDirectory.path);
  try {
    await testMain();
  } finally {
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  }
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.supportPath);

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}
