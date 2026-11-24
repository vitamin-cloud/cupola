import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/arr_add_scaffold.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_bulk.dart';
import 'package:cupola/features/movies/presentation/movies_find.dart';
import 'package:cupola/features/movies/presentation/movies_search_provider.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_lookup_memory.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';

/// The movie ids Radarr reports under `wanted/cutoff`.
///
/// Screen-local because the chip is the only thing that reads it: the Overview's
/// `radarrCutoffUnmetCountProvider` wants a count, this wants a membership test,
/// and folding one into the other would make a library chip re-fetch every time
/// a KPI refreshed.
///
/// The honest limit: `getAllCutoff()` answers `[]` on its own failures rather
/// than throwing, because the endpoint is missing on some *arr builds. So an
/// empty set here means "Radarr had nothing to say", not strictly "nothing is
/// below cutoff". A Radarr that is not answering at all never reaches this
/// chip: the library provider fails first and the wall goes under a fault
/// band, so the residue is a reachable Radarr with a dead cutoff route, which
/// reads as an empty chip rather than a wrong number.
final radarrCutoffUnmetIdsProvider = FutureProvider.autoDispose<Set<int>>((
  ref,
) async {
  final records = await ref.watch(radarrServiceProvider).getAllCutoff();
  return {
    for (final record in records.whereType<Map>())
      if (record['id'] case final int id) id,
  };
});

/// A movie's state on the wall: the word its badge says it in, over the queue,
/// so a title has one word on the wall and in the find.
MediaStatusInfo? Function(RadarrMovie movie) _statusOf(
  ArrQueueSnapshot queue,
) =>
    (movie) => badgeOverQueue(
      radarrMovieStatus(
        movie,
        queueEntry: queue.entryFor(movie.id),
        queueUnknown: !queue.isWhole,
      ),
      queue,
    );

/// Opens [movie] the way the wall does: its own page under this tab, or
/// through its TMDB id on the title page, on the lens's copy.
void _openMovie(
  BuildContext context,
  WidgetRef ref,
  String lens,
  RadarrMovie movie,
  String heroTag,
) {
  if (movie.tmdbId <= 0) {
    context.push(ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag));
    return;
  }
  // What the lookup knew of it, for a title nothing else knows yet.
  if (movie.id <= 0) rememberLookup(ref, MediaKey.movie(movie.tmdbId), movie);
  context.openMedia(
    MediaKey.movie(movie.tmdbId),
    focus: lens.isEmpty ? null : lens,
    heroTag: heroTag,
    posterUrl: remotePosterOf(movie.images),
  );
}

/// This fork's page for adding a film: Radarr's lookup alone.
class MoviesAddScreen extends ConsumerWidget {
  const MoviesAddScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = queueSnapshotOf(ref.watch(radarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
    final status = _statusOf(queue);
    return ArrAddScaffold(
      service: ServiceKey.radarr,
      title: 'Add a movie',
      hint: 'Search for a new movie',
      queryProvider: moviesSearchQueryProvider,
      initialQuery: initialQuery,
      results: (context, query) => MoviesFindRadarr(
        query: query,
        statusOf: status,
        onOpen: (context, movie, tag) =>
            _openMovie(context, ref, lens, movie, tag),
      ),
    );
  }
}

class MoviesScreen extends ConsumerWidget {
  final bool showAppBar;
  final double topPadding;

