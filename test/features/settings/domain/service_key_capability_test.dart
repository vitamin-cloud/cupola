import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('hasScopedCredential', () {
    test('is true for exactly Unraid, TrueNAS, Nginx Proxy Manager and '
        'Plex', () {
      expect(ServiceKey.values.where((s) => s.hasScopedCredential).toSet(), {
        ServiceKey.unraid,
        ServiceKey.truenas,
        // A shared account's token is refused who is watching.
        ServiceKey.plex,
      });
    });

    test('is false for Jellyfin', () {
      // A non-admin Jellyfin token is only ever shown sessions it may control,
      // so a gate would dim session controls that work.
      expect(ServiceKey.jellyfin.hasScopedCredential, isFalse);
    });
  });

  group('the capability copy', () {

    test('a Plex credential is a token, as Plex and its form call it', () {
      expect(ServiceKey.plex.capabilityCredentialNoun, 'token');
    });
  });
}
