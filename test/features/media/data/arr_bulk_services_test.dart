/// What Radarr's, Sonarr's and Readarr's editors do and do not say, and what
/// the client makes of it, each read against the arr's own source
/// (`MovieEditorController`, `SeriesEditorController`,
/// `AuthorEditorController`).
///
/// All three validate or save the set as a whole and name no title in a
/// refusal, so a result that says which title was refused can only come from
/// asking one at a time: one request when the arr takes the set, one per
/// title when it refuses the set (a 400, 409 or 422), and a failure that is no
/// title's thrown.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/api/arr_bulk.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// An arr, as far as its editors and its command queue go: it refuses any
/// request whose body or path names an id in [invalid] with a 400 that names a
/// property and no title.
class _Arr implements HttpClientAdapter {
  _Arr({this.invalid = const {}, this.statusForAll, this.profiles});

  final Set<int> invalid;
  final int? statusForAll;
  final Object? profiles;

  /// `method path ids` of every request, in the order it arrived.
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final queries = <Map<String, dynamic>>[];

  var _inFlight = 0;
  var widest = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final raw = requestStream == null
        ? ''
        : utf8.decode((await requestStream.toList()).expand((c) => c).toList());
    final body = raw.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    final ids = <int>[
      for (final key in const ['movieIds', 'seriesIds', 'authorIds'])
        ...?(body[key] as List?)?.cast<int>(),
      ?int.tryParse(options.uri.pathSegments.last),
      ?(body['seriesId'] as int?),
      ?(body['authorId'] as int?),
    ];
    requests.add('${options.method} ${options.uri.path} $ids');
    bodies.add(body);
    queries.add(options.uri.queryParameters);

    _inFlight++;
    widest = widest < _inFlight ? _inFlight : widest;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    _inFlight--;

    if (statusForAll != null) return _reply(statusForAll!, {'message': 'no'});
    if (options.uri.path.endsWith('/qualityprofile') ||
        options.uri.path.endsWith('/metadataprofile')) {
      return _reply(200, profiles ?? const []);
    }
    final refused = ids.where(invalid.contains).toList();
    if (refused.isNotEmpty) {
      return _reply(400, [
        {
          'propertyName': 'RootFolderPath',
          'errorMessage': 'The folder for ${refused.first} is not reachable',
        },
      ]);
    }
    return _reply(
      options.method == 'POST' ? 201 : 200,
      options.method == 'PUT' ? <Object?>[] : <String, dynamic>{},
    );
  }

  ResponseBody _reply(int status, Object body) => ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    },
  );
}

ApiClient _client(_Arr arr) {
  final client = ApiClient(baseUrl: 'https://arr.test', apiKey: 'k');
  client.dio.httpClientAdapter = arr;
  return client;
}

