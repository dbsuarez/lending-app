import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/update/update_checker.dart';

void main() {
  test('detects a newer timestamp build', () {
    expect(isNewerBuild('20261109_1501', '20261109_1430'), isTrue);
  });

  test('does not offer an older or identical timestamp build', () {
    expect(isNewerBuild('20261109_1430', '20261109_1430'), isFalse);
    expect(isNewerBuild('20261109_1400', '20261109_1430'), isFalse);
  });

  test('supports non timestamp build identifiers', () {
    expect(isNewerBuild('release-b', 'release-a'), isTrue);
    expect(isNewerBuild('release-a', 'release-a'), isFalse);
  });
}
