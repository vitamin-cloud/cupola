/// Activity's four views on the profiles: what each draws, in which order,
/// what it leaves out when it has nothing to say, and what it says when a
/// source did not answer.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_download_row.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/widgets/release_search_job_card.dart';
import 'package:cupola/features/release_search/presentation/release_search_jobs_provider.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _mb = 1024 * 1024;
const _gb = 1024 * 1024 * 1024;

/// Friday 9 October 2026, 20:53: the evening the world is drawn in.
final _now = DateTime(2026, 10, 9, 20, 53);

/// A queue with nothing in it, whatever the profile's clients hold.
final _quiet = <Override>[
  servicesQueueProvider.overrideWith(
    (ref) async =>
        (items: const <ServiceQueueItem>[], coverage: SourceCoverage.none),
  ),
];

final _clocks = <Override>[
  arrivalsClockProvider.overrideWith(
    (ref) =>
        () => _now,
  ),
  stallClockProvider.overrideWith(
    (ref) =>
        () => _now,
  ),
];

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  ActivityTab tab, {
  String? requestsOf,
  double textScale = 1,
  Size size = const Size(430, 8000),
  List<Override> overrides = const [],
  List<ProviderObserver> observers = const [],
}) async => _mount(
  tester,
  await ProfileHarness.start(
    profile,
    now: _now,
    overrides: [..._clocks, ...overrides],
  ),
  tab,
  requestsOf: requestsOf,
  textScale: textScale,
  size: size,
  observers: observers,
);

/// Mounts the page on a harness the test has already scripted.
Future<ProfileHarness> _mount(
  WidgetTester tester,
  ProfileHarness harness,
  ActivityTab tab, {
  String? requestsOf,
  double textScale = 1,
  Size size = const Size(430, 8000),
  List<ProviderObserver> observers = const [],
}) async {
  harness.network.followFakeTime(tester.binding);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      observers: observers,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: ActivityPage(tab: tab),
          ),
        ),
      ),
    ),
  );
  await harness.settle(tester);
  // Some answers (Seerr's list among them) are mapped on an isolate, which
  // fake time never turns: give the real loop a moment, then settle again.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await harness.settle(tester);
  return harness;
}

/// The sections the page draws, in order, as their name and what they count.
List<String> _sections(WidgetTester tester) => [
  for (final section in tester.widgetList<ActivitySection>(
    find.byType(ActivitySection),
  ))
    if (section.title != 'Needs you')
      section.meta == null
          ? section.title
          : '${section.title}\u00A0· ${section.meta}',
];

List<String> _titles(WidgetTester tester) => [
  for (final section in tester.widgetList<ActivitySection>(
    find.byType(ActivitySection),
  ))
    if (section.title != 'Needs you') section.title,
];

/// [matching] inside the section named [title].
Finder _inSection(String title, Finder matching) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is ActivitySection && widget.title == title,
  ),
  matching: matching,
);

/// A grab of [arr], a Sonarr connection, moving through qBittorrent.
WorldDownload _grab(int n, String arr) => WorldDownload(
  id: 'a1f0c3d4e5f60718293a4b5c6d7e8f90123458${n.toString().padLeft(2, '0')}',
  release: 'Show.$n.S01E01.1080p',
  client: 'qbittorrent',
  state: DownloadState.downloading,
  progress: 0.4,
  size: _gb,
  arr: arr,
  title: WorldTitles.cosmosLaundromat,
  season: 1,
  episode: n,
  speed: 2 * _mb,
  eta: const Duration(minutes: 10),
);

/// A history record as an arr sends it, with the movie it embeds.
Map<String, Object?> _import(
  ProfileHarness harness,
  int id,
  Duration ago, {
  String event = 'downloadFolderImported',
  Map<String, Object?>? data,
}) => {
  'id': id,
  'movieId': id,
  'eventType': event,
  'sourceTitle': 'Movie.$id.2024.1080p',
  'date': harness.network.now.subtract(ago).toUtc().toIso8601String(),
  'movie': {'id': id, 'title': 'Movie $id', 'year': 2024, 'tmdbId': 900 + id},
  'data': data ?? const <String, Object?>{},
};

