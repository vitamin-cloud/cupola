import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/demo/demo_session.dart';
import 'package:cupola/demo/world/profiles.dart';

/// The arrs once the world lives: a film or a series added, monitored, let
/// go, searched for, grabbed by hand, imported by hand, and arrived.
void main() {
  late ProfileNetwork network;

  setUp(() {
    network = ProfileNetwork(demoProfile)..live();
    addTearDown(network.install());
  });

  Future<Object?> send(String method, String url, {Object? json}) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse(url));
      if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return body.isEmpty ? null : jsonDecode(body);
    } finally {
      client.close();
    }
  }

  const radarr = '${WorldHosts.radarr}/api/v3';
  const sonarr = '${WorldHosts.sonarr}/api/v3';
  final nosferatu = WorldTitles.catalogue.firstWhere(
    (t) => t.key == 'nosferatu',
  );

  Future<List<Map<String, Object?>>> list(String url) async =>
      ((await send('GET', url)) as List).cast<Map<String, Object?>>();

  Future<List<Map<String, Object?>>> queue(String base) async =>
      (((await send('GET', '$base/queue?pageSize=50')) as Map)['records']
              as List)
          .cast<Map<String, Object?>>();

  Future<Map<String, Object?>> movie(String title) async =>
      (await list('$radarr/movie')).firstWhere((m) => m['title'] == title);

  group('Radarr', () {
    test('a film added with a search is fetched and arrives, newest in the '
        'history', () async {
      final added =
          await send(
                'POST',
                '$radarr/movie',
                json: {
                  'tmdbId': nosferatu.tmdbId,
                  'title': nosferatu.title,
                  'monitored': true,
                  'addOptions': {'searchForMovie': true},
                },
              )
              as Map;
      expect(added['hasFile'], isFalse);
      expect(
        (await queue(radarr)).map((r) => r['title']),
        contains(startsWith('Nosferatu')),
      );

      network.elapse(const Duration(minutes: 2));
      expect((await movie('Nosferatu'))['hasFile'], isTrue);
      expect(
        (await queue(radarr)).map((r) => r['title']),
        isNot(contains(startsWith('Nosferatu'))),
      );
      final history =
          ((await send('GET', '$radarr/history?pageSize=10')) as Map)['records']
              as List;
      expect(((history.first as Map)['movie'] as Map)['title'], 'Nosferatu');
    });

    test('keeps its monitoring and lets a film go', () async {
      final sintel = await movie('Sintel');
      await send(
        'PUT',
        '$radarr/movie/${sintel['id']}',
        json: {...sintel, 'monitored': false},
      );
      expect((await movie('Sintel'))['monitored'], isFalse);
      await send('DELETE', '$radarr/movie/${sintel['id']}?deleteFiles=true');
      expect(
        (await list('$radarr/movie')).map((m) => m['title']),
        isNot(contains('Sintel')),
      );
    });

    test('another download for a stuck one: the row removed, a search, and '
        'a fresh grab', () async {
      final rows = await queue(radarr);
      final stuck = rows.indexWhere(
        (r) => '${r['title']}'.startsWith('Big.Buck.Bunny'),
      );
      await send(
        'DELETE',
        '$radarr/queue/${stuck + 1}?removeFromClient=true&blocklist=true',
      );
      final bunny = await movie('Big Buck Bunny');
      await send(
        'POST',
        '$radarr/command',
        json: {
          'name': 'MoviesSearch',
          'movieIds': [bunny['id']],
        },
      );
      final fresh = (await queue(
        radarr,
      )).where((r) => '${r['title']}'.startsWith('Big.Buck.Bunny'));
      expect(fresh, hasLength(1));
      expect(fresh.single['status'], isNot('warning'));
    });

    test('an interactive search lists releases and a grab fetches the one '
        'picked', () async {
      final added =
          await send(
                'POST',
                '$radarr/movie',
                json: {'tmdbId': nosferatu.tmdbId, 'monitored': true},
              )
              as Map;
      final releases = await list('$radarr/release?movieId=${added['id']}');
      expect(releases, hasLength(3));
      final picked = releases[1];
      await send(
        'POST',
        '$radarr/release',
        json: {'guid': picked['guid'], 'indexerId': picked['indexerId']},
      );
      expect(
        (await queue(radarr)).map((r) => r['title']),
        contains(picked['title']),
      );
    });
  });

  group('Sonarr', () {
    Future<Map<String, Object?>> cosmos() async => (await list(
      '$sonarr/series',
    )).firstWhere((s) => s['title'] == 'Cosmos Laundromat');

    test('an episode that finishes is on disk, and counted', () async {
      final before = (await cosmos())['statistics'] as Map;
      network.elapse(const Duration(minutes: 2));
      final episodes = await list('$sonarr/episode?seriesId=1');
      final e4 = episodes.firstWhere(
        (e) => e['seasonNumber'] == 2 && e['episodeNumber'] == 4,
      );
      expect(e4['hasFile'], isTrue);
      expect(
        ((await cosmos())['statistics'] as Map)['episodeFileCount'],
        (before['episodeFileCount'] as int) + 1,
      );
    });

    test('a series added with a search arrives as a season', () async {
      final breakingBad = WorldTitles.catalogue.firstWhere(
        (t) => t.key == 'breakingBad',
      );
      final added =
          await send(
                'POST',
                '$sonarr/series',
                json: {
                  'tvdbId': breakingBad.tvdbId,
                  'monitored': true,
                  'addOptions': {'searchForMissingEpisodes': true},
                },
              )
              as Map;
      expect((added['statistics'] as Map)['episodeFileCount'], 0);
      network.elapse(const Duration(minutes: 2));
      final series = (await list(
        '$sonarr/series',
      )).firstWhere((s) => s['title'] == breakingBad.title);
      expect((series['statistics'] as Map)['episodeFileCount'], 8);
    });

    test('an import by hand takes a blocked download off the queue', () async {
      final blocked = WorldDownloads.blockedImports.first;
      final before = await queue(sonarr);
      expect(
        before.map((r) => '${r['downloadId']}'.toLowerCase()),
        contains(blocked.id.toLowerCase()),
      );
      await send(
        'POST',
        '$sonarr/command',
        json: {
          'name': 'ManualImport',
          'importMode': 'move',
          'files': [
            {
              'path': '/mnt/tank/downloads/complete/${blocked.release}',
              'downloadId': blocked.id,
              'seriesId': 1,
            },
          ],
        },
      );
      expect(
        (await queue(sonarr)).map((r) => '${r['downloadId']}'.toLowerCase()),
        isNot(contains(blocked.id.toLowerCase())),
      );
    });

    test('keeps a season\'s monitoring', () async {
      final series = await cosmos();
      final seasons = [
        for (final s in (series['seasons'] as List).cast<Map>())
          {...s, 'monitored': s['seasonNumber'] != 3},
      ];
      await send(
        'PUT',
        '$sonarr/series/${series['id']}',
        json: {...series, 'seasons': seasons},
      );
      final third = ((await cosmos())['seasons'] as List)
          .cast<Map>()
          .firstWhere((s) => s['seasonNumber'] == 3);
      expect(third['monitored'], isFalse);
    });
  });

  group('Lidarr', () {
    const lidarr = '${WorldHosts.lidarr}/api/v1';

    test('answers a name it does not hold with a row that has no id, and the '
        'world\'s own artist with its id', () async {
      final rows = await list('$lidarr/artist/lookup?term=elbow');
      expect(rows.single['artistName'], 'Elbow');
      expect(rows.single.containsKey('id'), isFalse);
      expect(rows.single['foreignArtistId'], startsWith('lookup-'));

      final own = await list('$lidarr/artist/lookup?term=jan');
      expect(own.single['id'], 1);
    });

    test('offers its folder with the defaults a new artist is given, and its '
        'metadata profile with the types it keeps', () async {
      final folder = (await list('$lidarr/rootfolder')).single;
      expect(folder['defaultQualityProfileId'], 1);
      expect(folder['defaultMetadataProfileId'], 1);
      expect(folder['defaultMonitorOption'], 'all');
      expect(folder['defaultNewItemMonitorOption'], 'all');

      final profiles = await list('$lidarr/metadataprofile');
      // Lidarr's own `None`, which keeps no release type, files an artist
      // added for one album.
      expect(profiles.map((p) => p['name']), ['Standard', 'None']);
      final profile = profiles.first;
      final allowed = [
        for (final type in (profile['primaryAlbumTypes'] as List).cast<Map>())
          if (type['allowed'] == true) (type['albumType'] as Map)['name'],
      ];
      expect(allowed, ['Album', 'EP']);
    });

    test('a search for an artist is a command Lidarr takes', () async {
      final command =
          await send(
                'POST',
                '$lidarr/command',
                json: {'name': 'ArtistSearch', 'artistId': 1002},
              )
              as Map;
      expect(command['name'], 'ArtistSearch');
      expect(command['status'], 'queued');
    });

    test('finds the world\'s own artist and albums as the library holds '
        'them, and for any other word one artist and one album that it '
        'does not', () async {
      final own = await list('$lidarr/search?term=elephants');
      expect(own.single['foreignId'], 'album-jm-1');
      expect((own.single['album'] as Map)['title'], 'Elephants Dream');
      expect((own.single['album'] as Map)['id'], 1);

      final artist = await list('$lidarr/search?term=jan');
      expect((artist.single['artist'] as Map)['id'], 1);

      final other = await list('$lidarr/search?term=elbow');
      expect(other, hasLength(2));
      expect((other.first['artist'] as Map)['artistName'], 'Elbow');
      expect((other.first['artist'] as Map)['id'], 0);
      final album = other.last['album'] as Map;
      expect(album['id'], 0);
      expect((album['artist'] as Map)['foreignArtistId'], 'lookup-elbow');

      expect(await list('$lidarr/search?term='), isEmpty);
    });

    test('an album added brings its artist with it, holds that one album '
        'and no other, and is held when searched again', () async {
      final added =
          await send(
                'POST',
                '$lidarr/album',
                json: {
                  'title': 'Elbow',
                  'foreignAlbumId': 'lookup-album-elbow',
                  'albumType': 'Album',
                  'monitored': true,
                  'artist': {
                    'artistName': 'Elbow',
                    'foreignArtistId': 'lookup-elbow',
                  },
                  'addOptions': {'searchForNewAlbum': true},
                },
              )
              as Map;
      expect((added['artist'] as Map)['id'], 2);
      expect(added['monitored'], isTrue);

      // The artist is in the library; the albums Lidarr would read for one
      // added by itself never come, since only this one was asked for.
      network.elapse(const Duration(seconds: 10));
      final albums = await list('$lidarr/album?artistId=2');
      expect(albums.map((a) => a['title']), ['Elbow']);
      expect(
        (await list('$lidarr/album')).map((a) => a['foreignAlbumId']),
        contains('lookup-album-elbow'),
      );

      // Searched again, the catalog's artist carries the library's id.
      final again = await list('$lidarr/search?term=elbow');
      expect((again.first['artist'] as Map)['id'], 2);

      // Adding it again finds it, as Lidarr's 400 would refuse it.
      await send(
        'POST',
        '$lidarr/album',
        json: {
          'title': 'Elbow',
          'foreignAlbumId': 'lookup-album-elbow',
          'artist': {'artistName': 'Elbow', 'foreignArtistId': 'lookup-elbow'},
        },
      );
      expect(await list('$lidarr/album?artistId=2'), hasLength(1));
    });

    test('monitors the albums it is told to, and takes the search', () async {
      await send(
        'POST',
        '$lidarr/album',
        json: {
          'title': 'Elbow',
          'foreignAlbumId': 'lookup-album-elbow',
          'monitored': true,
          'artist': {'artistName': 'Elbow', 'foreignArtistId': 'lookup-elbow'},
        },
      );
      await send(
        'PUT',
        '$lidarr/album/monitor',
        json: {
          'albumIds': [200],
          'monitored': false,
        },
      );
      expect(
        (await list(
          '$lidarr/album',
        )).firstWhere((a) => a['id'] == 200)['monitored'],
        isFalse,
      );

      final command =
          await send(
                'POST',
                '$lidarr/command',
                json: {
                  'name': 'AlbumSearch',
                  'albumIds': [200],
                },
              )
              as Map;
      expect(command['name'], 'AlbumSearch');
    });
  });

  group('the editors of the other arrs', () {
    const readarr = '${WorldHosts.readarr}/api/v1';

    test('Radarr sets monitoring on some movies and removes others', () async {
      final movies = await list('$radarr/movie');
      final first = movies.first['id'];
      final second = movies[1]['id'];

      await send(
        'PUT',
        '$radarr/movie/editor',
        json: {
          'movieIds': [first],
          'monitored': false,
        },
      );
      await send(
        'DELETE',
        '$radarr/movie/editor',
        json: {
          'movieIds': [second],
        },
      );

      final now = await list('$radarr/movie');
      expect(now.firstWhere((m) => m['id'] == first)['monitored'], isFalse);
      expect(now.map((m) => m['id']), isNot(contains(second)));
    });

    test('Sonarr sets monitoring on some series and removes others', () async {
      final shows = await list('$sonarr/series');
      final first = shows.first['id'];
      final second = shows[1]['id'];

      await send(
        'PUT',
        '$sonarr/series/editor',
        json: {
          'seriesIds': [first],
          'monitored': false,
        },
      );
      await send(
        'DELETE',
        '$sonarr/series/editor',
        json: {
          'seriesIds': [second],
        },
      );

      final now = await list('$sonarr/series');
      expect(now.firstWhere((m) => m['id'] == first)['monitored'], isFalse);
      expect(now.map((m) => m['id']), isNot(contains(second)));
    });

    test('Readarr sets monitoring on its author and removes it by its own '
        'route', () async {
      await send(
        'PUT',
        '$readarr/author/editor',
        json: {
          'authorIds': [1],
          'monitored': false,
        },
      );
      expect((await list('$readarr/author')).single['monitored'], isFalse);
      expect(await list('$readarr/metadataprofile'), hasLength(2));

      await send('DELETE', '$readarr/author/1');
      expect(await list('$readarr/author'), isEmpty);
    });

    test('a search for each is a command the arr takes', () async {
      for (final (base, body) in [
        (
          radarr,
          {
            'name': 'MoviesSearch',
            'movieIds': [1],
          },
        ),
        (sonarr, {'name': 'SeriesSearch', 'seriesId': 1}),
        (readarr, {'name': 'AuthorSearch', 'authorId': 1}),
      ]) {
        final command = await send('POST', '$base/command', json: body) as Map;
        expect(command['status'], 'queued');
      }
    });
  });
}
