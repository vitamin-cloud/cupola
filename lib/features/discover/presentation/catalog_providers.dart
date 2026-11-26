import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/catalog_query.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_details_provider.dart';

// The atrium's reads. Each throws when Seerr did not answer or answered with
// a failure, and none retries on its own (`noProviderRetry`): the atrium says
// what happened once, and Retry or a pull is the user's call.

/// Trending this week: the atrium's shelf, its door's artwork, and the
/// canary that says whether Seerr answered at all.
final atriumTrendingProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final page = await ref
      .watch(seerrServiceProvider)
      .getCatalogPage(const CatalogQuery.trending());
  return page.items;
}, retry: noProviderRetry);

/// Coming soon: films and series not out yet, the two lists woven together.
/// No region is claimed; TMDB's dates are the world's.
final comingSoonProvider = FutureProvider<List<MediaPreview>>((ref) async {
  final service = ref.watch(seerrServiceProvider);
  final pages = await Future.wait([
    for (final kind in CatalogKind.values)
      service.getCatalogPage(CatalogQuery.upcoming(kind)),
  ]);
  return interleave([for (final page in pages) page.items]);
}, retry: noProviderRetry);

/// What is coming out that nobody has asked for yet, the calendar's last
/// shelf: Coming soon without anything Seerr holds a record of (asked for,
/// on its way, on the server) and without anything whose day has come
/// (TMDB's upcoming lists keep a title a while after it opens). A removed
/// title can be asked for again, and stays.
final comingOutProvider = FutureProvider.autoDispose<List<MediaPreview>>((
  ref,
) async {
  final numbering = await ref.watch(seerrNumberingProvider.future);
  final soon = await ref.watch(comingSoonProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  bool asked(MediaPreview item) {
    final code = intOrNull(item.mediaInfo?['status']);
    if (code == null) return false;
    return switch (SeerrMediaAvailability.fromCode(
      code,
      numbering: numbering,
    )) {
      SeerrMediaAvailability.unknown || SeerrMediaAvailability.deleted => false,
      _ => true,
    };
  }

  return [
    for (final item in soon)
      if (!asked(item) &&
          (arrCalendarDate(item.releaseDate)?.isAfter(today) ?? false))
        item,
  ];
}, retry: noProviderRetry);

/// [lists] woven one title from each in turn, a title that appears twice
/// kept where it first came.
List<MediaPreview> interleave(List<List<MediaPreview>> lists) {
  final seen = <String>{};
  final woven = <MediaPreview>[];
  final longest = lists.fold<int>(
    0,
    (max, list) => list.length > max ? list.length : max,
  );
  for (var i = 0; i < longest; i++) {
    for (final list in lists) {
      if (i >= list.length) continue;
      final item = list[i];
      if (seen.add('${item.mediaType}:${item.id}')) woven.add(item);
    }
  }
  return woven;
}