void main() {
  group('Radarr', () {
    test('the editor takes the set in one request, and only the fields '
        'Radarr’s resource has', () async {
      final arr = _Arr();

      final result = await RadarrService(_client(arr)).updateMoviesInBulk([
        1,
        2,
        3,
      ], const ArrBulkEdit(monitored: false, qualityProfileId: 4));

      expect(arr.requests, ['PUT /api/v3/movie/editor [1, 2, 3]']);
      expect(arr.bodies.single, {
        'movieIds': [1, 2, 3],
        'monitored': false,
        'qualityProfileId': 4,
      });
      expect(result.done, [1, 2, 3]);
    });

    test('a refusal of the set is asked again movie by movie, and the movie '
        'refused is the one Radarr refused', () async {
      final arr = _Arr(invalid: {2});

      final result = await RadarrService(
        _client(arr),
      ).updateMoviesInBulk([1, 2, 3], const ArrBulkEdit(monitored: true));

      expect(arr.requests.first, 'PUT /api/v3/movie/editor [1, 2, 3]');
      expect(arr.requests.skip(1).toList()..sort(), [
        'PUT /api/v3/movie/editor [1]',
        'PUT /api/v3/movie/editor [2]',
        'PUT /api/v3/movie/editor [3]',
      ]);
      expect(result.done, [1, 3]);
      expect(result.refused.keys, [2]);
      expect(
        failureServiceMessage(result.refused[2]),
        'The folder for 2 is not reachable',
      );
    });

    test('a failure that is no movie’s is thrown, with no fan-out', () async {
      for (final status in [401, 404, 500, 503]) {
        final arr = _Arr(statusForAll: status);
        await expectLater(
          RadarrService(
            _client(arr),
          ).updateMoviesInBulk([1, 2], const ArrBulkEdit(monitored: true)),
          throwsA(isA<DioException>()),
          reason: '$status',
        );
        expect(arr.requests, hasLength(1), reason: '$status');
      }
    });

    test('the removal sends Radarr’s own name for the exclusion: '
        '`addImportExclusion`', () async {
      final arr = _Arr();

      await RadarrService(
        _client(arr),
      ).removeMoviesInBulk([4, 7], deleteFiles: true, addImportExclusion: true);

      expect(arr.requests, ['DELETE /api/v3/movie/editor [4, 7]']);
      expect(arr.bodies.single, {
        'movieIds': [4, 7],
        'deleteFiles': true,
        'addImportExclusion': true,
      });
    });

    test('a removal Radarr refuses is asked again movie by movie', () async {
      final arr = _Arr(invalid: {7});

      final result = await RadarrService(
        _client(arr),
      ).removeMoviesInBulk([4, 7]);

      expect(result.done, [4]);
      expect(result.refused.keys, [7]);
    });

    test('a search is ONE MoviesSearch command with the list, which Radarr’s '
        'command takes', () async {
      final arr = _Arr();

      final result = await RadarrService(
        _client(arr),
      ).searchMoviesInBulk([5, 6, 7]);

      expect(arr.requests, ['POST /api/v3/command [5, 6, 7]']);
      expect(arr.bodies.single, {
        'name': 'MoviesSearch',
        'movieIds': [5, 6, 7],
      });
      expect(result.done, [5, 6, 7]);
    });

    test('a search Radarr refuses is thrown: one command has one answer', () {
      final arr = _Arr(invalid: {6});

      expect(
        RadarrService(_client(arr)).searchMoviesInBulk([5, 6]),
        throwsA(isA<DioException>()),
      );
    });

    test('its quality profiles are read so that a failure reaches the '
        'sheet', () async {
      final ok = _Arr(
        profiles: [
          {'id': 1, 'name': 'HD-1080p'},
        ],
      );
      expect(
        (await RadarrService(_client(ok)).getQualityProfilesOrThrow()).single,
        {'id': 1, 'name': 'HD-1080p'},
      );
      await expectLater(
        RadarrService(
          _client(_Arr(statusForAll: 503)),
        ).getQualityProfilesOrThrow(),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('Sonarr', () {
    test('the editor takes the set in one request, with monitorNewItems '
        'where it is chosen', () async {
      final arr = _Arr();

      final result = await SonarrService(_client(arr)).updateSeriesInBulk([
        1,
        2,
      ], const ArrBulkEdit(monitored: true, monitorNewItems: 'none'));

      expect(arr.requests, ['PUT /api/v3/series/editor [1, 2]']);
      expect(arr.bodies.single, {
        'seriesIds': [1, 2],
        'monitored': true,
        'monitorNewItems': 'none',
      });
      expect(result.done, [1, 2]);
    });

    test('a refusal of the set is asked again series by series', () async {
      final arr = _Arr(invalid: {2});

      final result = await SonarrService(
        _client(arr),
      ).updateSeriesInBulk([1, 2, 3], const ArrBulkEdit(qualityProfileId: 5));

      expect(arr.requests.skip(1).toList()..sort(), [
        'PUT /api/v3/series/editor [1]',
        'PUT /api/v3/series/editor [2]',
        'PUT /api/v3/series/editor [3]',
      ]);
      expect(result.done, [1, 3]);
      expect(result.refused.keys, [2]);
    });

    test('a failure that is no series’ is thrown', () async {
      final arr = _Arr(statusForAll: 500);
      await expectLater(
        SonarrService(
          _client(arr),
        ).updateSeriesInBulk([1, 2], const ArrBulkEdit(monitored: true)),
        throwsA(isA<DioException>()),
      );
      expect(arr.requests, hasLength(1));
    });

    test('the removal sends Sonarr’s name for the exclusion: '
        '`addImportListExclusion`', () async {
      final arr = _Arr();

      await SonarrService(_client(arr)).removeSeriesInBulk(
        [3],
        deleteFiles: true,
        addImportListExclusion: true,
      );

      expect(arr.bodies.single, {
        'seriesIds': [3],
        'deleteFiles': true,
        'addImportListExclusion': true,
      });
    });

    test('a search is one SeriesSearch command per series, which takes one '
        'id', () async {
      final arr = _Arr(invalid: {2});

      final result = await SonarrService(
        _client(arr),
      ).searchSeriesInBulk([1, 2, 3]);

      expect(arr.requests, hasLength(3));
      expect(arr.bodies.map((b) => b['name']).toSet(), {'SeriesSearch'});
      expect(arr.bodies.map((b) => b['seriesId']).toList()..sort(), [1, 2, 3]);
      expect(result.done, [1, 3]);
      expect(result.refused.keys, [2]);
      expect(arr.widest, lessThanOrEqualTo(4));
    });

    test('a series reads the albums-to-come setting its record carries', () {
      expect(
        SonarrSeries.fromJson({
          'id': 1,
          'monitorNewItems': 'none',
        }).monitorNewItems,
        'none',
      );
      expect(SonarrSeries.fromJson({'id': 2}).monitorNewItems, isNull);
    });
  });

  group('Readarr', () {});
}
