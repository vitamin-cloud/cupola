@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/network/cert_trust.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/dockge/data/dockge_client.dart';
import 'package:cupola/features/dockge/data/dockge_service.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/truenas/data/truenas_service.dart';
import 'package:cupola/features/truenas/data/truenas_ws_client.dart';

/// Disposable transport smoke for the full macOS/OrbStack laboratory.
///
/// The bootstrap writes the generated Seerr/Jellyfin values to a chmod-600
/// file. Pass its path with CUPOLA_TESTLAB_CREDENTIALS_FILE; fixed passwords and
/// API keys are intentionally kept in that file too, rather than in Git.
///
/// This suite proves service reachability, authentication and the first typed
/// read used by Cupola. It is not the native visual/integration suite: a green
/// result here does not prove that a route draws the right screen.
void main() {
  final credentials = _loadCredentials();

  test('Seerr REST + session', () async {
    final client = ApiClient(
      baseUrl: 'http://127.0.0.1:5055',
      apiKey: credentials['CUPOLA_TESTLAB_SEERR_API_KEY']!,
    );
    addTearDown(client.close);
    final service = SeerrService(client);
    final me = await client.get('/api/v1/auth/me');
    expect(me.data, isA<Map>());
    expect(await service.getRadarrServers(), isNotEmpty);
    expect(await service.getSonarrServers(), isNotEmpty);
    expect((await service.getRequests()), isA<List>());
  });

  test('Radarr REST + movie parser', () async {
    final client = _arr('http://127.0.0.1:7878');
    addTearDown(client.close);
    final service = RadarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getMoviesOrThrow(), isNotEmpty);
    expect(await service.getQueue(), isA<List>());
  });

  test('Sonarr REST + series parser', () async {
    final client = _arr('http://127.0.0.1:8989');
    addTearDown(client.close);
    final service = SonarrService(client);
    final status = await client.get('/api/v3/system/status');
    expect(status.data, isA<Map>());
    expect(await service.getSeriesOrThrow(), isNotEmpty);
    expect(await service.getQueue(), isA<List>());
  });

  test('qBittorrent form auth + torrent parser', () async {
    final client = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_QBITTORRENT_PASSWORD'],
    );
    addTearDown(client.close);
    final service = QbittorrentService(client);
    expect(await service.authenticate(), isTrue);
    expect(await service.getVersion(), isNotEmpty);
    final first = await service.mainData();
    expect(first.torrents, isNotEmpty);
    expect(first.transfer.dlSpeed, greaterThanOrEqualTo(0));
    // The next read asks only for what changed, and still holds every torrent.
    final next = await service.mainData();
    expect(
      next.torrents.map((t) => t.hash).toSet(),
      first.torrents.map((t) => t.hash).toSet(),
    );
  });

  test('Jellyfin token auth + library parser', () async {
    final client = JellyfinClient(
      baseUrl: 'http://127.0.0.1:8096',
      apiKey: credentials['CUPOLA_TESTLAB_JELLYFIN_TOKEN']!,
      userId: credentials['CUPOLA_TESTLAB_JELLYFIN_USER_ID']!,
      deviceName: 'Cupola TestLab E2E',
      deviceId: 'cupola-testlab-e2e',
    );
    addTearDown(client.close);
    expect(await client.verifyCredential(), isTrue);
    expect(await client.probeVersion(), isNotEmpty);
    expect(await client.getLibraries(), isNotEmpty);
    expect(await client.getSessions(), isA<List>());
  });

  test('Dockge Socket.IO login + stack list', () async {
    final client = DockgeClient(
      baseUrl: 'http://127.0.0.1:5001',
      username: credentials['CUPOLA_TESTLAB_DOCKGE_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_DOCKGE_PASSWORD'],
    );
    addTearDown(client.close);
    final service = DockgeService(client);
    // Dockge installations may omit the optional version field while still
    // accepting the authenticated Socket.IO session.
    await service.fetchVersion();
    expect(await service.fetchStacks(), isA<List>());
  });

  test('TrueNAS WebSocket JSON-RPC over TLS + dashboard parser', () async {
    // The address a person saves: https://, with the self-signed certificate
    // trusted by its fingerprint. The client dials wss:// from it.
    final client = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: _truenasPin(credentials),
    );
    addTearDown(client.close);
    expect(client.resolveEndpoint().scheme, 'wss');
    final service = TrueNasService(client);
    expect(await service.ping(), isTrue);
    final dashboard = await service.loadDashboard();
    expect(dashboard.system.hostname, isNotEmpty);
    expect(dashboard.pools, isA<List>());
  });

  test(
    'TrueNAS certificate probe reads the fingerprint the lab recorded',
    () async {
      // The trust prompt on "Test connection" shows what this probe reads, and a
      // person's saved pin is that same text: the bootstrap's must be too.
      final certificate = await probeServerCertificate(
        '127.0.0.1',
        _truenasPort,
      );
      expect(certificate, isNotNull);
      expect(certificate!.fingerprint, _truenasPin(credentials));
    },
  );

  test('TrueNAS refuses a certificate it was not told to trust as untrusted, '
      'not as a dead server', () async {
    final pin = _truenasPin(credentials);
    // The server is there and answers: the same address, with its own pin.
    final trusted = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: pin,
    );
    addTearDown(trusted.close);
    expect(await TrueNasService(trusted).ping(), isTrue);

    // A pin that is one digit off: a certificate that was replaced after the
    // person trusted the old one. Never sent a key, never read as a dead host.
    final rotated = TrueNasWsClient(
      baseUrl: _truenasUrl,
      apiKey: 'test-key',
      certFingerprint: _oneDigitOff(pin),
    );
    addTearDown(rotated.close);
    await _expectUntrusted(
      TrueNasService(rotated).ping(),
      'a pin one digit off',
    );

    // No pin at all: the platform's trust store does not know the lab's
    // self-signed certificate, and nothing makes an exception for it.
    final unpinned = TrueNasWsClient(baseUrl: _truenasUrl, apiKey: 'test-key');
    addTearDown(unpinned.close);
    await _expectUntrusted(TrueNasService(unpinned).ping(), 'no pin');

    // The contrast: where nothing listens, the same code reads unreachable.
    final dead = TrueNasWsClient(
      baseUrl: 'https://127.0.0.1:${await _closedPort()}',
      apiKey: 'test-key',
      certFingerprint: pin,
    );
    addTearDown(dead.close);
    await expectLater(
      TrueNasService(dead).ping(),
      throwsA(
        isA<TrueNasException>().having(
          (error) => classifyConnectionFailure(error),
          'reason',
          ServiceFailureReason.unreachable,
        ),
      ),
      reason: 'a port nothing listens on',
    );
  });
}

