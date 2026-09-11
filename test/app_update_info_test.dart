import 'package:flutter_test/flutter_test.dart';
import 'package:hoomy/models/app_update_info.dart';

void main() {
  group('compareVersions', () {
    test('compares semantic version names', () {
      expect(compareVersions('0.1.2', '0.1.1'), greaterThan(0));
      expect(compareVersions('0.1.2', '0.1.2'), 0);
    });

    test('compares build numbers when version names match', () {
      expect(compareVersions('0.1.2+2004', '0.1.2+2003'), greaterThan(0));
      expect(compareVersions('0.1.2+2004', '0.1.2+2004'), 0);
      expect(compareVersions('0.1.2+2003', '0.1.2+2004'), lessThan(0));
    });

    test('does not report update when current version matches latest', () {
      final info = AppUpdateInfo.fromJson(
        {'latestVersion': '0.1.2+2004'},
        currentVersion: '0.1.2+2004',
      );

      expect(info.hasUpdate, isFalse);
    });
  });
}
