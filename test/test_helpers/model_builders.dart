/// Shared factory helpers that build test model instances with sensible
/// defaults. Use named parameters to override any field that matters for the
/// specific scenario.
library;

import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

RadarrMovie buildMovie({
  int id = 1,
  String title = 'Movie',
  int tmdbId = 123,
  int year = 2024,
  int runtime = 100,
  int sizeOnDisk = 0,
  String status = 'released',
  bool hasFile = true,
  bool monitored = true,
  String? overview,
  String? path,
  String? studio,
  String? certification,
  List<String> genres = const [],
  List<RatingSource> ratings = const [],
  List<dynamic> images = const [],
  bool? isAvailable,
  // `RadarrMovie` has no `copyWith`, so a test that needs a profile had to
  // hand-build the whole model; the action band only renders the profile path
  // when this is set.
  int? qualityProfileId,
}) {
  return RadarrMovie(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    sizeOnDisk: sizeOnDisk,
    status: status,
    overview: overview,
    path: path,
    hasFile: hasFile,
    monitored: monitored,
    year: year,
    images: images,
    tmdbId: tmdbId,
    runtime: runtime,
    studio: studio,
    genres: genres,
    certification: certification,
    ratings: ratings,
    isAvailable: isAvailable,
    qualityProfileId: qualityProfileId,
  );
}

SonarrSeries buildSeries({
  int id = 1,
  String title = 'Series',
  int tvdbId = 555,
  int year = 2024,
  int runtime = 45,
  String status = 'continuing',
  bool monitored = true,
  String? overview,
  String? path,
  String? network,
  String? seriesType,
  String? certification,
  List<String> genres = const [],
  List<Map<String, dynamic>> seasons = const [],
  Map<String, dynamic>? statistics,
  List<RatingSource> ratings = const [],
  List<dynamic> images = const [],
}) {
  return SonarrSeries(
    id: id,
    title: title,
    sortTitle: title.toLowerCase(),
    status: status,
    overview: overview,
    path: path,
    monitored: monitored,
    year: year,
    images: images,
    tvdbId: tvdbId,
    runtime: runtime,
    network: network,
    genres: genres,
    seasons: seasons,
    statistics: statistics,
    seriesType: seriesType,
    certification: certification,
    ratings: ratings,
  );
}

SonarrEpisode buildEpisode({
  int id = 1,
  int seasonNumber = 1,
  int episodeNumber = 1,
  String title = 'Episode',
  bool hasFile = true,
  bool monitored = true,
}) {
  return SonarrEpisode(
    id: id,
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    title: title,
    hasFile: hasFile,
    monitored: monitored,
  );
}
