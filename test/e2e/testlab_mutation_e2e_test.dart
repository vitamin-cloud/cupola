@Tags(['e2e'])
library;

import 'dart:convert';
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

/// The four NPM admin calls the scoped-account probe needs. They are not part
/// of the app's client on purpose: Cupola never manages NPM users.
class _NpmAdmin {
  _NpmAdmin({required this.url, required this.identity, required this.secret});

  final String url;
  final String identity;
  final String secret;
  final HttpClient _http = HttpClient();
  String? _token;

  Future<dynamic> _call(String method, String path, [Object? body]) async {
    _token ??=
        (await _send('POST', '/api/tokens', {
                  'identity': identity,
                  'secret': secret,
                }, auth: false)
                as Map)['token']
            as String;
    return _send(method, path, body);
  }

  Future<dynamic> _send(
    String method,
    String path,
    Object? body, {
    bool auth = true,
  }) async {
    final request = await _http.openUrl(method, Uri.parse('$url$path'));
    request.headers.contentType = ContentType.json;
    if (auth) request.headers.set('Authorization', 'Bearer $_token');
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw StateError('NPM $method $path: ${response.statusCode} $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }

  Future<int> createUser({
    required String email,
    required String password,
    required Map<String, String> permissions,
  }) async {
    final user =
        await _call('POST', '/api/users', {
              'name': 'Cupola scoped',
              'nickname': 'scoped',
              'email': email,
              'roles': <String>[],
              'is_disabled': false,
            })
            as Map;
    final id = user['id'] as int;
    await _call('PUT', '/api/users/$id/auth', {
      'type': 'password',
      'secret': password,
    });
    await setPermissions(id, permissions);
    return id;
  }

  Future<void> setPermissions(int id, Map<String, String> permissions) =>
      _call('PUT', '/api/users/$id/permissions', permissions);

  Future<void> deleteUser(int id) => _call('DELETE', '/api/users/$id');

  Future<void> deleteUserByEmail(String email) async {
    final users = await _call('GET', '/api/users') as List;
    for (final user in users.whereType<Map>()) {
      if (user['email'] == email) await deleteUser(user['id'] as int);
    }
  }

  void close() => _http.close(force: true);
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
