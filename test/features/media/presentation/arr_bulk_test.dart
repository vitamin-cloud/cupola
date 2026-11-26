/// What the selection bar asks before it acts on several movies, series or
/// authors: each service's sheets built from what its editor accepts, and the
/// nouns each one says them in.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_bulk.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_bulk.dart';

/// An arr that answers every write and records it as `method path`, with the
/// body and the query.
class _Arr implements HttpClientAdapter {
  final requests = <String>[];
  final bodies = <Map<String, dynamic>>[];
  final queries = <Map<String, dynamic>>[];

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
    final path = options.uri.path;
    Object reply = <String, dynamic>{};
    if (options.method == 'GET') {
      reply = path.endsWith('/qualityprofile')
          ? [
              {'id': 1, 'name': 'Any'},
              {'id': 2, 'name': 'HD-1080p'},
            ]
          : path.endsWith('/metadataprofile')
          ? [
              {'id': 1, 'name': 'Standard'},
              {'id': 2, 'name': 'Fiction only'},
            ]
          : <Object?>[];
    } else {
      requests.add('${options.method} $path');
      bodies.add(
        raw.isEmpty
            ? const <String, dynamic>{}
            : jsonDecode(raw) as Map<String, dynamic>,
      );
      queries.add(options.uri.queryParameters);
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(reply))),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }
}

ApiClient _client(_Arr arr) {
  final client = ApiClient(baseUrl: 'https://arr.test', apiKey: 'k');
  client.dio.httpClientAdapter = arr;
  return client;
}

const _gib = 1024 * 1024 * 1024;

RadarrMovie _movie(int id, String title, {int size = _gib}) =>
    RadarrMovie.fromJson({
      'id': id,
      'title': title,
      'sortTitle': title.toLowerCase(),
      'year': 1922,
      'monitored': true,
      'sizeOnDisk': size,
      'qualityProfileId': 1,
      'images': const [],
    });

SonarrSeries _series(int id, String title) => SonarrSeries.fromJson({
  'id': id,
  'title': title,
  'sortTitle': title.toLowerCase(),
  'monitored': true,
  'monitorNewItems': 'all',
  'qualityProfileId': 1,
  'statistics': {'sizeOnDisk': _gib},
  'images': const [],
});

/// The actions of [bulkOf] over a selection, each behind a button that runs
/// what it asks.
class _Host<T> extends ConsumerStatefulWidget {
  const _Host(this.bulkOf, this.items);

  final MediaBulk<T> Function(WidgetRef ref) bulkOf;
  final List<T> items;

  @override
  ConsumerState<_Host<T>> createState() => _HostState<T>();
}

class _HostState<T> extends ConsumerState<_Host<T>> {
  var outcome = 'nothing yet';

  @override
  Widget build(BuildContext context) {
    final bulk = widget.bulkOf(ref);
    return Scaffold(
      body: Column(
        children: [
          for (final action in bulk.actions)
            TextButton(
              onPressed: () async {
                final job = await action.prepare(context, widget.items);
                if (job == null) return;
                final result = await job.run(widget.items);
                setState(() => outcome = 'done ${result.done.length}');
              },
              child: Text('Run ${action.label}'),
            ),
          Text(outcome),
        ],
      ),
    );
  }
}

