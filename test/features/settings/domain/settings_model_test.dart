import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_glyphs.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('SettingsModel.urlFor', () {
    final settings = settingsWith(
      seerrUrl: 'https://jelly.example.com',
      radarrUrl: 'https://radarr.example.com',
      sonarrUrl: 'https://sonarr.example.com',
    );
  });

  group('SettingsModel.apiKeyFor', () {
    final settings = settingsWith(
      seerrApiKey: 'jkey',
      radarrApiKey: 'rkey',
      sonarrApiKey: 'skey',
    );
  });

  // The three-way "is it qBittorrent, Dockge or NZBGet" check used to be spelled
  // out in five files. Adding a credential-authenticated service therefore meant
  // finding all five by hand, and missing one left persistence and the settings
  // form disagreeing about which fields the service even has. These lock the
  // answer to the registry capability instead.
  group('the credential model comes from the registry', () {
    final credentials = settingsWith(
      qbittorrentUsername: 'qb-user',
      qbittorrentPassword: 'qb-pass',
      dockgeUsername: 'dockge-user',
      dockgePassword: 'dockge-pass',
      radarrApiKey: 'radarr-key',
    );

    test('a credential service counts as configured on its URL alone', () {
      // Some can legitimately run with no auth behind a reverse proxy, so a
      // missing password is not a missing configuration.
      final urlOnly = settingsWith(
        qbittorrentUrl: 'https://qb.lan:8080',
        radarrUrl: 'https://radarr.lan:7878',
      );

      expect(urlOnly.isServiceConfigured(ServiceKey.qbittorrent), isTrue);
      // An API-key service still needs both halves.
      expect(urlOnly.isServiceConfigured(ServiceKey.radarr), isFalse);
    });
  });

  group('SettingsModel.copyWithoutUnusedCertificate', () {
    const fingerprint = 'aa:bb';

    test('forgets a pin nothing configured reaches any more', () {
      // Without this the entry outlives the address, and because pins are keyed
      // purely by origin, any service later pointed back there would silently
      // reuse the stale trust with no prompt.
      final settings = const SettingsModel()
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://nas.lan:8989',
            apiKey: 'k',
          )
          .copyWithTrustedCertificate(
            url: 'https://nas.lan:8989',
            fingerprint: fingerprint,
          );

      final moved = settings
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://elsewhere.lan:8989',
            apiKey: 'k',
          )
          .copyWithoutUnusedCertificate('https://nas.lan:8989');

      expect(moved.pinForUrl('https://nas.lan:8989'), isNull);
    });

    test('keeps a pin another configured service still shares', () {
      // Removing Sonarr must never break Radarr's trust in the same proxy.
      final settings = const SettingsModel()
          .copyWithService(
            ServiceKey.sonarr,
            url: 'https://nas.lan:443',
            apiKey: 'k',
          )
          .copyWithService(
            ServiceKey.radarr,
            url: 'https://nas.lan:443',
            apiKey: 'k',
          )
          .copyWithTrustedCertificate(
            url: 'https://nas.lan:443',
            fingerprint: fingerprint,
          );

      final removed = settings
          .copyWithService(ServiceKey.sonarr, url: '', apiKey: '')
          .copyWithoutUnusedCertificate('https://nas.lan:443');

      expect(removed.pinForUrl('https://nas.lan:443'), fingerprint);
    });

    test('an empty prior URL is a no-op', () {
      final settings = const SettingsModel().copyWithTrustedCertificate(
        url: 'https://nas.lan:443',
        fingerprint: fingerprint,
      );

      expect(
        settings.copyWithoutUnusedCertificate('').trustedCertificates,
        settings.trustedCertificates,
      );
    });
  });

  group('SettingsModel.copyWithService', () {
    const base = SettingsModel();

    test('partial update only changes provided fields', () {
      final updated = base.copyWithService(
        ServiceKey.sonarr,
        url: 'https://sonarr.local',
      );

      expect(updated.urlFor(ServiceKey.sonarr), 'https://sonarr.local');
      expect(updated.apiKeyFor(ServiceKey.sonarr), '');
    });

    test('works for all ServiceKey values', () {
      for (final key in ServiceKey.values) {
        final updated = base.copyWithService(key, url: 'https://test');
        expect(updated.urlFor(key), 'https://test');
      }
    });
  });

  group('SettingsModel.themeMode', () {});

  group('NavTab', () {});

  group('ServiceKey.routeParam', () {});

  group('ServiceKey metadata', () {
    test('every service draws its own mark from the service glyph font', () {
      for (final service in ServiceKey.values) {
        expect(
          service.icon.fontFamily,
          ServiceGlyphs.fontFamily,
          reason: '${service.title} fell back to a category glyph',
        );
      }
      // A mark is only an identity while no two services share it.
      final codePoints = ServiceKey.values.map((s) => s.icon.codePoint);
      expect(codePoints.toSet(), hasLength(ServiceKey.values.length));
    });
  });
}
