import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/torrent_list_order.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/domain/models/dashboard.dart';

/// A download client's Queue tab rail: [serviceKpiProvider] as read, with its
/// rates `—` while the page's stale band is up ([withRatesNotUpdating]).
///
/// Not `whenData`: a stale page's rail is reloading behind a read that does
/// not come back, and `whenData` drops a reload's previous figures, which
/// put the rail back to its skeleton.
AsyncValue<List<ServiceKpi>> queueRailOf(
  AsyncValue<List<ServiceKpi>> kpis, {
  required bool stale,
}) => stale && kpis.hasValue && !kpis.hasError
    ? AsyncData(withRatesNotUpdating(kpis.requireValue))
    : kpis;

/// KPIs shown in the [ServiceKpiPeek] at the top of each service page.
///
/// Derives metrics from the same sources the pages load, so the figures agree
/// with the lists. A page that already watches a live stream derives its rail
/// from that watch (Dockge does); this provider then serves the dashboard
/// card's snapshot.
final serviceKpiProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>, ServiceKey>((ref, service) async {
      switch (service) {
        case ServiceKey.radarr:
          return _radarrKpis(ref);
        case ServiceKey.sonarr:
          return _sonarrKpis(ref);
        case ServiceKey.qbittorrent:
          return _qbittorrentKpis(ref);
        case ServiceKey.seerr:
          return _seerrKpis(ref);
        case ServiceKey.truenas:
          return _truenasKpis(ref);
        case ServiceKey.dockge:
          return _dockgeKpis(ref);
        case ServiceKey.jellyfin:
          final container = ref.container;
          final providers = mediaBrowserProvidersOf(service);
          return _mediaBrowserKpis(
            ref.watch(providers.sessions.future),
            ref.watch(providers.strictLibraries.future),
            kind: () => container.read(providers.credentialKind.future),
          );
      }
    }, retry: noProviderRetry);

/// Every provider [serviceKpiProvider] reads for [service]: the sources, not
/// the folds.
///
/// A pull that invalidates only [serviceKpiProvider] re-folds the same cached
/// answers: most of these are plain `FutureProvider`s that live as long as the
/// app, so the Dashboard's refresh redrew thirteen stack cards from figures it
/// never re-asked for, and a source that had failed stayed failed however many
/// times it was pulled. Kept beside the switch above and exhaustive over
/// [ServiceKey], so a service added there cannot be missing here.
///
/// The per-connection readers behind [serviceKpiForProvider] ask their client
/// directly, except the arrs' libraries, which are read once a session per
/// connection ([moviesForProvider] and its siblings) and listed here with the
/// lens's.
List<ProviderOrFamily> serviceKpiSources(ServiceKey service) =>
    switch (service) {
      // The family behind the snapshot, not the lens wrapper alone: that one
      // only resolves the lens and re-watches its family member, which keeps
      // the answer it already had.
      ServiceKey.radarr => [
        radarrKpiLibraryProvider,
        moviesForProvider,
        radarrQueueSnapshotProvider,
        radarrQueueSnapshotForProvider,
      ],
      ServiceKey.sonarr => [sonarrKpiLibraryProvider, seriesForProvider],
      ServiceKey.qbittorrent => [allTorrentsProvider],
      ServiceKey.seerr => [requestRowsProvider, issueCountProvider],
      ServiceKey.truenas => [truenasDashboardProvider],
      ServiceKey.dockge => [dockgeStackListProvider],
      ServiceKey.jellyfin => [
        jellyfinSessionsProvider,
        jellyfinStrictLibrariesProvider,
      ],
    };

/// The [serviceKpiSources] that download a whole library: the arrs' `GET /movie`,
/// `/series`, `/artist`, `/album` and `/author`, the heaviest answers the app
/// asks for, behind figures that change a few times a day.
///
/// A silent return to Stack skips these until they are old enough to be worth
/// the download; a pull or a re-tap reads them like everything else.
List<ProviderOrFamily> serviceKpiLibrarySources(ServiceKey service) =>
    switch (service) {
      ServiceKey.radarr => [radarrKpiLibraryProvider, moviesForProvider],
      ServiceKey.sonarr => [sonarrKpiLibraryProvider, seriesForProvider],
      _ => const [],
    };

/// What a service page's pull-to-refresh has to re-ask: its reachability probe
/// and every source its KPI rail reads.
///
/// [serviceSummaryProvider] only delegates to [instanceSummaryProvider], which
/// is not `autoDispose`; invalidating the wrapper alone redrew the identity
/// band from the probe already in the cache, so a pull never asked the server
/// whether it was up. And [serviceKpiProvider] folds sources that live as long
/// as the app: see [serviceKpiSources].
void invalidateServiceReadout(WidgetRef ref, ServiceKey service) {
  ref.invalidate(serviceSummaryProvider(service));
  for (final instance
      in ref.read(currentSettingsProvider).configuredInstancesOf(service)) {
    ref.invalidate(
      instanceSummaryProvider((service: service, instanceId: instance.id)),
    );
  }
  ref.invalidate(serviceKpiProvider(service));
  for (final source in serviceKpiSources(service)) {
    ref.invalidate(source);
  }
}

