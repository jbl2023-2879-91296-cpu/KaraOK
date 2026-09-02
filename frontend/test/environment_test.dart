import 'package:flutter_test/flutter_test.dart';
import 'package:karaok_app/core/config/environment.dart';

void main() {
  test('local API default uses the backend IPv4 loopback address', () {
    expect(Environment.apiBaseUrl, 'http://127.0.0.1:5000/api');
  });
}