Future<_Arr> _pump<T>(
  WidgetTester tester, {
  required MediaBulk<T> Function(WidgetRef ref) bulkOf,
  required List<T> items,
}) async {
  final arr = _Arr();
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        radarrServiceForProvider.overrideWith(
          (ref, id) => RadarrService(_client(arr)),
        ),
        sonarrServiceForProvider.overrideWith(
          (ref, id) => SonarrService(_client(arr)),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: _Host<T>(bulkOf, items),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return arr;
}

final _movies = [
  _movie(1, 'Metropolis'),
  _movie(2, 'Nosferatu'),
  _movie(3, 'Sherlock Jr.'),
];
final _shows = [
  _series(1, 'Cosmos Laundromat'),
  _series(2, 'Cowboy Bebop'),
  _series(3, 'Hero'),
];

final _threeGb = formatBytes(3 * _gib);

void main() {
  group('the words', () {});

  group('Search over many titles', () {
    List<SonarrSeries> many(int n) => [
      for (var i = 1; i <= n; i++) _series(i, 'Show $i'),
    ];
    MediaBulk<SonarrSeries> sonarr(WidgetRef ref) =>
        sonarrBulk(ref: ref, instanceId: 'sonarr', name: 'Sonarr');
    MediaBulk<RadarrMovie> radarr(WidgetRef ref) =>
        radarrBulk(ref: ref, instanceId: 'radarr', name: 'Radarr');

    testWidgets('50 titles run without asking', (tester) async {
      final arr = await _pump(tester, bulkOf: sonarr, items: many(50));

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();

      expect(find.text('Search 50 series in Sonarr?'), findsNothing);
      expect(arr.requests, hasLength(50));
    });

    testWidgets('51 titles ask first, and Not now sends nothing', (
      tester,
    ) async {
      final arr = await _pump(tester, bulkOf: sonarr, items: many(51));

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();

      expect(find.text('Search 51 series in Sonarr?'), findsOneWidget);
      expect(
        find.text(
          'Sonarr searches them one by one, and the searches can’t be '
          'stopped from here.',
        ),
        findsOneWidget,
      );
      expect(arr.requests, isEmpty);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(arr.requests, isEmpty);

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search 51 series'));
      await tester.pumpAndSettle();
      expect(arr.requests, hasLength(51));
    });

    testWidgets('Radarr asks above 50 too, then sends its one command', (
      tester,
    ) async {
      final arr = await _pump(
        tester,
        bulkOf: radarr,
        items: [for (var i = 1; i <= 51; i++) _movie(i, 'Movie $i')],
      );

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();
      expect(find.text('Search 51 movies in Radarr?'), findsOneWidget);
      expect(arr.requests, isEmpty);

      await tester.tap(find.text('Search 51 movies'));
      await tester.pumpAndSettle();
      expect(arr.requests, ['POST /api/v3/command']);
    });
  });

  group('Movies', () {
    MediaBulk<RadarrMovie> bulkOf(WidgetRef ref) =>
        radarrBulk(ref: ref, instanceId: 'radarr', name: 'Radarr');

    testWidgets('Monitor is one control: no second row, only `monitored` '
        'is sent', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _movies);

      await tester.tap(find.text('Run Monitor'));
      await tester.pumpAndSettle();

      expect(find.text('Monitor 3 movies'), findsOneWidget);
      expect(find.text('Metropolis, Nosferatu and Sherlock Jr.'), findsOne);
      expect(find.text('Stop monitoring'), findsOneWidget);
      expect(find.textContaining('Monitor new'), findsNothing);
      expect(find.text('Leave as is'), findsNothing);

      await tester.tap(find.text('Stop monitoring'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to 3 movies'));
      await tester.pumpAndSettle();

      expect(arr.requests, ['PUT /api/v3/movie/editor']);
      expect(arr.bodies.single, {
        'movieIds': [1, 2, 3],
        'monitored': false,
      });
    });

    testWidgets('Profile is the quality profile alone, Apply live on a '
        'change', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _movies);

      await tester.tap(find.text('Run Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile for 3 movies'), findsOneWidget);
      expect(find.text('Quality profile'), findsOneWidget);
      expect(find.text('Metadata profile'), findsNothing);
      final apply = find.widgetWithText(FilledButton, 'Apply to 3 movies');
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      await tester.tap(find.text('Quality profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HD-1080p'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await tester.pumpAndSettle();

      expect(arr.bodies.single, {
        'movieIds': [1, 2, 3],
        'qualityProfileId': 2,
      });
    });

    testWidgets('Remove asks in Radarr’s words and sends Radarr’s own flag '
        'names', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _movies);

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 3 movies from Radarr?'), findsOneWidget);
      expect(find.text('Radarr stops looking for them.'), findsOneWidget);
      expect(find.text('Also delete $_threeGb of files'), findsOneWidget);
      expect(find.text('Don’t add them again'), findsOneWidget);
      expect(find.text('Keep them'), findsOneWidget);

      await tester.tap(find.text('Don’t add them again'));
      await tester.pump();
      await tester.tap(find.text('Remove 3 movies and don’t add them again'));
      await tester.pumpAndSettle();

      expect(arr.requests, ['DELETE /api/v3/movie/editor']);
      expect(arr.bodies.single, {
        'movieIds': [1, 2, 3],
        'deleteFiles': false,
        'addImportExclusion': true,
      });
    });

    testWidgets('Search is one command for the list', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _movies);

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();

      expect(arr.requests, ['POST /api/v3/command']);
      expect(arr.bodies.single['movieIds'], [1, 2, 3]);
    });

    testWidgets('nothing on disk offers no files, and says so', (tester) async {
      await _pump(
        tester,
        bulkOf: bulkOf,
        items: [_movie(1, 'A', size: 0), _movie(2, 'B', size: 0)],
      );

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Also delete'), findsNothing);
      expect(
        find.text(
          'Radarr stops looking for them. None of them are on your server '
          'yet.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Series', () {
    MediaBulk<SonarrSeries> bulkOf(WidgetRef ref) =>
        sonarrBulk(ref: ref, instanceId: 'sonarr', name: 'Sonarr');

    testWidgets('Monitor has `Monitor new seasons`, started on what they '
        'share, and sends it', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _shows);

      await tester.tap(find.text('Run Monitor'));
      await tester.pumpAndSettle();

      expect(find.text('Monitor 3 series'), findsOneWidget);
      expect(find.text('Monitor new seasons'), findsOneWidget);
      expect(find.text('Leave as is'), findsOneWidget);

      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply to 3 series'));
      await tester.pumpAndSettle();

      expect(arr.requests, ['PUT /api/v3/series/editor']);
      expect(arr.bodies.single, {
        'seriesIds': [1, 2, 3],
        'monitored': true,
        'monitorNewItems': 'none',
      });
    });

    testWidgets('Profile is the quality profile alone', (tester) async {
      await _pump(tester, bulkOf: bulkOf, items: _shows);

      await tester.tap(find.text('Run Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Profile for 3 series'), findsOneWidget);
      expect(find.text('Metadata profile'), findsNothing);
    });

    testWidgets('Remove is worded for series and sends Sonarr’s flag '
        'names', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _shows);

      await tester.tap(find.text('Run Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove 3 series from Sonarr?'), findsOneWidget);
      expect(find.text('Sonarr stops looking for them.'), findsOneWidget);
      await tester.tap(find.text('Remove 3 series'));
      await tester.pumpAndSettle();

      expect(arr.bodies.single, {
        'seriesIds': [1, 2, 3],
        'deleteFiles': false,
        'addImportListExclusion': false,
      });
    });

    testWidgets('Search is one command per series', (tester) async {
      final arr = await _pump(tester, bulkOf: bulkOf, items: _shows);

      await tester.tap(find.text('Run Search'));
      await tester.pumpAndSettle();

      expect(arr.bodies.map((b) => b['name']).toSet(), {'SeriesSearch'});
      expect(arr.bodies.map((b) => b['seriesId']).toList()..sort(), [1, 2, 3]);
    });
  });
}
