/// What the Radarr Overview reads, and the pure functions that shape it.
///
/// The Overview is the one tab that carries the identity block and the
/// readouts, so everything else on it is derived rather than fetched twice:
/// Coming up and Recently added both fall out of [radarrOverviewMoviesProvider],
/// and Needs attention reads the *raw* queue records
/// rather than [ArrQueueSnapshot], the snapshot collapses to one headline per
/// media id and drops the titles and timestamps the fault rows are made of.
///
/// Every windowing rule lives in a top-level pure function taking an explicit
/// `now`, so the boundaries are unit-testable without a clock or a container.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';

/// Posters on the Recently added rail.
const int radarrRecentlyAddedLimit = 6;

// ─── Coming up ──────────────────────────────────────────────────────────────

/// Which of a film's three dates an upcoming entry is about.
///
/// Radarr carries all three on the library row, so a film can legitimately
/// appear twice in one week: a digital release on Tuesday and a physical one
/// on Friday are two events, not one row that has to pick a winner.
enum RadarrReleaseKind {
  inCinemas(Lexicon.inCinemas),
  digital(Lexicon.onDigital),
  physical(Lexicon.onDisc);

  const RadarrReleaseKind(this.label);

  /// Sentence case, for the eye and for the ear alike, and the calendar's own
  /// words: one film on one date is named the same on both screens.
  final String label;
}

/// One dated release inside the Coming up window.
@immutable
class RadarrUpcomingRelease {
  const RadarrUpcomingRelease({
    required this.movie,
    required this.date,
    required this.kind,
  });

  final RadarrMovie movie;

  /// The calendar date the release spells, as a local midnight
  /// ([arrCalendarDate]). The window is a run of local calendar days, and a
  /// release date is one of them, not an instant to convert into one.
  final DateTime date;

  final RadarrReleaseKind kind;
}

/// The library, read so that a failure is still a failure when it arrives.
///
/// **[moviesProvider] itself**, which reads `getMoviesOrThrow` now: this was
/// a second copy of the same request, and with the KPI rail's a third, so the
/// heaviest answer the app asks for was downloaded up to three times a
/// session. One read, `noProviderRetry` like the wall and the rail: a blip is
/// the user's Retry. Pull-to-refresh and the sections' Retry invalidate it.
final radarrOverviewMoviesProvider = moviesProvider;

// ─── Recently added ─────────────────────────────────────────────────────────

/// The newest [limit] additions, newest first.
///
/// A film with no parseable `added` is dropped rather than sorted to one end:
/// the rail claims to be ordered by when things arrived, and an entry with no
/// arrival time cannot honour that claim in either direction.
List<RadarrMovie> radarrRecentlyAdded(
  List<RadarrMovie> movies, {
  int limit = radarrRecentlyAddedLimit,
}) {
  final dated = <(DateTime, RadarrMovie)>[];
  for (final movie in movies) {
    final added = parseLocalInstant(movie.added);
    if (added != null) dated.add((added, movie));
  }
  dated.sort((a, b) => b.$1.compareTo(a.$1));
  return List.unmodifiable(dated.take(limit).map((entry) => entry.$2));
}

final radarrRecentlyAddedProvider =
    FutureProvider.autoDispose<List<RadarrMovie>>((ref) async {
      final movies = await ref.watch(radarrOverviewMoviesProvider.future);
      return radarrRecentlyAdded(movies);
    }, retry: noProviderRetry);

// ─── Needs attention ────────────────────────────────────────────────────────

/// The three conditions this screen can derive today.
///
/// Each carries its own tone, and that is the whole point of the enum: two of
/// these are faults and the third is backlog, which the five-arm tone rule
/// paints neutral. Collapsing them into one "attention" colour is how a pile of
/// upgrades ends up wearing the same amber as a broken import.
enum RadarrAttentionKind implements ArrAttentionKind {
  /// Radarr grabbed the release and could not move it into the library.
  importFailed(StatusTone.warning, Icons.file_download_off_rounded),

  /// The transfer is not moving. A fault: the user did not ask for this.
  stalled(StatusTone.warning, Icons.sync_problem_rounded),

  /// Files on disk below the configured quality cutoff. Backlog, so neutral:
  /// nothing is broken, there is simply work outstanding.
  belowCutoff(StatusTone.neutral, Icons.upgrade_rounded);

  const RadarrAttentionKind(this.tone, this.icon);

  @override
  final StatusTone tone;

  @override
  final IconData icon;
}

// ─── History today ──────────────────────────────────────────────────────────

// ─── Shared parsing ─────────────────────────────────────────────────────────
