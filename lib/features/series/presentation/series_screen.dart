import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/arr_add_scaffold.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_lookup_memory.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_status.dart';
import 'package:cupola/features/series/presentation/series_bulk.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/series/presentation/series_find.dart';
import 'package:cupola/features/series/presentation/series_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The series ids Sonarr reports under `wanted/cutoff`.
///
/// Sonarr answers that route with *episodes*, not series, so the fold is over
/// `seriesId` and a series with nine episodes below cutoff is one id, which is
/// exactly what a library chip over series needs, and is why this cannot be the
/// same provider Radarr uses.
///
/// `getAllCutoff()` answers `[]` on its own failures rather than throwing (the
/// route is absent on some builds), so an empty set is "Sonarr had nothing to
/// say" as much as "nothing is below cutoff". A Sonarr that is not answering at
/// all never gets here: the library provider fails first.
///
/// Only the ids are read, so the walk asks for neither embed: with the series
/// and the episode file inside every episode, each page was the whole show
/// repeated per row, fifty times over on a long backlog.
final sonarrCutoffUnmetSeriesIdsProvider = FutureProvider.autoDispose<Set<int>>(
  (ref) async {
    final records = await ref
        .watch(sonarrServiceProvider)
        .getAllCutoff(
          queryParameters: const {
            'includeSeries': false,
            'includeEpisodeFile': false,
          },
        );
    return {
      for (final record in records.whereType<Map>())
        if (record['seriesId'] case final int id) id,
    };
  },
);

/// A series' state on the wall: the word its badge says it in, over the
/// queue, so a title has one word on the wall and in the find.
MediaStatusInfo? Function(SonarrSeries series) _statusOf(
  ArrQueueSnapshot queue,
) =>
    (series) => badgeOverQueue(
      sonarrSeriesStatus(
        series,
        queueEntry: queue.entryFor(series.id),
        queueUnknown: !queue.isWhole,
      ),
      queue,
    );

/// Opens [series] the way the wall does: its own page under this tab, or
/// through its TMDB id on the title page, on the lens's copy.
void _openSeries(
  BuildContext context,
  WidgetRef ref,
  String lens,
  SonarrSeries series,
  String heroTag,
) {
  if (series.tmdbId <= 0) {
    context.push(ServiceRoutes.sonarrSeries(series.id, heroTag: heroTag));
    return;
  }
  // What the lookup knew of it, for a title nothing else knows yet.
  if (series.id <= 0) rememberLookup(ref, MediaKey.tv(series.tmdbId), series);
  context.openMedia(
    MediaKey.tv(series.tmdbId),
    focus: lens.isEmpty ? null : lens,
    heroTag: heroTag,
    posterUrl: remotePosterOf(series.images),
  );
}

/// This fork's page for adding a series: Sonarr's lookup alone.
class SeriesAddScreen extends ConsumerWidget {
  const SeriesAddScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = queueSnapshotOf(ref.watch(sonarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
    final status = _statusOf(queue);
    return ArrAddScaffold(
      service: ServiceKey.sonarr,
      title: 'Add a series',
      hint: 'Search for a new series',
      queryProvider: seriesSearchQueryProvider,
      initialQuery: initialQuery,
      results: (context, query) => SeriesFindSonarr(
        query: query,
        statusOf: status,
        onOpen: (context, series, tag) =>
            _openSeries(context, ref, lens, series, tag),
      ),
    );
  }
}

class SeriesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const SeriesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers: see `movies_screen.dart`.
    final queue = queueSnapshotOf(ref.watch(sonarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.sonarr))?.id ?? '';
    // Which of its addresses the lens's connection is reached at: the
    // posters go where the library is read from.
    final route = ref.watch(connectionRouteProvider(lens));
    final status = _statusOf(queue);

    // The series' own page, under this tab, opened on this Sonarr's copy;
    // with no TMDB id, the way through its id here, where a Seerr can name
    // TMDB's from TVDB's. The wall's tile, the library's find and Sonarr's
    // all open it this way.
    void open(BuildContext context, SonarrSeries series, String heroTag) {
      if (series.tmdbId <= 0) {
        context.push(ServiceRoutes.sonarrSeries(series.id, heroTag: heroTag));
        return;
      }
      context.openMedia(
        MediaKey.tv(series.tmdbId),
        focus: lens.isEmpty ? null : lens,
        heroTag: heroTag,
        posterUrl: remotePosterOf(series.images),
      );
    }

    // The connection as a sentence says it: the bar's toasts and the
    // confirmation name it.
    final connectionName = ref.watch(
      currentSettingsProvider.select(
        (s) => s.connectionTitle(lens, ServiceKey.sonarr),
      ),
    );

    return MediaBrowseScaffold<SonarrSeries>(
      title: 'TV series',
      searchHint: 'Series',
      activityRoute: '${ServiceRoutes.sonarr}/queue',
      navigationSection: NavigationSection.stack,
      serviceName: 'Sonarr',
      service: ServiceKey.sonarr,
      posterFallbackIcon: Icons.tv_outlined,
      accentColor: ServiceKey.sonarr.accent,
      heroTagPrefix: 'series',
      libraryProvider: seriesProvider,
      searchQueryProvider: seriesSearchQueryProvider,
      // Only what the library holds: adding a series is its own page, the
      // band's magnifying glass, which the "ask Sonarr" row opens too.
      find: MediaFind.libraryOnly(
        libraryBody: (context, query) => SeriesFindLibrary(
          query: query,
          statusOf: status,
          settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
          onOpen: open,
          onAskSonarr: () => context.push(ServiceRoutes.sonarrAddFor(query)),
        ),
      ),
      // Search, Monitor, Profile and Remove on the series selected.
      bulk: sonarrBulk(
        ref: ref,
        instanceId: lens,
        name: connectionName,
        onChanged: (ref) {
          ref.invalidate(seriesProvider);
          ref.invalidate(seriesForProvider);
          ref.invalidate(sonarrCutoffUnmetSeriesIdsProvider);
          ref.invalidate(sonarrKpiLibraryProvider);
        },
      ),
      titleExtractor: (series) => series.title,
      subtitleExtractor: (series) => series.year > 0 ? '${series.year}' : '',
      sortTitleExtractor: (series) => series.sortTitle,
      imagesExtractor: (series) => series.images,
      idExtractor: (series) => series.id,
      statusExtractor: status,
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper: see
        // `movies_screen.dart`. The read itself, which the series index is a
        // view of.
        ref.invalidate(sonarrQueueSnapshotsForProvider);
        // The rail's own non-swallowing read. See `movies_screen.dart`.
        ref.invalidate(sonarrKpiLibraryProvider);
      },
      // The lens's connection, never the first one's: see `movies_screen.dart`.
      settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
      onItemTap: open,
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<SonarrSeries>.dateAdded((series) => series.added),
        MediaBrowseSort<SonarrSeries>.year((series) => series.year),
        MediaBrowseSort<SonarrSeries>.size(
          // `statistics` is absent on a freshly added series, which is a zero
          // on disk and not an unknown: the series genuinely has no files yet.
          (series) => switch (series.statistics?['sizeOnDisk']) {
            final int bytes => bytes,
            final num bytes => bytes.toInt(),
            _ => 0,
          },
        ),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(sonarrCutoffUnmetSeriesIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.sonarr)),
        service: ServiceKey.sonarr,
      ),
    );
  }
}
