import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The in-memory store is the only seam that sees every preferences write.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

/// Saving settings writes what changed, and a reload from nothing but disk
/// always gives back exactly what was saved.
///
/// The same scenarios run twice: whole-model saves (what every save did
/// before) and saves against the last persisted model. Whatever the mode, the
/// disk afterwards must be byte for byte what one whole-model save of the
/// final model writes on an empty install.

/// Counts and, on demand, interrupts every write to preferences and to secure
/// storage, in the one order they happen.
class _Ops {
  int writes = 0;
  int? interruptAt;

  void tick() {
    writes++;
    final at = interruptAt;
    if (at != null && writes >= at) {
      throw StateError('interrupted');
    }
  }
}

class _CountingPrefsStore extends InMemorySharedPreferencesStore {
  _CountingPrefsStore(this.ops, Map<String, Object> data)
    : super.withData(data);

  final _Ops ops;
  int prefsWrites = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    ops.tick();
    prefsWrites++;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    ops.tick();
    prefsWrites++;
    return super.remove(key);
  }
}

class _CountingSecureStore extends FakeSecureSettingsStore {
  _CountingSecureStore(this.ops);

  final _Ops ops;
  int secureWrites = 0;

  @override
  Future<void> write({required String key, required String value}) async {
    ops.tick();
    secureWrites++;
    await super.write(key: key, value: value);
  }

  @override
  Future<void> delete({required String key}) async {
    ops.tick();
    secureWrites++;
    await super.delete(key: key);
  }
}

/// One install: its preferences store, secure store and a service over them.
class _Disk {
  _Disk._(this.ops, this.prefsStore, this.secure);

  final _Ops ops;
  final _CountingPrefsStore prefsStore;
  final _CountingSecureStore secure;

  static Future<_Disk> empty() async {
    final ops = _Ops();
    final prefsStore = _CountingPrefsStore(ops, {});
    return _Disk._(ops, prefsStore, _CountingSecureStore(ops));
  }

  Future<SharedPreferences> prefs() async {
    SharedPreferencesStorePlatform.instance = prefsStore;
    SharedPreferences.resetStatic();
    return SharedPreferences.getInstance();
  }

  /// A service started now, as a new process would.
  Future<SettingsService> service() async =>
      SettingsService(await prefs(), secure);

  /// Everything on disk, read back from nothing.
  Future<SettingsModel> reload() async {
    final saved = ops.interruptAt;
    ops.interruptAt = null;
    final model = await (await service()).loadSettings();
    ops.interruptAt = saved;
    return model;
  }

  /// Every key and value on disk, preferences then secure storage.
  Future<Map<String, String>> dump() async => {
    for (final entry in (await prefsStore.getAll()).entries)
      'prefs:${entry.key}': '${entry.value}',
    for (final entry in secure.entries.entries)
      'secure:${entry.key}': entry.value,
  };
}

final _cloudflare = const CloudflareServiceToken(
  clientId: 'id-one',
  clientSecret: 'sentinel-cf-secret',
);

ServiceInstance _primary(
  ServiceKey key, {
  String url = 'http://nas.home.arpa:7878',
  String credential = '',
  String username = '',
  String viewerId = '',
  ConnectionAccess access = const NoAccess(),
  ConnectionAddress? away,
  SeerrAccountSignIn? account,
}) => ServiceInstance(
  id: ServiceInstance.primaryIdFor(key),
  service: key,
  url: url,
  credential: credential,
  username: username,
  viewerId: viewerId,
  access: access,
  away: away,
  account: account,
);

final _account = SeerrAccountSignIn(
  kind: SeerrAccountKind.local,
  login: 'anna@home.arpa',
  userId: 2,
  displayName: 'Anna',
  session: 'sentinel-session',
  permissions: 32,
  checkedAt: DateTime.utc(2026, 10, 1, 20, 41),
);

