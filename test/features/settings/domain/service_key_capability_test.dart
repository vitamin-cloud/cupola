import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('hasScopedCredential', () {
    test('is false for Jellyfin', () {
      // A non-admin Jellyfin token is only ever shown sessions it may control,
      // so a gate would dim session controls that work.
      expect(ServiceKey.jellyfin.hasScopedCredential, isFalse);
    });
  });

  group('the capability copy', () {});
}
