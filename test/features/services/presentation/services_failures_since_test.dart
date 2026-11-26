/// The downloads that failed in the last week, read like the week's imports.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The moment the week is read from: the harness's own clock.
DateTime _now(ProfileHarness harness) => harness.network.now;

ProviderContainer _container(ProfileHarness harness) {
  final container = ProviderContainer(
    overrides: [
      ...harness.overrides,
      arrivalsClockProvider.overrideWith(
        (ref) =>
            () => _now(harness),
      ),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

Future<ArrHistory> _arrivals(ProviderContainer container) {
  container.listen(servicesArrivalsProvider, (_, _) {});
  return container.read(servicesArrivalsProvider.future);
}

Future<ArrHistory> _failures(ProviderContainer container) {
  container.listen(servicesFailuresSinceProvider, (_, _) {});
  return container.read(servicesFailuresSinceProvider.future);
}

String _stamp(ProfileHarness harness, Duration ago) =>
    _now(harness).subtract(ago).toUtc().toIso8601String();

/// One history record as an arr sends it, with the media it embeds.
Map<String, Object?> _record(
  ProfileHarness harness, {
  required int id,
  required String eventType,
  Duration ago = const Duration(hours: 2),
  String? sourceTitle,
  Map<String, Object?>? data,
  String? media,
}) => {
  'id': id,
  'eventType': eventType,
  'date': _stamp(harness, ago),
  'sourceTitle': ?sourceTitle,
  'data': data ?? const <String, Object?>{},
  if (media == 'movie') ...{
    'movieId': id,
    'movie': {'id': id, 'title': 'Movie $id', 'year': 2024, 'tmdbId': 100 + id},
  },
  if (media == 'series') ...{
    'seriesId': id,
    'series': {'id': id, 'title': 'Series $id', 'tmdbId': 100 + id},
  },
  if (media == 'artist') ...{
    'artistId': id,
    'artist': {'artistName': 'Artist $id'},
    'album': {'id': id, 'title': 'Album $id'},
  },
};

void main() {
  group('servicesFailuresSinceProvider', () {
    Map<String, String> asked(
      ProfileHarness harness,
      String server,
      String path,
    ) => harness.network
        .requestsTo(server)
        .singleWhere((r) => r.method == 'GET' && r.path == path)
        .query;

    test('it keeps the failed downloads, and drops a record of any other '
        'event, a failed import included', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/history/since',
        (r) => NetworkReply.json([
          _record(
            harness,
            id: 1,
            eventType: 'downloadFailed',
            media: 'movie',
            data: {'message': 'Aborted'},
          ),
          _record(harness, id: 2, eventType: 'grabbed', media: 'movie'),
          _record(harness, id: 3, eventType: 'importFailed', media: 'movie'),
          _record(
            harness,
            id: 4,
            eventType: 'downloadFolderImported',
            media: 'movie',
          ),
          _record(
            harness,
            id: 5,
            eventType: 'downloadFailed',
            media: 'movie',
            ago: const Duration(days: 3),
          ),
        ]),
      );

      final week = await _failures(_container(harness));

      final radarr = [
        for (final entry in week.entries)
          if (entry.service == ServiceKey.radarr &&
              entry.instanceId == WorldIds.radarr)
            entry,
      ];
      // The failure is the week's, with the arr's own reason; the four
      // others are not.
      expect(radarr.map((entry) => entry.id), [1, 5]);
      expect(radarr.first.reason, 'Aborted');
      expect(
        radarr.every((entry) => entry.outcome == ArrImportOutcome.failed),
        isTrue,
      );
      expect(radarr.first.tmdbId, 101);
    });

    test(
      'a failure carries no file name, whatever else its record holds',
      () async {
        final harness = await ProfileHarness.start(Profiles.p1);
        harness.network.on(
          WorldIds.radarr,
          'GET',
          '/api/v3/history/since',
          (r) => NetworkReply.json([
            _record(
              harness,
              id: 1,
              eventType: 'downloadFailed',
              media: 'movie',
              sourceTitle: 'Movie.1.2024.1080p',
              data: {'message': 'Aborted', 'importedPath': '/x/y.mkv'},
            ),
          ]),
        );

        final week = await _failures(_container(harness));

        final failed = week.entries.firstWhere(
          (entry) => entry.service == ServiceKey.radarr,
        );
        expect(failed.outcome, ArrImportOutcome.failed);
        expect(failed.fileName, isNull);
      },
    );

    test('it is the week Arrived reads: one clock, one window', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      final container = _container(harness);
      await _arrivals(container);
      await _failures(container);

      final dates = {
        for (final r in harness.network.requestsTo(WorldIds.radarr))
          if (r.path == '/api/v3/history/since') r.query['date'],
      };
      expect(dates, hasLength(1));
    });
  });
}