  const MoviesScreen({super.key, this.showAppBar = true, this.topPadding = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No badge until the queue answers, never an empty queue: a film with no
    // file reads `Missing` only once a queue read whole has no entry for it,
    // and `Unknown` only once the read failed (`badgeOverQueue`).
    final queue = queueSnapshotOf(ref.watch(radarrQueueSnapshotProvider));
    final lens = ref.watch(activeInstanceProvider(ServiceKey.radarr))?.id ?? '';
    // Which of its addresses the lens's connection is reached at: the
    // posters go where the library is read from.
    final route = ref.watch(connectionRouteProvider(lens));
    final status = _statusOf(queue);
    // The connection the grid shows, which is the lens's, never the first
    // one's: the posters are built off this address and key, so a 4K grid
    // keyed on the first Radarr drew its movies' artwork from the other
    // server, under that server's ids. Editing the lens's connection re-keys
    // the grid, and editing another does not.

    // The film's own page, under this tab, opened on this Radarr's copy. The
    // wall's tile, the library's find and Radarr's all open it this way.
    void open(BuildContext context, RadarrMovie movie, String heroTag) {
      if (movie.tmdbId <= 0) {
        context.push(ServiceRoutes.radarrMovie(movie.id, heroTag: heroTag));
        return;
      }
      context.openMedia(
        MediaKey.movie(movie.tmdbId),
        focus: lens.isEmpty ? null : lens,
        heroTag: heroTag,
        posterUrl: remotePosterOf(movie.images),
      );
    }

    // The connection as a sentence says it: the bar's toasts and the
    // confirmation name it.
    final connectionName = ref.watch(
      currentSettingsProvider.select(
        (s) => s.connectionTitle(lens, ServiceKey.radarr),
      ),
    );

    return MediaBrowseScaffold<RadarrMovie>(
      title: 'Movies',
      searchHint: 'Movies',
      activityRoute: '${ServiceRoutes.radarr}/queue',
      navigationSection: NavigationSection.stack,
      serviceName: 'Radarr',
      service: ServiceKey.radarr,
      accentColor: ServiceKey.radarr.accent,
      heroTagPrefix: 'movie',
      libraryProvider: moviesProvider,
      searchQueryProvider: moviesSearchQueryProvider,
      // Only what the library holds: adding a film is its own page, the
      // band's magnifying glass, which the "ask Radarr" row opens too.
      find: MediaFind.libraryOnly(
        libraryBody: (context, query) => MoviesFindLibrary(
          query: query,
          statusOf: status,
          settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
          onOpen: open,
          onAskRadarr: () => context.push(ServiceRoutes.radarrAddFor(query)),
        ),
      ),
      // Search, Monitor, Profile and Remove on the movies selected.
      bulk: radarrBulk(
        ref: ref,
        instanceId: lens,
        name: connectionName,
        onChanged: (ref) {
          // What an action changed: the library, and what is read from it.
          ref.invalidate(moviesProvider);
          ref.invalidate(moviesForProvider);
          ref.invalidate(radarrCutoffUnmetIdsProvider);
          ref.invalidate(radarrKpiLibraryProvider);
        },
      ),
      titleExtractor: (movie) => movie.title,
      subtitleExtractor: (movie) => movie.year > 0 ? '${movie.year}' : '',
      sortTitleExtractor: (movie) => movie.sortTitle,
      imagesExtractor: (movie) => movie.images,
      idExtractor: (movie) => movie.id,
      statusExtractor: status,
      onRefresh: (ref) {
        // The family behind the snapshot, not the lens wrapper alone: that
        // one only resolves the lens and re-watches its family member, which
        // keeps the answer it already had, so a pull redrew every badge over
        // the queue from before it.
        ref.invalidate(radarrQueueSnapshotForProvider);
        // The rail above this grid reads its own non-swallowing copy of the
        // library, so that a dark Radarr prints "—" and not "Movies 0". The
        // scaffold invalidates `libraryProvider` for the grid; without this
        // line the pull refreshed the posters and left the figures frozen.
        ref.invalidate(radarrKpiLibraryProvider);
      },
      settingsSelector: (settings) => settings.artworkKeyOf(lens, route),
      onItemTap: open,
      showAppBar: showAppBar,
      topPadding: topPadding,
      sorts: [
        MediaBrowseSort<RadarrMovie>.dateAdded((movie) => movie.added),
        MediaBrowseSort<RadarrMovie>.year((movie) => movie.year),
        MediaBrowseSort<RadarrMovie>.size((movie) => movie.sizeOnDisk),
      ],
      // Null until the answer lands, so the chip appears with its set rather
      // than appearing first and filtering to nothing while the fetch is out.
      cutoffUnmetIds: ref
          .watch(radarrCutoffUnmetIdsProvider)
          .maybeWhen(data: (ids) => ids, orElse: () => null),
      kpiPeek: ServiceKpiPeek(
        kpis: ref.watch(serviceKpiProvider(ServiceKey.radarr)),
        service: ServiceKey.radarr,
      ),
    );
  }
}
