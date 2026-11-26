import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

import '../../../test_helpers/settings_scope.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('SettingsService', () {
    late SharedPreferences prefs;
    late FakeSecureSettingsStore secureStore;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStore = FakeSecureSettingsStore();
      service = SettingsService(prefs, secureStore);
    });

    test('migrateFromPlaintext is idempotent', () async {
      await prefs.setString('radarr_api_key', 'radarr-key');

      await service.migrateFromPlaintext();
      await service.migrateFromPlaintext();

      expect(
        await secureStore.read(key: 'secure_radarr_api_key'),
        'radarr-key',
      );
      expect(prefs.getString('radarr_api_key'), isNull);
    });

    test('migrateFromPlaintext skips empty keys', () async {
      await prefs.setString('radarr_api_key', '   ');

      await service.migrateFromPlaintext();

      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
      expect(prefs.getString('radarr_api_key'), isNull);
    });

    test('migrateFromPlaintext preserves existing secure seerr key', () async {
      await secureStore.write(
        key: 'secure_seerr_api_key',
        value: 'existing-seerr-key',
      );
      await prefs.setString('jellyseerr_api_key', 'legacy-jellyseerr-key');

      await service.migrateFromPlaintext();

      expect(
        await secureStore.read(key: 'secure_seerr_api_key'),
        'existing-seerr-key',
      );
      expect(prefs.getString('jellyseerr_api_key'), isNull);
    });

    test('loadSettings falls back to legacy Jellyseerr keys', () async {
      await prefs.setString('jellyseerr_url', 'https://legacy.example.com');
      await secureStore.write(
        key: 'secure_jellyseerr_api_key',
        value: 'legacy-seerr-key',
      );

      final loaded = await service.loadSettings();

      expect(loaded.urlFor(ServiceKey.seerr), 'https://legacy.example.com');
      expect(loaded.apiKeyFor(ServiceKey.seerr), 'legacy-seerr-key');
    });

    test('saveSettings removes secure keys when values are empty', () async {
      final populatedSettings = settingsWith(radarrApiKey: 'radarr-key');
      const clearedSettings = SettingsModel();

      await service.saveSettings(populatedSettings);
      await service.saveSettings(clearedSettings);

      expect(await secureStore.read(key: 'secure_radarr_api_key'), isNull);
    });

    test('clearAll removes legacy keys too', () async {
      await prefs.setString('jellyseerr_url', 'https://legacy.example.com');
      await prefs.setString('jellyseerr_api_key', 'legacy-key');
      await prefs.setString('radarr_api_key', 'plaintext-key');
      await secureStore.write(
        key: 'secure_jellyseerr_api_key',
        value: 'legacy-seerr-key',
      );

      await service.clearAll();

      expect(prefs.getString('jellyseerr_url'), isNull);
      expect(prefs.getString('jellyseerr_api_key'), isNull);
      expect(prefs.getString('radarr_api_key'), isNull);
      expect(await secureStore.read(key: 'secure_jellyseerr_api_key'), isNull);
    });

    group('trusted certificates (ADR-6)', () {
      const fingerprint =
          'ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab1';

      test('saveSettings and loadSettings round-trip the trust map', () async {
        final settings = settingsWith(
          radarrUrl: 'https://nas.local:8443',
          radarrApiKey: 'radarr-key',
          trustedCertificates: {'https://nas.local:8443': fingerprint},
        );

        await service.saveSettings(settings);
        final loaded = await service.loadSettings();

        expect(loaded.trustedCertificates, {
          'https://nas.local:8443': fingerprint,
        });
      });

      test('the trust map lives in secure storage, never in prefs', () async {
        const settings = SettingsModel(
          trustedCertificates: {'https://nas.local:8443': fingerprint},
        );
        await service.saveSettings(settings);

        expect(prefs.getString('secure_trusted_certificates'), isNull);
        expect(
          await secureStore.read(key: 'secure_trusted_certificates'),
          contains(fingerprint),
        );
      });

      test('an empty trust map deletes the secure entry outright', () async {
        const populated = SettingsModel(
          trustedCertificates: {'https://nas.local:8443': fingerprint},
        );
        await service.saveSettings(populated);
        expect(
          await secureStore.read(key: 'secure_trusted_certificates'),
          isNotNull,
        );

        await service.saveSettings(const SettingsModel());
        expect(
          await secureStore.read(key: 'secure_trusted_certificates'),
          isNull,
        );
      });

      test(
        'migrates the two ADR-5 per-service fingerprints into origin keys',
        () async {
          await prefs.setString('truenas_url', 'https://nas.local:8443');
          await prefs.setString('dockge_url', 'https://nas.local:5001');
          await secureStore.write(
            key: 'truenas_cert_fingerprint',
            value: fingerprint,
          );
          const dockgeFingerprint =
              '11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11aa22bb33cc11a';
          await secureStore.write(
            key: 'dockge_cert_fingerprint',
            value: dockgeFingerprint,
          );

          final loaded = await service.loadSettings();

          expect(loaded.trustedCertificates, {
            'https://nas.local:8443': fingerprint,
            'https://nas.local:5001': dockgeFingerprint,
          });
          // Migration only runs once per install: the legacy keys are gone.
          expect(
            await secureStore.read(key: 'truenas_cert_fingerprint'),
            isNull,
          );
          expect(
            await secureStore.read(key: 'dockge_cert_fingerprint'),
            isNull,
          );
        },
      );

      test(
        'a legacy fingerprint with no saved URL is dropped rather than guessed',
        () async {
          // No truenas_url saved: the origin the pin belonged to is
          // unknowable, so ADR-6 accepts losing it: the user re-trusts on
          // next connect rather than the app inventing a key for it.
          await secureStore.write(
            key: 'truenas_cert_fingerprint',
            value: fingerprint,
          );

          final loaded = await service.loadSettings();

          expect(loaded.trustedCertificates, isEmpty);
          expect(
            await secureStore.read(key: 'truenas_cert_fingerprint'),
            isNull,
          );
        },
      );

      test('clearAll wipes the trust map and the legacy keys', () async {
        await prefs.setString('truenas_url', 'https://nas.local:8443');
        await secureStore.write(
          key: 'truenas_cert_fingerprint',
          value: fingerprint,
        );
        await service.loadSettings(); // triggers the one-time migration
        await service.saveSettings(
          settingsWith(
            trustedCertificates: {'https://nas.local:8443': fingerprint},
          ),
        );

        await service.clearAll();

        final loaded = await service.loadSettings();
        expect(loaded.trustedCertificates, isEmpty);
        expect(
          await secureStore.read(key: 'secure_trusted_certificates'),
          isNull,
        );
      });
    });

    group('scheme-less URL migration', () {
      // Older builds stored the address field verbatim, and qBittorrent's had no
      // validator at all, so a working install can hold `192.168.1.5:8080`. That
      // value used to mean `http://` (the client prepended it), and now means
      // `https://`, so on upgrade the same config dies in the TLS handshake with
      // no fallback. Nothing writes a scheme-less URL any more, so anything in
      // storage without one is by definition pre-normalisation data.
      test('a scheme-less qBittorrent URL keeps meaning http://', () async {
        await prefs.setString('qbittorrent_url', '192.168.1.5:8080');

        final loaded = await service.loadSettings();

        expect(
          loaded.urlFor(ServiceKey.qbittorrent),
          'http://192.168.1.5:8080',
        );
        // Written back, so the rewrite happens once instead of on every load;
        // and so it survives even if the user never saves anything.
        expect(prefs.getString('qbittorrent_url'), 'http://192.168.1.5:8080');
      });

      test('Dockge is migrated too: same commit changed both', () async {
        await prefs.setString('dockge_url', 'nas.lan:5001');

        expect(
          (await service.loadSettings()).urlFor(ServiceKey.dockge),
          'http://nas.lan:5001',
        );
      });

      // The concrete loss the scoping prevents: a self-signed NAS the user
      // already trusted keeps its pin, because the URL still resolves to the
      // `https://` origin the fingerprint is filed under.
      test('a scheme-less TrueNAS URL keeps finding its pinned cert', () async {
        await prefs.setString('truenas_url', 'nas.lan');
        await secureStore.write(
          key: 'secure_trusted_certificates',
          value: '{"https://nas.lan:443":"AA:BB"}',
        );

        final loaded = await service.loadSettings();

        expect(loaded.pinForUrl(loaded.urlFor(ServiceKey.truenas)), 'AA:BB');
      });

      test('an explicit scheme is never rewritten', () async {
        await prefs.setString('radarr_url', 'https://radarr.lan:7878');
        await prefs.setString('sonarr_url', 'http://sonarr.lan:8989');

        final loaded = await service.loadSettings();

        expect(loaded.urlFor(ServiceKey.radarr), 'https://radarr.lan:7878');
        expect(loaded.urlFor(ServiceKey.sonarr), 'http://sonarr.lan:8989');
      });

      test('a host that cannot be parsed is left alone', () async {
        // Nothing here was ever a working configuration, so inventing a scheme
        // for it would only turn one unusable value into a different one.
        await prefs.setString('qbittorrent_url', '::::');

        expect(
          (await service.loadSettings()).urlFor(ServiceKey.qbittorrent),
          '::::',
        );
      });

      test('an empty URL stays empty rather than becoming http://', () async {
        expect(
          (await service.loadSettings()).urlFor(ServiceKey.qbittorrent),
          isEmpty,
        );
        expect(prefs.getString('qbittorrent_url'), isNull);
      });

      test('it is idempotent across loads', () async {
        await prefs.setString('qbittorrent_url', '192.168.1.5:8080');

        await service.loadSettings();
        final loaded = await service.loadSettings();

        expect(
          loaded.urlFor(ServiceKey.qbittorrent),
          'http://192.168.1.5:8080',
        );
      });

      // The fix for the upgrade break is split across two files: this migration
      // writes `http://`, and `QbittorrentClient.normalizeBaseUrl` must carry
      // that scheme through rather than applying its https default. Each half is
      // covered on its own side; this joins them, because the bug only exists in
      // the seam and either half alone can be "correct" while the pair is not.
      test('the migrated URL survives into the client that reads it', () async {
        await prefs.setString('qbittorrent_url', '192.168.1.5:8080');

        final loaded = await service.loadSettings();
        final client = QbittorrentClient(
          url: loaded.urlFor(ServiceKey.qbittorrent),
        );
        addTearDown(client.close);

        expect(client.baseUrl, 'http://192.168.1.5:8080');
      });
    });
  });
}
