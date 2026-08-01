import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
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