ApiClient _arr(String baseUrl) =>
    ApiClient(baseUrl: baseUrl, apiKey: 'test-key');

const _truenasPort = 8460;

/// TrueNAS as a person saves it. The client derives `wss://` from it.
const _truenasUrl = 'https://127.0.0.1:$_truenasPort';

/// The fingerprint the bootstrap recorded for the TrueNAS mock's certificate:
/// 64 lowercase hex digits, the form `certFingerprint` compares.
String _truenasPin(Map<String, String> credentials) {
  final pin = credentials['CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT'];
  if (pin == null || pin.isEmpty) {
    fail(
      'Missing CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT in the lab credentials: '
      'run test/e2e/testlab/truenas_cert.sh credentials (see test/e2e/README.md)',
    );
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin)) {
    fail(
      'CUPOLA_TESTLAB_TRUENAS_CERT_FINGERPRINT must be 64 lowercase hex digits '
      'without colons, the SHA-256 of the certificate',
    );
  }
  return pin;
}

/// [pin] with its first digit changed, still a well-formed fingerprint.
String _oneDigitOff(String pin) =>
    '${pin.startsWith('0') ? '1' : '0'}${pin.substring(1)}';

/// A loopback port nothing listens on: bound a moment ago, then released.
Future<int> _closedPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// [call] fails the way a certificate the app does not trust fails: a TLS
/// refusal, classified [ServiceFailureReason.tls] and nothing else. Not
/// unreachable (the server answered the handshake), not a refused key (no key
/// was sent), not the cleartext refusal (the address was dialled).
Future<void> _expectUntrusted(Future<Object?> call, String reason) =>
    expectLater(
      call,
      throwsA(
        isA<TrueNasException>()
            .having(
              (error) => classifyConnectionFailure(error),
              'reason',
              ServiceFailureReason.tls,
            )
            .having(
              (error) => error is TrueNasInsecureTransportException,
              'refused as cleartext',
              isFalse,
            ),
      ),
      reason: reason,
    );

Map<String, String> _loadCredentials() {
  final path = Platform.environment['CUPOLA_TESTLAB_CREDENTIALS_FILE'];
  if (path == null || path.isEmpty) {
    fail(
      'CUPOLA_TESTLAB_CREDENTIALS_FILE must point to the bootstrap output '
      '(.ai/testlab/state/credentials.env)',
    );
  }
  final file = File(path);
  if (!file.existsSync()) fail('Missing testlab credentials file: $path');
  final values = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final separator = line.indexOf('=');
    if (separator <= 0) continue;
    values[line.substring(0, separator)] = line.substring(separator + 1);
  }
  return values;
}