/// The same KPIs, for one **named connection** rather than for the lens.
///
/// The Dashboard's stack card needs this: a service with two connections draws
/// `×2` and the fleet's figures, and there is no fleet figure to compute while
/// the only thing the app can ask is "what does the lens say". Keyed on
/// [InstanceRef] and not on a bare id, for the reason that record already
/// carries, a probe for a connection that has since been removed still has to
/// know what kind of thing it was.
///
/// The lens's own id collapses back onto [serviceKpiProvider] rather than
/// fetching the same server twice, which is the same collapse
/// `requestsForProvider` and the `*ServiceFor` families make, and what keeps an
/// override of the plain provider from being bypassed in tests.
///
/// **Null means this connection cannot be read on its own yet**, which is not
/// the same as having no figures. Every currently registered service has a
/// keyed reader; keeping the nullable result makes the contract explicit for
/// a future service whose KPI set cannot be addressed per connection. A fold
/// that guessed would print the lens's rate as the fleet's, which is the bug
/// this provider exists to end.
final serviceKpiForProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, InstanceRef>((ref, key) async {
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(serviceKpiProvider(key.service).future);
      }
      return switch (key.service) {
        ServiceKey.radarr => await _radarrKpisFor(ref, key.instanceId),
        ServiceKey.sonarr => await _sonarrKpisFor(ref, key.instanceId),
        ServiceKey.seerr => await _seerrKpisFor(ref, key.instanceId),
        ServiceKey.qbittorrent => await _qbittorrentKpisFor(
          ref,
          key.instanceId,
        ),
        ServiceKey.truenas => await _truenasKpisFor(ref, key.instanceId),
        ServiceKey.dockge => await _dockgeKpisFor(ref, key.instanceId),
        ServiceKey.jellyfin => await _mediaBrowserKpisFor(
          ref,
          key.service,
          key.instanceId,
        ),
      };
      // `noProviderRetry`, like the provider above it. The lens path awaits
      // `serviceKpiProvider(...).future`, which settles into a stable error
      // and stops; retrying *here* re-ran it behind an exponential backoff and
      // put the whole storm back one level up, with pending timers that
      // outlive a widget test.
    }, retry: noProviderRetry);

/// The whole service's figures, folded across every connection it has.
///
/// Null when there is no aggregate to show, and the three reasons are all the
/// same refusal:
///
///  * **a connection is dark.** Gated on `offline == 0` before anything is
///    fetched: the fold is never partial, because a sum missing a term looks
///    exactly like a sum.
///  * **a connection cannot be read per connection**: see
///    [serviceKpiForProvider].
///  * **the figures do not fold**: see [aggregateServiceKpis], which is where
///    the arithmetic and, more importantly, the refusals live.
///
/// A single-connection service folds to itself, so the card does not have to
/// know whether it is looking at one server or six.
final foldedServiceKpisProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      final connections = settings.configuredInstancesOf(service);
      if (connections.isEmpty) return null;

      // Lens first. `aggregateServiceKpis` falls back to the head of this list
      // for every figure whose unit cannot be added: a percentage, a ratio, a
      // state word, and the lens is the connection the rest of the app is
      // already pointed at, so it is the only defensible one to keep.
      final lens = ref.watch(activeInstanceProvider(service))?.id;
      final ordered = [
        for (final connection in connections)
          if (connection.id == lens) connection,
        for (final connection in connections)
          if (connection.id != lens) connection,
      ];

      // Reachability first, and **awaited**. Reading the synchronous fold
      // instead was the bug this line replaces: on a cold open every probe is
      // still in flight, so `offline` is zero, the gate opens, and the fold
      // publishes a sum over however many servers happened to have answered.
      // The figure has to wait for every connection to have said something,
      // because that is the whole claim it makes.
      final answers = await Future.wait([
        for (final connection in ordered)
          _connectionAnswers(ref, (
            service: service,
            instanceId: connection.id,
          )),
      ]);
      if (answers.contains(false)) return null;

      final perConnection = await Future.wait([
        for (final connection in ordered)
          ref.watch(
            serviceKpiForProvider((
              service: service,
              instanceId: connection.id,
            )).future,
          ),
      ]);
      return aggregateServiceKpis(
        service == ServiceKey.seerr
            ? withCommonOpenProblems(perConnection)
            : perConnection,
      );
      // Derived from [serviceKpiForProvider], so it carries the flag for the
      // reason that one does.
    }, retry: noProviderRetry);

