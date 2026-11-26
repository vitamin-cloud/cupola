import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/series/presentation/sonarr_overview_provider.dart';

void main() {
  // A fixed instant, never `DateTime.now()`: every rule under test takes its
  // `now` explicitly, which is the whole reason they are top-level functions.
  final now = DateTime(2026, 9, 2, 14, 30);

  group('the week window', () {});

  group('whether an empty week can be believed', () {});

  group('naming the record', () {
    test('an episode record reads as a slot', () {
      expect(
        sonarrEpisodeSlot({
          'episode': {'seasonNumber': 2, 'episodeNumber': 5},
        }),
        'S2\u00A0E5',
      );
    });

    test('a season pack falls back to the bare season', () {
      // The board's own example row. Without this the season pack loses the
      // only thing that identifies which part of the series failed.
      expect(sonarrEpisodeSlot({'seasonNumber': 4}), 'S4');
    });

    test('a record naming neither says nothing rather than guessing', () {
      expect(sonarrEpisodeSlot({'title': 'Some.Release.1080p'}), isNull);
    });
  });

  group('queue faults', () {
    test('faults are amber and the backlog is neutral', () {
      // The five-arm tone rule, asserted rather than left to review: painting
      // the backlog amber is the single most common way it is broken.
      expect(SonarrAttentionKind.stalled.tone, StatusTone.warning);
      expect(SonarrAttentionKind.importFailed.tone, StatusTone.warning);
      expect(SonarrAttentionKind.missing.tone, StatusTone.neutral);
      expect(SonarrAttentionKind.belowCutoff.tone, StatusTone.neutral);
    });
  });

  group('queue faults lead to where the fault is fixed', () {});

  group('the backlog rows', () {});

  group('the series a backlog page spans', () {
    test('is null when the page is only a sample of the backlog', () {
      // Twenty rows out of two hundred span the series those twenty happened to
      // touch. Printing that as a fact about the library is a sampling artefact
      // wearing a number.
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
          {'seriesId': 2},
        ],
        total: 200,
      );

      expect(sonarrSeriesSpread(page), isNull);
    });

    test('counts distinct series when the page holds every record', () {
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
          {'seriesId': 1},
          {
            'series': {'id': 7},
          },
        ],
        total: 3,
      );

      expect(sonarrSeriesSpread(page), 2);
    });

    test('is null when the server did not say how many there are', () {
      final page = ArrRecordPage(
        records: [
          {'seriesId': 1},
        ],
        total: null,
      );

      expect(sonarrSeriesSpread(page), isNull);
    });
  });

  group('recently downloaded', () {
    test('keeps imports, drops grabs, and shows one tile per series', () {
      // A season pack import writes one record per episode; a rail of eight
      // identical posters says less than one.
      final tiles = sonarrRecentlyDownloaded([
        _import(
          seriesId: 1,
          title: 'Severance',
          season: 2,
          episode: 4,
          at: now,
        ),
        _import(
          seriesId: 1,
          title: 'Severance',
          season: 2,
          episode: 3,
          at: now.subtract(const Duration(hours: 1)),
        ),
        {
          'eventType': 'grabbed',
          'seriesId': 2,
          'series': {'title': 'Andor'},
          'date': now.toIso8601String(),
        },
        _import(
          seriesId: 3,
          title: 'Silo',
          season: 3,
          episode: 1,
          at: now.subtract(const Duration(hours: 2)),
        ),
      ], now: now);

      expect(tiles.map((t) => t.seriesTitle), ['Severance', 'Silo']);
      // The newest record of the series is the one whose slot the caption shows.
      expect(tiles.first.slot, 'S2\u00A0E4');
      expect(tiles.first.caption, 'S2\u00A0E4\u00A0· just now');
    });

    test(
      'a record with no series id is dropped, because the tile is a link',
      () {
        final tiles = sonarrRecentlyDownloaded([
          {
            'eventType': 'downloadFolderImported',
            'series': {'title': 'Orphan'},
            'date': now.toIso8601String(),
          },
        ], now: now);

        expect(tiles, isEmpty);
      },
    );

    test('honours the limit, newest first', () {
      final tiles = sonarrRecentlyDownloaded(
        [
          for (var i = 1; i <= 10; i++)
            _import(
              seriesId: i,
              title: 'Series $i',
              season: 1,
              episode: 1,
              at: now.subtract(Duration(hours: i)),
            ),
        ],
        now: now,
        limit: 3,
      );

      expect(tiles.map((t) => t.seriesTitle), [
        'Series 1',
        'Series 2',
        'Series 3',
      ]);
    });
  });

  group('history today', () {});

  group('Needs attention, assembled', () {});

  group('the library the week is built from', () {});
}

// ─── Harness ────────────────────────────────────────────────────────────────

Map<String, dynamic> _import({
  required int seriesId,
  required String title,
  required int season,
  required int episode,
  required DateTime at,
}) => {
  'eventType': 'downloadFolderImported',
  'seriesId': seriesId,
  'series': {'title': title, 'id': seriesId, 'images': const []},
  'episode': {'seasonNumber': season, 'episodeNumber': episode},
  'date': at.toIso8601String(),
};
