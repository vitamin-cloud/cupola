/// What the Sonarr Overview reads, and the pure functions that shape it.
///
/// Sonarr shares Radarr's bar exactly: Overview, Library, Calendar, Queue,
/// Wanted, History, so this file is deliberately the sibling of
/// `radarr_overview_provider.dart` and departs from it only where the record
/// forces it to. The record here is an **episode inside a season inside a
/// series**, and that is the one difference that runs through everything: a
/// count of episodes must say episodes, a row names the slot (`S2 E5`) as well
/// as the series, and the week window can only be built out of what a *series*
/// row carries.
///
/// The one structural departure: Radarr derives its Coming up from the library
/// because a film's dates are on the film. Episodes are not on the series row
/// at all: the honest source is `GET /api/v3/calendar`, which `SonarrService`
/// has never called (the same block `lib/core/router.dart` records for the
/// Calendar tab). What is reachable is `nextAiring`, one instant per series on
/// the `series` call the KPI rail already makes, so the week window here counts
/// **series with an episode due**, never episodes. See [sonarrAiringWeek].
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/utils/date_format.dart' show formatRelativeDateTime;
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Posters on the Recently downloaded rail.
const int sonarrRecentlyDownloadedLimit = 6;

/// One page of history, and deliberately only one.
///
/// Thirty rather than Radarr's twenty because the record is an episode: a
/// weekly series drops nine files where a film drops one, so twenty rows on a
/// busy Sonarr can be an hour of activity. It is still one request, and both
/// history-derived sections read this same page rather than fetching twice.
const int sonarrHistoryPageSize = 30;

// ─── Airing this week ───────────────────────────────────────────────────────

/// One series with an episode due inside the window.
@immutable
class SonarrAiringEntry {
  const SonarrAiringEntry({required this.series, required this.airsAt});

  final SonarrSeries series;

  /// Local time. The window is a run of local calendar days, so an entry
  /// compared in UTC would slip a day either side of midnight.
  final DateTime airsAt;
}

/// The week window, and whether its emptiness can be believed.
///
/// [canReport] exists because `nextAiring` is absent for two entirely different
/// reasons: nothing is scheduled, or this server never sent the field, and
/// they must not render as the same sentence. An empty list with
/// [canReport] false is "Sonarr did not say", which is a missing answer; an
/// empty list with it true is "nothing airs this week", which is an answer.
@immutable
class SonarrAiringWeek {
  const SonarrAiringWeek({required this.entries, required this.canReport});

  /// Sorted by air time, then by sort title so two episodes in the same slot
  /// have a stable order.
  final List<SonarrAiringEntry> entries;

  /// False when at least one series could still be airing and **no** series in
  /// the whole library carried a next-airing date.
  final bool canReport;
}

// ─── Needs attention ────────────────────────────────────────────────────────

/// The four conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and two are backlog, which the five-arm tone rule paints
/// neutral. Painting the backlog amber is the single most common way that rule
/// is broken: a library with twelve episodes still to find is not a library
/// that is broken.
enum SonarrAttentionKind implements ArrAttentionKind {
  /// Sonarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault: the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Monitored episodes that have aired and are not on disk. Backlog: nothing
  /// is broken, there is simply work outstanding.
  missing(StatusTone.neutral, Icons.radar_rounded),

  /// Episodes on disk below the configured quality cutoff. Backlog too.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const SonarrAttentionKind(this.tone, this.icon);

  @override
  final StatusTone tone;

  @override
  final IconData icon;
}

/// The slot a queue or history record is about: `S2 E5`, or `S4` for a season
/// pack, or null when the record names neither.
///
/// [arrEpisodeCode] needs both numbers and answers null without them, which is
/// exactly the shape of a season pack, the record the board's own example row
/// is made of ("Season pack failed to import · Slow Horses S04"). Dropping to
/// the bare season is what lets that row name the thing that failed instead of
/// printing the series title twice over.
String? sonarrEpisodeSlot(Map<String, dynamic> record) {
  final code = arrEpisodeCode(record);
  if (code != null) return code;

  final season = intOrNull(
    mapOrNull(record['episode'])?['seasonNumber'] ?? record['seasonNumber'],
  );
  if (season == null) return null;
  return formatSeasonCode(season);
}

/// How many distinct series a backlog page spans, or null when the page cannot
/// answer that.
///
/// Null unless the envelope's total says this one page holds **every** record:
/// twenty rows out of two hundred span the series those twenty happened to
/// touch, and printing that as "across 5 series" turns a sampling artefact into
/// a fact about the library. The board asks for the clause; this is the only
/// condition under which the client can honour it.
int? sonarrSeriesSpread(ArrRecordPage page) {
  final total = page.total;
  if (total == null || total > page.records.length) return null;

  final ids = <int>{};
  for (final raw in page.records) {
    final record = mapOrNull(raw);
    if (record == null) continue;
    final id = intOrNull(
      record['seriesId'] ?? mapOrNull(record['series'])?['id'],
    );
    if (id != null) ids.add(id);
  }
  return ids.isEmpty ? null : ids.length;
}

