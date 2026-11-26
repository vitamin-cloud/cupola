@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/host_reach.dart';
import 'package:cupola/features/settings/data/route_knock.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The route probe's knock table against the macOS laboratory: every service
/// answers its knock with no key, and no service answers another's.
///
/// Needs the lab up (`test/e2e/testlab/bootstrap.sh`); no credentials, which
/// is the point.
void main() {
  const lab = <ServiceKey, String>{
    ServiceKey.seerr: 'http://127.0.0.1:5055',
    ServiceKey.radarr: 'http://127.0.0.1:7878',
    ServiceKey.sonarr: 'http://127.0.0.1:8989',
    ServiceKey.qbittorrent: 'http://127.0.0.1:8080',
    ServiceKey.jellyfin: 'http://127.0.0.1:8096',
    ServiceKey.dockge: 'http://127.0.0.1:5001',
    ServiceKey.truenas: 'https://127.0.0.1:8460',
  };

  Future<bool> knock(ServiceKey service, String url) => knockAt(
    service,
    (url: url, access: const NoAccess(), pin: null),
    timeout: const Duration(seconds: 3),
    hostReach: tcpHostReach,
  );

  test('every service answers its own knock, with no key', () async {
    expect(lab.keys.toSet(), ServiceKey.values.toSet());
    for (final MapEntry(key: service, value: url) in lab.entries) {
      expect(await knock(service, url), isTrue, reason: '$service at $url');
    }
  });

  test('a port nobody listens on is not an answer', () async {
    expect(await knock(ServiceKey.radarr, 'http://127.0.0.1:1'), isFalse);
  });
}
