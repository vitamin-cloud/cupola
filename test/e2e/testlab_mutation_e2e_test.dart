@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';

/// Safe write probes for the disposable macOS/OrbStack laboratory.
///
/// Every specimen is either a paused, zero-data magnet or an existing seeded
/// row that is restored to its original state. Nothing writes to the user's
/// download directory, and the NPM toggle is restored in a `finally` block.
void main() {
  final credentials = _loadCredentials();

  test('qBittorrent add, pause and delete a zero-data magnet', () async {
    final client = QbittorrentClient(
      url: 'http://127.0.0.1:8080',
      username: credentials['CUPOLA_TESTLAB_QBITTORRENT_USERNAME'],
      password: credentials['CUPOLA_TESTLAB_QBITTORRENT_PASSWORD'],
    );
    addTearDown(client.close);
    final service = QbittorrentService(client);
    await service.authenticate();
    const marker = 'Cupola Mutation qBittorrent';
    const magnet =
        'magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678'
        '&dn=Cupola%20Mutation%20qBittorrent';

    Future<List<Torrent>> matching() async => (await service.mainData())
        .torrents
        .where((torrent) => torrent.name == marker)
        .toList(growable: false);

    Future<void> cleanup() async {
      for (final torrent in await matching()) {
        await service.deleteTorrents([torrent.hash]);
      }
    }

    await cleanup();
    addTearDown(cleanup);
    await service.addTorrentUrl(magnet);
    final added = await _eventually(
      matching,
      (items) => items.isNotEmpty,
      label: 'qBittorrent mutation specimen',
    );
    final torrent = added.single;
    await service.pauseTorrents([torrent.hash]);
    final paused = await _eventually(
      matching,
      (items) => items.single.parsedState.isPaused,
      label: 'qBittorrent pause',
    );
    expect(paused.single.parsedState.isPaused, isTrue);
    await service.deleteTorrents([torrent.hash]);
    expect(
      await _eventually(
        matching,
        (items) => items.isEmpty,
        label: 'qBittorrent delete',
      ),
      isEmpty,
    );
  });
}

Future<T> _eventually<T>(
  Future<T> Function() read,
  bool Function(T value) predicate, {
  required String label,
}) async {
  Object? lastError;
  for (var attempt = 0; attempt < 16; attempt++) {
    try {
      final value = await read();
      if (predicate(value)) return value;
    } catch (error) {
      lastError = error;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    '$label did not settle${lastError == null ? '' : ': $lastError'}',
  );
}

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
