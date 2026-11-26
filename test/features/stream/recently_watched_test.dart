import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// What the household finished last, as each media server is asked it: the
/// latest first, a series once for all its episodes, and nothing a server
/// sends back that it does not say was watched.
void main() {
  group('Jellyfin', () {
    const viewer = '8c4f2a1e9b7d4c3a8f5e2d1c9b8a7f6e';

    JellyfinClient client(_Adapter adapter, {String userId = viewer}) {
      final client = JellyfinClient(
        baseUrl: 'https://jf.test',
        apiKey: 'SECRET-KEY',
        userId: userId,
        clientName: 'Cupola',
        deviceName: 'macos',
        deviceId: 'DEVICE-ID-1',
        appVersion: '0.8.0',
      );
      client.dio.httpClientAdapter = adapter;
      addTearDown(client.close);
      return client;
    }

    Map<String, Object?> played(
      String id,
      String name, {
      String type = 'Movie',
      String? at,
      bool played = true,
      String? series,
      String? tmdb,
    }) => {
      'Id': id,
      'Name': name,
      'Type': type,
      'SeriesId': ?series,
      'ProviderIds': {'Tmdb': ?tmdb},
      'UserData': {'Played': played, 'LastPlayedDate': ?at},
    };

    _Adapter history() => _Adapter((uri) {
      if (uri.queryParameters['ids'] case final ids?) {
        expect(ids, 'series-1');
        return {
          'Items': [
            {
              'Id': 'series-1',
              'Name': 'The Expanse',
              'Type': 'Series',
              'ProviderIds': {'Tmdb': '63639'},
            },
          ],
        };
      }
      // Answered in no order, with an unplayed film and an undated one: a
      // server that ignores the filter must not make them history.
      return {
        'Items': [
          played('m-1', 'Sintel', at: '2026-10-01T20:00:00Z', tmdb: '45745'),
          played(
            'e-2',
            'Caliban',
            type: 'Episode',
            series: 'series-1',
            at: '2026-10-03T21:00:00Z',
          ),
          played(
            'e-1',
            'Dulcinea',
            type: 'Episode',
            series: 'series-1',
            at: '2026-10-02T21:00:00Z',
          ),
          played('m-2', 'Agent 327', played: false, tmdb: '1'),
          played('m-3', 'Spring', tmdb: '2'),
        ],
      };
    });

    test('the latest first, a series once for its episodes', () async {
      final adapter = history();
      final watched = await client(adapter).getRecentlyWatched();

      expect(
        [for (final w in watched) w.item.title],
        ['The Expanse', 'Sintel'],
      );
      expect(watched.first.item.kind, StreamItemKind.series);
      expect(watched.first.item.externalIds.tmdb, '63639');
      expect(watched.first.playedAt, DateTime.utc(2026, 10, 3, 21));

      final asked = adapter.uris.first.queryParameters;
      expect(asked['userId'], viewer);
      expect(asked['isPlayed'], 'true');
      expect(asked['sortBy'], 'DatePlayed');
      expect(asked['sortOrder'], 'Descending');
      expect(adapter.uris, hasLength(2));
    });

    test('no more than asked for', () async {
      final watched = await client(history()).getRecentlyWatched(limit: 1);
      expect([for (final w in watched) w.item.title], ['The Expanse']);
    });

    test('no viewer chosen: nothing, and nothing asked', () async {
      final adapter = history();
      expect(await client(adapter, userId: '').getRecentlyWatched(), isEmpty);
      expect(adapter.uris, isEmpty);
    });

    test('a server that does not answer has nothing to say', () async {
      final adapter = _Adapter((_) => null, status: 500);
      expect(await client(adapter).getRecentlyWatched(), isEmpty);
    });
  });
}

/// Answers each request with what [reply] makes of its URI, recording them.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply, {this.status = 200});

  final Object? Function(Uri uri) reply;
  final int status;
  final List<Uri> uris = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    uris.add(options.uri);
    final body = reply(options.uri);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      body == null && status == 200 ? 404 : status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}