/// The `Open problems` readout of Seerr is there only for an account that may
/// view issues, so two Seerr connections can disagree about holding it. A fleet
/// figure needs every connection's term (the fold refuses lists that differ),
/// so it is kept only where every connection reports it.
@visibleForTesting
List<List<ServiceKpi>?> withCommonOpenProblems(
  List<List<ServiceKpi>?> perConnection,
) {
  const label = 'Open problems';
  bool has(List<ServiceKpi>? kpis) =>
      kpis != null && kpis.any((kpi) => kpi.label == label);
  if (perConnection.every(has) || !perConnection.any(has)) {
    return perConnection;
  }
  return [
    for (final kpis in perConnection)
      kpis == null
          ? null
          : [
              for (final kpi in kpis)
                if (kpi.label != label) kpi,
            ],
  ];
}

/// Whether one connection answered, with a probe that threw counted as a no.
///
/// `instanceSummaryProvider` normally reports an unreachable server as an
/// offline summary rather than by throwing, but the fold must not be the place
/// that finds out otherwise: an error escaping here would take the card into
/// `AsyncError` and lose the reading for every connection that *was* fine.
Future<bool> _connectionAnswers(Ref ref, InstanceRef key) async {
  try {
    return (await ref.watch(instanceSummaryProvider(key).future)).isOnline;
  } catch (_) {
    return false;
  }
}

/// The single live figure a service contributes to the stack matrix on
/// `/services`.
///
int _statInt(Map<String, dynamic>? stats, String key) =>
    (stats?[key] as num?)?.toInt() ?? 0;

/// Flags a metric as a **fault**: something that was meant to be working and
/// is not, and the only one of the three that earns amber.
StatusTone? _faultIf(bool condition) => condition ? StatusTone.warning : null;

/// Flags a metric as **backlog**: work that has not happened yet.
///
/// Noteworthy, because a pile of missing films is why you opened the service;
/// untoned, because it is the resting state of a media manager and not a
/// problem with one. This is the distinction the old single `_warnIf` could not
/// express, and the reason every \*arr shipped with its baseline painted in the
/// alarm colour.
StatusTone? _backlogIf(bool condition) => condition ? StatusTone.neutral : null;

/// Flags a metric as **activity** rather than as a problem: bytes are moving,
/// or somebody is watching, because the stack is doing its job.
StatusTone? _activityIf(bool condition) => condition ? StatusTone.info : null;

/// One figure, or the em dash that stands in for it.
///
/// A null [value] means *nobody answered*, which is the case every \*arr
/// builder below used to print as `0`. Routing both readings of a card through
/// one call is what keeps the label and the icon written once: the rail shows
/// the same four cards whether the server replied or not, so a reader can see
/// *which* figure is missing rather than watching the strip change shape.
ServiceKpi _figure({
  required String label,
  required IconData icon,
  required String? value,
  StatusTone? tone,
  String? note,
  Set<Object>? members,
}) => value == null
    ? ServiceKpi.unavailable(label: label, icon: icon, note: note)
    : ServiceKpi(
        label: label,
        value: value,
        icon: icon,
        tone: tone,
        members: members,
      );

/// The identity a title is counted by across connections: [key] when the
/// service gave one, else the title itself, which merges with nothing.
Object _titleKey(Object title, Object? key) =>
    key == null || key == 0 || key == '' ? title : key;

/// What an unanswered figure says instead of a number.
///
/// Carried by the **first** card only. The note replaces the label on the card
/// that holds it (the rail is two lines tall by construction), so putting it on
/// all four would leave a strip of four identical reasons and no way to tell
/// which absence is which.
///
/// In the classified words, never a guess: "Radarr not answering" was printed
/// for a refused key too, under a header that had just said Answering. A read
/// that failed without saying why is `Did not complete`, not silence.
String _notAnswering(ServiceKey service, Object? error) =>
    '${service.title}\u00A0· '
    '${failureLabel(classifyConnectionFailure(error), credential: refusedCredentialOf(service), gateway: accessGatewayOf(error))}';