/// Six connections of every kind of stored thing: keys, credentials, a viewer,
/// a second instance, gateways at home and away, a Seerr account, a trusted
/// certificate.
SettingsModel _installed() => SettingsModel(
  plexClientId: 'plex-client-0001',
  trustedCertificates: const {'https://truenas.home.arpa:443': 'abcd1234'},
  instances: [
    _primary(
      ServiceKey.radarr,
      credential: 'sentinel-radarr-key',
      access: _cloudflare,
      away: const ConnectionAddress(
        url: 'https://radarr.example.net',
        access: CustomHeaders([
          (name: 'X-One', value: 'sentinel-h1'),
          (name: 'X-Two', value: 'sentinel-h2'),
          (name: 'X-Three', value: 'sentinel-h3'),
        ]),
      ),
    ),
    ServiceInstance(
      id: 'radarr-00000a1',
      service: ServiceKey.radarr,
      label: '4K',
      url: 'http://nas.home.arpa:7879',
      credential: 'sentinel-radarr4k-key',
    ),
    _primary(
      ServiceKey.sonarr,
      url: 'http://nas.home.arpa:8989',
      credential: 'sentinel-sonarr-key',
      access: const ProxyPassword(
        username: 'proxy-user',
        password: 'sentinel-proxy-pass',
      ),
    ),
    _primary(
      ServiceKey.qbittorrent,
      url: 'https://nas.home.arpa:8080',
      username: 'admin',
      credential: 'sentinel-qb-pass',
    ),
    _primary(
      ServiceKey.jellyfin,
      url: 'http://nas.home.arpa:8096',
      credential: 'sentinel-jf-key',
      viewerId: 'viewer-77',
    ),
    _primary(
      ServiceKey.seerr,
      url: 'http://nas.home.arpa:5055',
      account: _account,
    ),
  ],
);

SettingsModel _withKey(SettingsModel model, String id, String credential) =>
    model.copyWith(
      instances: [
        for (final instance in model.instances)
          if (instance.id == id)
            instance.copyWith(credential: credential)
          else
            instance,
      ],
    );

void main() {
  for (final delta in [false, true]) {
    group(delta ? 'saving against the last persisted' : 'whole-model', () {
      Future<void> save(
        SettingsService service,
        SettingsModel next,
        SettingsModel? previous,
      ) => delta
          ? service.saveSettings(next, previous: previous)
          : service.saveSettings(next);

      Future<_Disk> savedThrough(List<SettingsModel> models) async {
        final disk = await _Disk.empty();
        final service = await disk.service();
        SettingsModel? last;
        for (final model in models) {
          await save(service, model, last);
          last = model;
        }
        return disk;
      }

      void expectSameAs(SettingsModel loaded, SettingsModel expected) {
        expect(loaded.trustedCertificates, expected.trustedCertificates);
        expect(loaded.plexClientId, expected.plexClientId);
        expect(
          [for (final i in loaded.instances) i.id],
          [for (final i in expected.instances) i.id],
        );
        for (final instance in expected.instances) {
          expect(
            loaded.instanceById(instance.id),
            instance,
            reason: 'instance ${instance.id}',
          );
        }
      }

      test(
        'a reload gives back what was saved, instance by instance',
        () async {
          final disk = await savedThrough([_installed()]);
          expectSameAs(await disk.reload(), _installed());
        },
      );

      test('changing one secret leaves the others as they were', () async {
        final disk = await savedThrough([
          _installed(),
          _withKey(_installed(), 'sonarr', 'sentinel-sonarr-key-2'),
        ]);

        final loaded = await disk.reload();
        expect(
          loaded.instanceById('sonarr')?.credential,
          'sentinel-sonarr-key-2',
        );
        expect(
          loaded.instanceById('radarr')?.credential,
          'sentinel-radarr-key',
        );
        expect(loaded.instanceById('radarr')?.access, _cloudflare);
        expect(
          loaded.instanceById('radarr-00000a1')?.credential,
          'sentinel-radarr4k-key',
        );
        expect(loaded.instanceById('seerr')?.account, _account);
      });
    });
  }
}