// ─── History, and the two sections built from it ────────────────────────────

/// One page of history, read once and shared.
///
/// Recently downloaded and History today are two readings of the same rows, so
/// they take one request between them rather than one each. Both derive with
/// `ref.watch(...future)`, which is also why neither needs a `retry:` of its
/// own: this source declares none, so there is none to drop.
final sonarrHistoryPageProvider = FutureProvider.autoDispose<List<dynamic>>((
  ref,
) async {
  return ref
      .watch(sonarrServiceProvider)
      .getHistory(page: 1, pageSize: sonarrHistoryPageSize);
});

/// One imported episode, resolved into the tile the rail draws.
@immutable
class SonarrDownloadedEpisode {
  const SonarrDownloadedEpisode({
    required this.seriesId,
    this.tmdbId,
    required this.seriesTitle,
    required this.slot,
    required this.images,
    required this.date,
    required this.age,
  });

  /// Sonarr's series id: required, because the tile is a link and a poster
  /// that cannot navigate is a promise the page cannot keep.
  final int seriesId;

  /// TMDB's id of the series, when the embedded series carries it (Sonarr
  /// v4): the series' own page opens by it.
  final int? tmdbId;

  final String seriesTitle;

  /// `S2 E4`, or null when the record named no slot.
  final String? slot;

  /// The embedded series' `images`, for the poster.
  final List<dynamic> images;

  final DateTime date;

  /// `40 min ago`, resolved once against the `now` the window was built with.
  ///
  /// Held rather than recomputed in `build`: a string the widget derives from
  /// the wall clock is a string no test can assert and one the tile and its
  /// spoken label can disagree about across a rebuild.
  final String age;

  /// The caption under the poster: the slot, then how long ago.
  String get caption => joinDisplayParts([slot, age]);

  String get spoken => joinSpokenParts([seriesTitle, slot, age]);
}

/// The most recently imported episodes, newest first, one tile per series.
///
/// Deduplicated by series, because a season pack import writes eight records
/// and a rail of eight identical posters says less than one. The newest of them
/// wins, which is the one whose slot the caption shows.
///
/// **No time claim.** The board's header reads "9 episodes this week"; this is
/// one page of thirty records, which on a busy server may not reach back a
/// week, so the section says "latest imports" and prints no count. A figure
/// derived from however many rows happened to fit on a page is exactly the
/// plausible-but-wrong number the rest of this file refuses to print.
List<SonarrDownloadedEpisode> sonarrRecentlyDownloaded(
  List<dynamic> records, {
  required DateTime now,
  int limit = sonarrRecentlyDownloadedLimit,
}) {
  final dated = <(DateTime, SonarrDownloadedEpisode)>[];

  for (final raw in records) {
    final record = mapOrNull(raw);
    if (record == null) continue;

    final eventType = stringOrNull(record['eventType']);
    if (eventType != 'downloadFolderImported' &&
        eventType != 'downloadImported') {
      continue;
    }

    final date = parseLocalInstant(stringOrNull(record['date']));
    if (date == null) continue;

    final series = mapOrNull(record['series']);
    final seriesId = intOrNull(record['seriesId'] ?? series?['id']);
    if (seriesId == null || seriesId <= 0) continue;

    dated.add((
      date,
      SonarrDownloadedEpisode(
        seriesId: seriesId,
        tmdbId: intOrNull(series?['tmdbId']),
        seriesTitle: arrSeriesTitle(record) ?? 'Unknown series',
        slot: sonarrEpisodeSlot(record),
        images: (series?['images'] as List<dynamic>?) ?? const [],
        date: date,
        age: formatRelativeDateTime(date, now: now),
      ),
    ));
  }

  dated.sort((a, b) => b.$1.compareTo(a.$1));

  final seen = <int>{};
  final tiles = <SonarrDownloadedEpisode>[];
  for (final (_, tile) in dated) {
    if (!seen.add(tile.seriesId)) continue;
    tiles.add(tile);
    if (tiles.length == limit) break;
  }
  return List.unmodifiable(tiles);
}

final sonarrRecentlyDownloadedProvider =
    FutureProvider.autoDispose<List<SonarrDownloadedEpisode>>((ref) async {
      final records = await ref.watch(sonarrHistoryPageProvider.future);
      return sonarrRecentlyDownloaded(records, now: DateTime.now());
    });

// ─── Shared parsing ─────────────────────────────────────────────────────────