/// The shared KPI set for a media server, identical for Jellyfin, Emby and Plex.
///
/// Three metrics, and the order is load-bearing in two ways that
/// `resolveServiceSignalPair` depends on.
///
/// **`Streams` is first, so it is the resting fallback.** With nothing flagged
/// the matrix cell shows `kpis.first`, and `0 streams` is both true and live:
/// unlike a library total, which DESIGN.md rightly calls the least live thing you
/// could put on a control-room screen.
///
/// **`Streams` is only flagged while nothing is transcoding.** The cell shows the
/// *first* flagged KPI, so gating it this way lets the more urgent fact win
/// without teaching the resolver about precedence: idle reads `0 streams` in
/// neutral, a healthy stream reads `2 streaming` in info blue, and the moment the
/// box starts re-encoding it reads `1 transcode` in warning amber. One rule, three
/// correct readings, no special-casing in the shared resolver.
///
/// **There is no aggregate bitrate metric, deliberately.** Neither server reports
/// measured outbound throughput: Jellyfin only carries a bitrate while
/// transcoding, and Plex's `Session.bandwidth` is a reservation. Summing those
/// would add two different units together and present the result as the box's
/// egress: a fabricated number. Per-session bitrate is shown on the board, where
/// `StreamSession.bitrateIsNominal` can say what it actually is.
///
/// **A null future is a read this token may not make**, and its figures read
/// `—` with [sessionsNote] or [librariesNote] saying why: a shared account's
/// Plex token is refused who is watching, a household member's Jellyfin token
/// the library list. Both are configuration, not faults, so the rest of the
/// rail still says what the token could read.
///
/// [sessionsNote] on sessions that did answer says whose they are: a
/// household member's Jellyfin token sees only its own playback, and a count
/// of it must not read as the server's.
Future<List<ServiceKpi>> _streamKpis(
  Future<List<StreamSession>>? sessionsFuture,
  Future<List<StreamLibrary>>? librariesFuture, {
  String? sessionsNote,
  String? librariesNote,
}) async {
  // Both reads are started by the caller so the rail does not wait for one
  // endpoint before asking the other. `Future.wait` is important here rather
  // than two sequential awaits: when an unreachable server rejects both
  // requests, it observes both failures while still propagating the first one
  // to `serviceKpiProvider`.
  final results = await Future.wait<Object?>([
    sessionsFuture ?? Future<Object?>.value(),
    librariesFuture ?? Future<Object?>.value(),
  ]);
  final sessions = results[0] as List<StreamSession>?;
  final libraries = results[1] as List<StreamLibrary>?;
  final transcodes = sessions?.where((s) => s.playMethod.isTranscode).length;

  return [
    sessions == null
        ? ServiceKpi.unavailable(
            label: 'Streams',
            icon: Icons.play_circle_outline_rounded,
            note: sessionsNote,
          )
        : ServiceKpi(
            label: 'Streams',
            value: '${sessions.length}',
            icon: Icons.play_circle_outline_rounded,
            tone: _activityIf(sessions.isNotEmpty && transcodes == 0),
            note: sessionsNote,
          ),
    _figure(
      label: 'Transcodes',
      value: transcodes == null ? null : '$transcodes',
      icon: Icons.memory_rounded,
      tone: transcodes == null ? null : _faultIf(transcodes > 0),
      // The reason rides on the first card of the two it empties, as every
      // unanswered rail carries it: two identical notes side by side would
      // hide which figure each one stands in for.
    ),
    _figure(
      label: 'Libraries',
      value: libraries == null ? null : '${libraries.length}',
      icon: Icons.video_library_outlined,
      note: librariesNote,
    ),
  ];
}

/// What a figure out of a household member's Jellyfin token's reach says.
const _adminOnlyNote = 'admin only';

/// What a count of only a household member's own playback says.
const _yoursOnlyNote = 'yours only';

/// What a failed read failed with, or null when it answered.
Future<Object?> _failureOf(Future<Object?> read) =>
    read.then<Object?>((_) => null, onError: (Object error) => error);

/// The figures of a MediaBrowser server, Jellyfin or Emby.
///
/// A library list refused to a household member's token, which [kind] says
/// it is, reads `—`; its own playback still counts, and says it is its own,
/// as its Now playing does.
/// Any other failure takes the rail, as before.
Future<List<ServiceKpi>> _mediaBrowserKpis(
  Future<List<StreamSession>> sessions,
  Future<List<StreamLibrary>> libraries, {
  required Future<JellyfinCredentialKind> Function() kind,
}) async {
  try {
    return await _streamKpis(sessions, libraries);
  } catch (_) {
    if (await _failureOf(libraries) == null ||
        await _failureOf(sessions) != null) {
      rethrow;
    }
    bool member;
    try {
      member = (await kind()).lacksAdministrator;
    } catch (_) {
      member = false;
    }
    if (!member) rethrow;
    return _streamKpis(
      sessions,
      null,
      sessionsNote: _yoursOnlyNote,
      librariesNote: _adminOnlyNote,
    );
  }
}

