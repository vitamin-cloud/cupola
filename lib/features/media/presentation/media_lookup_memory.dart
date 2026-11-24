import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// This fork's ("Stack") memory of the Sonarr and Radarr search results a
/// title page was opened from, for the session.
///
/// A title nobody has added yet has no copy in an arr, and without a Seerr
/// nothing else knows its artwork or its scores, so its page drew no banner
/// and four dashes. The lookup that found it already carried both (TMDB's and
/// TVDB's public pictures, Radarr's IMDb, TMDB, Rotten Tomatoes and
/// Metacritic figures): the page falls back on that record.
final mediaLookupMemoryProvider = Provider<Map<MediaKey, Object>>(
  (ref) => <MediaKey, Object>{},
);

/// Keeps [record] (a [SonarrSeries] or a [RadarrMovie] from a lookup) as what
/// is known of [key].
void rememberLookup(WidgetRef ref, MediaKey key, Object record) {
  assert(record is SonarrSeries || record is RadarrMovie);
  ref.read(mediaLookupMemoryProvider)[key] = record;
}
