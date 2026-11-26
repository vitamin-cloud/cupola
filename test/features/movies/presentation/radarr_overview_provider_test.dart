import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/movies/presentation/radarr_overview_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

import '../../../test_helpers/fake_services.dart';

/// A [FakeRadarrService] with a scripted library, queue, history and cutoff
/// list.
///
/// Extends the shared fake rather than editing it: every other test that builds
/// a `FakeRadarrService` keeps the empty defaults it relies on.
class _ScriptedRadarr extends FakeRadarrService {
  _ScriptedRadarr({
    this.movies = const [],
    this.queue = const [],
    this.history = const [],
    this.cutoffTotal,
  });

  final List<RadarrMovie> movies;
  final List<dynamic> queue;
  final List<dynamic> history;

  /// What `wanted/cutoff` reports as its `totalRecords`: **null** for a fork
  /// that does not serve the endpoint, which is what
  /// `ArrRecordPage.fromEnvelope` degrades an unreadable envelope to.
  final int? cutoffTotal;

  /// How many requests the cutoff figure cost.
  int cutoffPageCalls = 0;

  /// How many times the figure was taken by downloading every record.
  int allCutoffCalls = 0;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => queue;

  @override
  Future<List<dynamic>> getHistory({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async => history;

  @override
  Future<List<dynamic>> getAllCutoff({
    Map<String, dynamic>? queryParameters,
  }) async {
    allCutoffCalls++;
    // What the real one answers: every record, a page of 250 at a time, and
    // `[]` when the fork does not serve the endpoint, which is why a caller
    // that counts these cannot tell "none" from "never answered".
    return List<dynamic>.generate(
      cutoffTotal ?? 0,
      (index) => {'id': index + 1},
    );
  }

  @override
  Future<ArrRecordPage> getCutoffPage({
    int page = 1,
    int pageSize = 20,
    Map<String, dynamic>? queryParameters,
  }) async {
    cutoffPageCalls++;
    return ArrRecordPage(records: const [], total: cutoffTotal);
  }
}

ProviderContainer _container(_ScriptedRadarr service) {
  final container = ProviderContainer(
    // Riverpod re-runs a failed provider on an exponential backoff; a test that
    // deliberately fails one would otherwise wait out the whole sequence.
    retry: (_, _) => null,
    overrides: [
      radarrServiceProvider.overrideWith((ref) => service),
      // The connection the lens is on, which a download's door is addressed
      // by: none here, so the door names no connection.
      activeInstanceProvider.overrideWith((ref, service) => null),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A movie carrying only the fields this screen reads.
///
/// Built here rather than through `buildMovie`, which models none of the four
/// dates the Overview is derived from.
RadarrMovie _movie({
  required int id,
  String title = 'Film',
  bool monitored = true,
  String? added,
  String? inCinemas,
  String? digitalRelease,
  String? physicalRelease,
}) => RadarrMovie(
  id: id,
  title: title,
  sortTitle: title.toLowerCase(),
  sizeOnDisk: 0,
  status: 'released',
  hasFile: true,
  monitored: monitored,
  year: 2024,
  images: const [],
  tmdbId: id,
  runtime: 100,
  genres: const [],
  added: added,
  inCinemas: inCinemas,
  digitalRelease: digitalRelease,
  physicalRelease: physicalRelease,
);

/// Local-time ISO, so the window's local calendar days are what the test is
/// actually exercising: a `Z` suffix would move the boundary by the runner's
/// offset and make the assertion pass or fail by timezone.
String _iso(DateTime date) => date.toIso8601String();

void main() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  group('radarrUpcomingReleases', () {});

  group('radarrRecentlyAdded', () {
    test('is newest first and capped at six', () {
      final movies = [
        for (var day = 1; day <= 9; day++)
          _movie(
            id: day,
            title: 'Film $day',
            added: _iso(DateTime(today.year, today.month, today.day - day)),
          ),
      ];

      final recent = radarrRecentlyAdded(movies);

      expect(recent, hasLength(radarrRecentlyAddedLimit));
      expect(recent.map((movie) => movie.title), [
        'Film 1',
        'Film 2',
        'Film 3',
        'Film 4',
        'Film 5',
        'Film 6',
      ]);
    });

    test('drops a film whose arrival time is missing or unreadable', () {
      final recent = radarrRecentlyAdded([
        _movie(id: 1, title: 'Dated', added: _iso(today)),
        _movie(id: 2, title: 'Undated'),
        _movie(id: 3, title: 'Nonsense', added: 'not a date'),
      ]);

      expect(recent.map((movie) => movie.title), ['Dated']);
    });
  });

  group('radarrHistoryToday', () {});

  group('radarrQueueFaults', () {});

  group('radarrQueueFaults leads to where the fault is fixed', () {});

  group('radarrBelowCutoffItem', () {});

  group('the providers', () {
    test('recently added comes back newest first', () async {
      final container = _container(
        _ScriptedRadarr(
          movies: [
            _movie(
              id: 1,
              title: 'Older',
              added: _iso(DateTime(today.year, today.month, today.day - 3)),
            ),
            _movie(id: 2, title: 'Newer', added: _iso(today)),
          ],
        ),
      );

      final recent = await container.read(radarrRecentlyAddedProvider.future);

      expect(recent.map((movie) => movie.title), ['Newer', 'Older']);
    });
  });
}