Future<List<ServiceKpi>> _mediaBrowserKpisFor(
  Ref ref,
  ServiceKey service,
  String instanceId,
) {
  final providers = mediaBrowserProvidersOf(service);
  final client = ref.watch(providers.client.forConnection(instanceId));
  final container = ref.container;
  return _mediaBrowserKpis(
    ref.watch(
      streamSessionsForProvider((
        service: service,
        instanceId: instanceId,
      )).future,
    ),
    client.getLibrariesOrThrow(),
    kind: () => container.read(providers.credentialKindFor(instanceId).future),
  );
}

/// The Radarr library, read so that a failure survives the fetch.
///
/// Written when [moviesProvider] still went through `fetchAllItems`, which
/// swallows every failure into `[]`: an unreachable Radarr resolved it
/// *successfully* and the rail printed `Movies 0 · Monitored 0 · Missing 0`
/// under an identity band whose own probe already read Unreachable. The wall
/// now reads `getMoviesOrThrow` too, with the same retry policy, so the two are
/// the same request made twice, kept apart so this rail's invalidation stays
/// its own. See `getMoviesOrThrow`.
///
/// Plain, not `autoDispose`, matching `moviesProvider` beside it: the library
/// is a session-scoped read, and `serviceKpiProvider` *is* `autoDispose`: a
/// disposing source under it would turn one `GET /movie` per session into one
/// per visit to the Dashboard and to every Radarr tab. Pull-to-refresh
/// invalidates it explicitly.
///
/// **`retry: noProviderRetry` is load-bearing**, not hygiene. Riverpod's
/// default retry re-runs a throwing build ten times with backoff, and a
/// `DioException` is an `Exception`, so it engages on every network failure:
/// which means `await ref.watch(...future)` inside the `catch` below does not
/// settle for some forty seconds. The `catch` exists precisely to report that
/// the server did not answer, so holding it until the retries run out is the
/// rail sitting in its skeleton state instead of saying so. Measured: the four
/// tests for this timed out at thirty seconds each before the policy went on.
/// See `lib/core/providers/provider_retry.dart`.
///
/// **[moviesProvider] itself.** The wall, this rail, Home's card and the
/// Overview each made the same `GET /movie`, the heaviest answer the app asks
/// for, and the Home paid for it at every cold open on top of the screens that
/// followed. They share one read now; all of them already carried this
/// retry policy, so nothing about how a failure settles changed.
final radarrKpiLibraryProvider = moviesProvider;

/// The Sonarr library. See [radarrKpiLibraryProvider].
///
/// Its own rather than a share of `sonarrOverviewSeriesProvider`, which reads
/// the same endpoint the same way: that one carries the default retry, on
/// purpose, because the Overview watches it as an `AsyncValue` and wants the
/// blip to heal itself. This one is *awaited* in a `catch`, and the two
/// policies cannot both hold on one provider.
///
/// **[seriesProvider] itself**, as the Radarr rail is the wall's.
final sonarrKpiLibraryProvider = seriesProvider;

Future<List<ServiceKpi>> _radarrKpis(Ref ref) async {
  // The queue starts with the library, not after it: the snapshot never throws,
  // so a library that fails leaves nothing unhandled.
  final queue = ref.watch(radarrQueueSnapshotProvider.future);
  final List<RadarrMovie> movies;
  try {
    movies = await ref.watch(radarrKpiLibraryProvider.future);
  } catch (error) {
    // The queue figure goes too: it comes off the same server, and once the
    // library has told us the server is dark the queue has nothing to add but
    // a second note saying so.
    return _radarrKpisFrom(
      null,
      ArrQueueSnapshot.unknown,
      note: _notAnswering(ServiceKey.radarr, error),
    );
  }
  return _radarrKpisFrom(movies, await queue);
}

/// The same four figures for one **named** connection, whatever the lens is on.
///
/// Only ever called for a connection that is *not* the lens: see
/// [serviceKpiForProvider], which collapses the lens back onto the plain
/// builder so the card and the library screen keep reading one cache.
Future<List<ServiceKpi>> _radarrKpisFor(Ref ref, String instanceId) async {
  // The queue starts with the library (see [_radarrKpis]).
  final queue = ref.watch(radarrQueueSnapshotForProvider(instanceId).future);
  final List<RadarrMovie> movies;
  try {
    // The connection's one library read, cached for the session like the
    // lens's: the fold is `autoDispose` and runs again each time Home is
    // rebuilt, and read off the service it downloaded the library each time.
    movies = await ref.watch(moviesForProvider(instanceId).future);
  } catch (error) {
    return _radarrKpisFrom(
      null,
      ArrQueueSnapshot.unknown,
      note: _notAnswering(ServiceKey.radarr, error),
    );
  }
  return _radarrKpisFrom(movies, await queue);
}