void main() {
  group('All', () {});

  group('Downloads', () {
    testWidgets('P1: what moves as its queue orders it, the stuck one last '
        'with the proof, then Up next', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);

      expect(_sections(tester), [
        'Downloads\u00A0· 5 moving\u00A0· 1 stuck',
        'Up next\u00A0· 1 queued',
      ]);
      final order = [
        'Cosmos Laundromat\u00A0· S2\u00A0E4',
        'Sprite Fright',
        'Elephants Dream',
        'Cosmos Laundromat\u00A0· S2\u00A0E5',
        'Big Buck Bunny',
      ];
      final ys = [
        for (final title in order)
          tester.getTopLeft(_inSection('Downloads', find.text(title))).dy,
      ];
      expect(ys, [...ys]..sort());
      // The stuck row says where it stopped and how long nothing came.
      expect(find.text('Stuck at 47%'), findsOneWidget);
      expect(find.text('nothing for 3\u00A0h'), findsOneWidget);
      // Which way the bytes go, and a moving row's own speed.
      expect(find.text('Radarr 4K → qBittorrent'), findsNWidgets(2));
      expect(find.text('12.1\u00A0MB/\u2060s'), findsOneWidget);
      // Whose request brought it, and when it should be ready.
      expect(
        find.text("Anna's request\u00A0· ready around 21:04"),
        findsOneWidget,
      );
      // Up next: the queued one, and who asked.
      expect(find.textContaining('Queued'), findsWidgets);
      expect(find.text("Anna's request"), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('no search, no group', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);

      expect(find.text('Searching'), findsNothing);
      expect(find.byType(ReleaseSearchJobCard), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('a search stands at the head, above Downloads', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.downloads);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      );
      final jobs = container.read(releaseSearchJobsProvider.notifier);
      jobs.configure(runner: (_, _) => Completer<List<dynamic>>().future);
      jobs.start(
        const ReleaseSearchTarget.movie(
          movieId: 2,
          label: 'Sintel',
        ).stampedWith(WorldIds.radarr4k),
      );
      await tester.pump();

      // The heading, and the card's own state under it.
      expect(find.text('Searching'), findsWidgets);
      expect(find.text('1 search'), findsOneWidget);
      expect(find.byType(ReleaseSearchJobCard), findsOneWidget);
      // A pull reaches it as it reaches the rest: it is in the page's scroll.
      expect(
        find.ancestor(
          of: find.byType(ReleaseSearchJobCard),
          matching: find.byType(RefreshIndicator),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.text('Searching').first).dy,
        lessThan(
          tester.getTopLeft(_inSection('Downloads', find.text('Downloads'))).dy,
        ),
      );

      await harness.unmount(tester);
    });

    testWidgets('with nothing moving the view says so, and when the last '
        'download finished', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: _quiet,
      );

      expect(find.text('Nothing is downloading'), findsOneWidget);
      // Under the title and under the section: the same moment.
      expect(find.text('Nothing moving'), findsOneWidget);
      expect(find.text('Last download finished 18:52'), findsNWidgets(2));
      expect(find.byType(ActivityDownloadRow), findsNothing);
      expect(_titles(tester), ['Downloads']);

      await harness.unmount(tester);
    });

    testWidgets('a read again keeps the rows on screen: a pull or a poll '
        'never blanks the list', (tester) async {
      final gate = Completer<void>();
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: [
          servicesQueueProvider.overrideWith((ref) async {
            reads++;
            // The first read answers; every later one is held open, so the
            // reload itself is what is on screen.
            if (reads > 1) await gate.future;
            return (
              items: const [
                ServiceQueueItem(
                  service: ServiceKey.radarr,
                  id: '1',
                  title: 'Furiosa.2024.2160p',
                  progress: 0.75,
                  clientLabel: 'qBittorrent',
                  clientService: ServiceKey.qbittorrent,
                  etaSeconds: 600,
                ),
              ],
              coverage: SourceCoverage.none,
            );
          }),
        ],
      );
      expect(find.byType(ActivityDownloadRow), findsOneWidget);
      expect(_sections(tester), ['Downloads\u00A0· 1 moving']);

      ProviderScope.containerOf(
        tester.element(find.byType(ActivityPage)),
      ).invalidate(servicesQueueProvider);
      await tester.pump(const Duration(milliseconds: 10));
      expect(reads, 2);

      // Mid-read the row and the count are the last answer's.
      expect(find.byType(ActivityDownloadRow), findsOneWidget);
      expect(_sections(tester), ['Downloads\u00A0· 1 moving']);
      expect(find.text('Nothing is downloading'), findsNothing);

      gate.complete();
      await harness.settle(tester);
      expect(find.byType(ActivityDownloadRow), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a queue that could not be read says so in its own place, '
        'with a Retry that reads it again', (tester) async {
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        overrides: [
          servicesQueueProvider.overrideWith((ref) async {
            reads++;
            throw Exception('down');
          }),
        ],
      );
      final first = reads;

      expect(find.byType(BriefFailureLine), findsOneWidget);
      expect(find.byType(ActivityDownloadRow), findsNothing);
      expect(find.text('Nothing is downloading'), findsNothing);

      await tester.tap(find.text('Retry'));
      await harness.settle(tester);
      expect(reads, greaterThan(first));

      await harness.unmount(tester);
    });
  });

  group('Requests', () {});

  group('History', () {
    testWidgets('P1: the week by day, newest first, with the older history '
        'and the blocklist at the foot', (tester) async {
      final harness = await _pump(tester, Profiles.p1, ActivityTab.history);

      expect(_sections(tester), [
        'Today\u00A0· 3',
        'Yesterday\u00A0· 1',
        'Wed 7 Oct\u00A0· 1',
      ]);
      // Nothing of the other views.
      expect(find.byType(ActivityDownloadRow), findsNothing);
      // Each import with the file it became.
      expect(find.text('Spring (2014).mkv'), findsOneWidget);
      expect(find.text('Tears of Steel (2012).mkv'), findsOneWidget);
      expect(
        find.text(
          'Older history stays in each service, under its History tab.',
        ),
        findsOneWidget,
      );
      final foot = ['Sonarr history', 'Radarr history', 'Blocklist'];
      final ys = [
        for (final label in foot) tester.getTopLeft(find.text(label)).dy,
      ];
      expect(ys, [...ys]..sort());
      expect(
        find.text('Releases the arrs will not take again'),
        findsOneWidget,
      );

      await harness.unmount(tester);
    });

    testWidgets('a download that failed is in its day beside the imports, '
        'with why', (tester) async {
      final harness = await ProfileHarness.start(
        Profiles.p1,
        now: _now,
        overrides: _clocks,
      );
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/history/since',
        (r) => r.query['eventType'] == 'downloadFailed'
            ? NetworkReply.json([
                _import(
                  harness,
                  41,
                  const Duration(hours: 6, minutes: 51),
                  event: 'downloadFailed',
                  data: {'message': 'Aborted by the client'},
                ),
              ])
            : null,
      );
      await _mount(tester, harness, ActivityTab.history);

      expect(_sections(tester).first, 'Today\u00A0· 4');
      expect(find.text('Download failed 14:02'), findsOneWidget);
      expect(find.text('Aborted by the client'), findsOneWidget);
      // Beside the imports, newest first: the failure is the oldest of the
      // day, so it is last.
      expect(
        tester.getTopLeft(find.text('Download failed 14:02')).dy,
        greaterThan(tester.getTopLeft(find.text('Imported 18:10')).dy),
      );

      await harness.unmount(tester);
    });

    testWidgets('a week with nothing in it says so, and keeps the foot', (
      tester,
    ) async {
      final empty = (
        entries: const <ArrHistoryEntry>[],
        coverage: SourceCoverage.none,
      );
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        overrides: [
          servicesArrivalsProvider.overrideWith((ref) async => empty),
          servicesFailuresSinceProvider.overrideWith((ref) async => empty),
        ],
      );

      expect(
        find.text('Nothing finished in the last seven days'),
        findsOneWidget,
      );
      expect(_titles(tester), isEmpty);
      expect(find.text('Sonarr history'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a connection that did not answer is named, and the days are '
        'the others\'', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        ),
        ActivityTab.history,
      );

      // Under the title, for the queue, and under the week.
      expect(find.text('Not in the total: Radarr 4K'), findsNWidgets(2));
      expect(find.text('Spring (2014).mkv'), findsNothing);
      expect(find.text('Coffee Run (2020).mkv'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a week that could not be read says so, with a Retry that '
        'reads both halves again', (tester) async {
      var reads = 0;
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        overrides: [
          servicesFailuresSinceProvider.overrideWith((ref) async {
            reads++;
            throw Exception('down');
          }),
        ],
      );

      // A read that throws is asked again with a growing wait before it is
      // called failed: the page draws nothing of the week until then, and
      // never a zero.
      expect(find.byType(BriefFailureLine), findsNothing);
      expect(_titles(tester), isEmpty);
      for (var second = 0; second < 60; second += 2) {
        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      final first = reads;

      expect(find.byType(BriefFailureLine), findsOneWidget);
      expect(_titles(tester), isEmpty);

      await tester.tap(find.text('Retry'));
      await harness.settle(tester);
      expect(reads, greaterThan(first));

      await harness.unmount(tester);
    });
  });

  group('reading again', () {
    // A phone's height: a pull has to travel a quarter of it to count.
    const phone = Size(430, 900);

    int reads(ProfileHarness harness, String id, String path) => harness.network
        .requestsTo(id)
        .where((request) => request.uri.path.startsWith(path))
        .length;

    Future<void> pull(WidgetTester tester, ProfileHarness harness) async {
      await tester.drag(
        find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, 300),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);
    }

    testWidgets('a pull on Downloads reads the queues again', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.downloads,
        size: phone,
      );
      final before = reads(harness, WorldIds.radarr, '/api/v3/queue');
      expect(before, greaterThan(0));

      await pull(tester, harness);

      expect(
        reads(harness, WorldIds.radarr, '/api/v3/queue'),
        greaterThan(before),
      );
      // What it read again is on screen, not a skeleton: Needs you leads
      // the view on a phone, the rows under it.
      expect(find.text('Needs you'), findsOneWidget);

      await harness.unmount(tester);
    });

    testWidgets('a pull on History reads the week again, both halves', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p1,
        ActivityTab.history,
        size: phone,
      );
      final before = reads(harness, WorldIds.radarr, '/api/v3/history/since');
      expect(before, greaterThan(1));

      await pull(tester, harness);

      expect(
        reads(harness, WorldIds.radarr, '/api/v3/history/since'),
        greaterThan(before),
      );

      await harness.unmount(tester);
    });
  });

  group('a source that did not answer is named and not counted', () {
    testWidgets('P6: two Sonarr connections, each one\'s downloads counted '
        'once and each row naming its own', (tester) async {
      final harness = await _pump(
        tester,
        Profiles.p6.withDownloads([
          _grab(1, WorldIds.sonarr),
          _grab(2, WorldIds.sonarrAnime),
        ]),
        ActivityTab.downloads,
      );

      // Four moving and the stuck one in the world, and the two grabs.
      expect(
        _sections(tester).first,
        'Downloads\u00A0· 7 moving\u00A0· 1 stuck',
      );
      expect(find.text('Sonarr 1 → qBittorrent'), findsWidgets);
      expect(find.text('Sonarr Anime → qBittorrent'), findsOneWidget);

      await harness.unmount(tester);
    });
  });

  group('the menu', () {});

  group('the sizes', () {
    for (final tab in ActivityTab.values) {
      for (final width in [390.0, 430.0]) {
        testWidgets('P1: ${tab.label} at 200% on a ${width.round()}pt phone '
            'draws without overflowing', (tester) async {
          final harness = await _pump(
            tester,
            Profiles.p1,
            tab,
            textScale: 2,
            size: Size(width, 12000),
          );

          expect(tester.takeException(), isNull);
          expect(find.byType(PageTabs<ActivityTab>), findsOneWidget);

          await harness.unmount(tester);
        });
      }
    }
  });

  group('with nothing to read', () {});

  group('needsYouMeta and requestsWaitLine', () {
    test('each kind counted apart, a request is not a fault', () {
      expect(
        needsYouMeta(faults: 3, requests: 2),
        '3 faults\u00A0· 2 requests',
      );
      expect(needsYouMeta(faults: 1, requests: 1), '1 fault\u00A0· 1 request');
      expect(needsYouMeta(faults: 4, requests: 0), '4 faults');
      expect(needsYouMeta(faults: 0, requests: 1), '1 request');
      expect(needsYouMeta(faults: 0, requests: 0), isEmpty);
    });

    test('violations are their own group, between faults and requests, and '
        'a floor says so', () {
      expect(
        needsYouMeta(faults: 3, requests: 2, violations: 2),
        '3 faults\u00A0· 2 violations\u00A0· 2 requests',
      );
      expect(
        needsYouMeta(faults: 0, requests: 0, violations: 1),
        '1 violation',
      );
      expect(
        needsYouMeta(
          faults: 0,
          requests: 1,
          violations: 5,
          violationsFloor: true,
        ),
        '5+ violations\u00A0· 1 request',
      );
    });

    test('the line over the waiting requests', () {
      expect(requestsWaitLine(1), '1 request waits for your approval');
      expect(requestsWaitLine(2), '2 requests wait for your approval');
      expect(requestsWaitLine(0), '0 requests wait for your approval');
    });
  });
}