/// Null means the server did not answer: see [_figure]. Never `[]`, which is
/// an answer: it says the library is there and empty.
///
/// The queue figure is the films in [queue], and only as much of a figure as
/// the snapshot can stand behind: an em dash with its own reason when the
/// queue did not answer (a library that reads fine over a queue endpoint that
/// does not used to print `Queue 0`), and a floor (`200+`) when the walk
/// stopped on a full page with no total.
List<ServiceKpi> _radarrKpisFrom(
  List<RadarrMovie>? movies,
  ArrQueueSnapshot queue, {
  String? note,
}) {
  final queued = queue.entriesById.length;
  final monitored = movies?.where((m) => m.monitored).length;
  final missing = movies?.where((m) => m.monitored && !m.hasFile).length;
  // Films by TMDB id, so a fold across an HD and a 4K Radarr counts a film
  // both hold once. Missing stays a count of files to fetch, which sums.
  Set<Object>? films(bool Function(RadarrMovie movie) where) => movies == null
      ? null
      : {
          for (final movie in movies)
            if (where(movie)) _titleKey(movie, movie.tmdbId),
        };
  return [
    _figure(
      label: 'Movies',
      value: movies == null ? null : '${movies.length}',
      icon: Icons.movie_rounded,
      note: note,
      members: films((_) => true),
    ),
    _figure(
      label: 'Monitored',
      value: monitored == null ? null : '$monitored',
      icon: Icons.visibility_rounded,
      members: films((movie) => movie.monitored),
    ),
    _figure(
      label: 'Missing',
      value: missing == null ? null : '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(missing != null && missing > 0),
    ),
    _figure(
      label: 'Queue',
      value: !queue.answered
          ? null
          : queue.cutShort
          ? Lexicon.floor(queued)
          : '$queued',
      icon: Icons.download_rounded,
      // The library's note already says why when the whole server is dark.
      note: queue.answered || movies == null
          ? null
          : _queueNote(ServiceKey.radarr, queue.error),
    ),
  ];
}

/// Why a queue figure reads an em dash when the queue is its own fetch:
/// `Queue · Did not answer`.
String _queueNote(ServiceKey service, Object? error) =>
    'Queue\u00A0· ${failureLabel(classifyConnectionFailure(error), credential: refusedCredentialOf(service), gateway: accessGatewayOf(error))}';

Future<List<ServiceKpi>> _sonarrKpis(Ref ref) async {
  try {
    // [sonarrKpiLibraryProvider]: `seriesProvider` used to read `getSeries`,
    // which swallows its own failure into `[]`, and every figure below it was
    // a confident zero for a question nobody answered.
    return _sonarrKpisFrom(await ref.watch(sonarrKpiLibraryProvider.future));
  } catch (error) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr, error));
  }
}

/// See [_radarrKpisFor].
Future<List<ServiceKpi>> _sonarrKpisFor(Ref ref, String instanceId) async {
  try {
    return _sonarrKpisFrom(
      await ref.watch(seriesForProvider(instanceId).future),
    );
  } catch (error) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr, error));
  }
}

/// Null means the server did not answer. See [_radarrKpisFrom].
List<ServiceKpi> _sonarrKpisFrom(List<SonarrSeries>? series, {String? note}) {
  var epHave = 0;
  var epTotal = 0;
  var monitored = 0;
  for (final s in series ?? const <SonarrSeries>[]) {
    if (s.monitored) monitored++;
    epHave += _statInt(s.statistics, 'episodeFileCount');
    epTotal += _statInt(s.statistics, 'episodeCount');
  }
  final missing = (epTotal - epHave).clamp(0, epTotal);
  final answered = series != null;
  // Series by TVDB id, so two Sonarr holding one series count it once. The
  // missing episodes are files to fetch on each, and sum.
  Set<Object>? shows(bool Function(SonarrSeries show) where) => series == null
      ? null
      : {
          for (final show in series)
            if (where(show)) _titleKey(show, show.tvdbId),
        };
  return [
    _figure(
      label: 'Series',
      value: answered ? '${series.length}' : null,
      icon: Icons.tv_rounded,
      note: note,
      members: shows((_) => true),
    ),
    _figure(
      label: 'Episodes',
      value: answered ? '$epHave/$epTotal' : null,
      icon: Icons.playlist_play_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
    _figure(
      label: 'Monitored',
      value: answered ? '$monitored' : null,
      icon: Icons.visibility_rounded,
      members: shows((show) => show.monitored),
    ),
  ];
}

Future<List<ServiceKpi>> _qbittorrentKpis(Ref ref) async {
  final now = ref.read(stallClockProvider)();
  return _qbittorrentKpisFrom(
    await ref.watch(allTorrentsProvider.future),
    now: now,
  );
}

Future<List<ServiceKpi>> _qbittorrentKpisFor(Ref ref, String instanceId) async {
  final now = ref.read(stallClockProvider)();
  final data = await ref
      .watch(qbittorrentServiceForProvider(instanceId))
      .mainData();
  return _qbittorrentKpisFrom(
    sortTorrents(data.torrents, TorrentSort.addedOn, reverse: true),
    now: now,
  );
}

/// qBittorrent's rail. Its last figure counts the stuck torrents, by the one
/// rule a stuck download is judged by ([qbittorrentInFlight]: stalled or
/// failed), so the card is flagged when Needs you shows one.
List<ServiceKpi> _qbittorrentKpisFrom(
  List<Torrent> torrents, {
  required DateTime now,
}) {
  var active = 0;
  var downloading = 0;
  var seeding = 0;
  var stuck = 0;
  var dl = 0;
  var up = 0;
  for (final t in torrents) {
    final state = TorrentState.fromString(t.state);
    if (state.isActive) active++;
    if (state == TorrentState.downloading ||
        state == TorrentState.metaDownloading) {
      downloading++;
    }
    if (state == TorrentState.seeding) seeding++;
    if (qbittorrentInFlight(t, now: now)?.fault != null) stuck++;
    dl += t.dlSpeed;
    up += t.upSpeed;
  }
  return [
    ServiceKpi(label: 'Active', value: '$active', icon: Icons.bolt_rounded),
    // The brand book's pair, `↓ 22.4 MB/s ↑ 1.1 MB/s`: the arrow is the
    // card's glyph and the rate its figure, so the word under them names the
    // rate rather than repeating the arrow. It said `Down` and `Up`, and
    // `Down` is the one state word the lexicon bans outright.
    ServiceKpi(
      label: 'Download',
      value: formatSpeed(dl),
      icon: Icons.south_rounded,
      tone: _activityIf(dl > 0),
    ),
    ServiceKpi(
      label: 'Upload',
      value: formatSpeed(up),
      icon: Icons.north_rounded,
    ),
    ServiceKpi(label: 'Seeding', value: '$seeding', icon: Icons.upload_rounded),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: StateWord.stuck.label,
      value: '$stuck',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _faultIf(stuck > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _seerrKpis(Ref ref) async => _seerrKpisFrom(
  await ref.watch(requestRowsProvider.future),
  problems: await _seerrOpenProblems(ref, ''),
);

/// See [_radarrKpisFor]. Seerr already owned its per-connection read, because a
/// request id is per instance and a merged list cannot be acted on by id alone.
Future<List<ServiceKpi>> _seerrKpisFor(Ref ref, String instanceId) async =>
    _seerrKpisFrom(
      await ref.watch(requestRowsForProvider(instanceId).future),
      problems: await _seerrOpenProblems(ref, instanceId),
    );

/// What Seerr says about its open issues, as the readout needs it: not
/// [shown] for an account that may not view issues (nothing is asked and the
/// readout is absent, the Issues tab already says why), and a null [open] for
/// a count that did not answer, which reads `—`.
typedef OpenProblems = ({bool shown, int? open});

/// The open issues of connection [instanceId] (empty: the lens).
Future<OpenProblems> _seerrOpenProblems(Ref ref, String instanceId) async {
  final mayList = ref.watch(roleGateOfProvider(instanceId)).mayReviewIssues;
  if (!mayList) return (shown: false, open: null);
  try {
    return (
      shown: true,
      open: (await ref.watch(issueCountProvider(instanceId).future)).open,
    );
  } catch (_) {
    return (shown: true, open: null);
  }
}

List<ServiceKpi> _seerrKpisFrom(
  List<SeerrRequest> requests, {
  OpenProblems problems = (shown: false, open: null),
}) {
  var pending = 0;
  var processing = 0;
  var available = 0;
  for (final r in requests) {
    // Pending counts the requests that still need a decision, so it reads the
    // request's OWN status: the same source `request_ordering.dart` and the
    // /activity rows read, and for the same
    // documented reason. `displayStatus` answers a different question: it lets
    // the media's availability override the request, so a request still in
    // pendingApproval whose media Radarr already holds reports "Available":
    // which is how this KPI came to show "Pending 0" while /activity was
    // offering an Approve button for that very record.
    if (r.status == RequestStatus.pendingApproval) pending++;

    // The other two stay on displayStatus, which is the right source for them:
    // they describe where the media is, not what the request needs.
    switch (r.displayStatus.kind) {
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        processing++;
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        available++;
      case SeerrRequestDisplayKind.pending:
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.blocklisted:
      case SeerrRequestDisplayKind.deleted:
      case SeerrRequestDisplayKind.unknown:
        break;
    }
  }
  return [
    ServiceKpi(
      label: 'Requests',
      value: '${requests.length}',
      icon: Icons.inbox_rounded,
    ),
    ServiceKpi(
      label: StateWord.waitingForApproval.label,
      value: '$pending',
      icon: Icons.hourglass_top_rounded,
      tone: _backlogIf(pending > 0),
    ),
    ServiceKpi(
      label: 'Processing',
      value: '$processing',
      icon: Icons.sync_rounded,
    ),
    if (problems.shown)
      switch (problems.open) {
        // A count Seerr did not give is a dash, never nothing open.
        null => const ServiceKpi.unavailable(
          label: 'Open problems',
          icon: Icons.flag_outlined,
          overviewOnly: true,
        ),
        final open => ServiceKpi(
          label: 'Open problems',
          value: '$open',
          icon: Icons.flag_outlined,
          // A reported problem is a fault: something somebody relies on is
          // not working.
          tone: _faultIf(open > 0),
          // Seerr's Overview alone: it answering keeps its light green.
          overviewOnly: true,
        ),
      },
    ServiceKpi(
      label: 'Available',
      value: '$available',
      icon: Icons.check_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _truenasKpis(Ref ref) async {
  return _truenasKpisFrom(await ref.watch(truenasDashboardProvider.future));
}

Future<List<ServiceKpi>> _truenasKpisFor(Ref ref, String instanceId) async {
  final dashboard = await ref
      .watch(truenasServiceForProvider(instanceId))
      .loadDashboard();
  return _truenasKpisFrom(dashboard);
}

List<ServiceKpi> _truenasKpisFrom(TrueNasDashboard dashboard) {
  final pools = dashboard.pools;
  final usedFractions = pools
      .map((p) => p.usedFraction)
      .whereType<double>()
      .toList(growable: false);
  final maxUsed = usedFractions.isEmpty
      ? null
      : usedFractions.fold<double>(0, (max, v) => v > max ? v : max);
  final activeAlerts = dashboard.activeAlerts.length;
  final running = dashboard.services.where((s) => s.running).length;
  return [
    ServiceKpi(
      label: 'Pools',
      value: '${pools.length}',
      icon: Icons.dns_rounded,
    ),
    if (maxUsed == null)
      const ServiceKpi.unavailable(
        label: 'Used',
        icon: Icons.pie_chart_rounded,
        note: 'pool capacity unavailable',
      )
    else
      ServiceKpi(
        label: 'Used',
        value: formatPercent(maxUsed * 100),
        icon: Icons.pie_chart_rounded,
        tone: _faultIf(maxUsed >= 0.8),
      ),
    ServiceKpi(
      label: 'Alerts',
      value: '$activeAlerts',
      icon: Icons.warning_amber_rounded,
      tone: _faultIf(activeAlerts > 0),
    ),
    ServiceKpi(label: 'Services', value: '$running', icon: Icons.bolt_rounded),
  ];
}

Future<List<ServiceKpi>> _dockgeKpis(Ref ref) async {
  // The rail is a snapshot, not a second listener on the live stack list:
  // reading the service keeps the figures on the same client cache without
  // tying an autoDispose provider to a stream another page owns. The pages
  // that draw the list derive their own rail from it.
  return dockgeKpisFrom(await ref.watch(dockgeServiceProvider).fetchStacks());
}

Future<List<ServiceKpi>> _dockgeKpisFor(Ref ref, String instanceId) async {
  final stacks = await ref
      .watch(dockgeServiceForProvider(instanceId))
      .fetchStacks();
  return dockgeKpisFrom(stacks);
}

/// The Dockge rail from the stack list the page is drawing.
List<ServiceKpi> dockgeKpisFrom(List<DockgeStack> stacks) {
  final running = stacks
      .where((s) => s.status == DockgeStackStatus.running)
      .length;
  final stopped = stacks
      .where((s) => s.status == DockgeStackStatus.exited)
      .length;
  return dockgeKpisFromCounts(
    total: stacks.length,
    running: running,
    stopped: stopped,
  );
}

/// The Dockge rail from three counts, so the Overview can feed it from the
/// census it already watches instead of opening a second read of the list.
///
/// The inactive count is the remainder: a status the rail has no word for
/// still counts in the total it was counted in.
List<ServiceKpi> dockgeKpisFromCounts({
  required int total,
  required int running,
  required int stopped,
}) {
  final inactive = total - running - stopped;
  return [
    ServiceKpi(label: 'Stacks', value: '$total', icon: Icons.layers_rounded),
    ServiceKpi(
      label: 'Running',
      value: '$running',
      icon: Icons.play_circle_rounded,
    ),
    // Backlog, not a fault: Dockge does not say whether a stop was intended,
    // so a stopped count is a plain count with no tone.
    ServiceKpi(
      label: 'Stopped',
      value: '$stopped',
      icon: Icons.stop_circle_rounded,
    ),
    ServiceKpi(
      label: 'Inactive',
      value: '$inactive',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}
