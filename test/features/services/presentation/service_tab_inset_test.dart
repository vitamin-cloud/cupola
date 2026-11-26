import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/list_rows_shimmer.dart';
import 'package:cupola/core/widgets/search_bar_header.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/activity/presentation/widgets/requests_board.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/arr_calendar_screen.dart';
import 'package:cupola/features/activity/presentation/arr_tab_screen.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_screen.dart';
import 'package:cupola/features/dockge/presentation/dockge_terminal_screen.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_provider.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_rss_screen.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_screen.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_all_screens.dart';
import 'package:cupola/features/services/presentation/service_home_screen.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/service_tab_scaffold.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/settings_scope.dart';

/// What the router hands every hosted tab screen as `topPadding`: the service
/// band plus the tab bar, **without** the phone's top inset. Mirrored here
/// because the router's own constant is private.
const double _hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

/// An iPhone 17 Pro in portrait, the surface the defect was seen on.
const Size _phone = Size(402, 874);
const double _statusBar = 62;

/// The tabs of a service room on a notched phone: the band, the tab bar under
/// it, and the tab's own screen under both.
///
/// **The bar is placed an inset below `kToolbarHeight`**, because the band
/// consumes the inset (see `ServiceHomeScreen.bandHeightOf`). A hosted screen
/// is handed the bare chrome height, so it is the screen's job to add the
/// inset, through a `SafeArea` or through `MediaQuery`. A test surface with no
/// inset cannot tell a screen that does from one that does not, which is how a
/// tab's first row sat under the bar until someone looked at a real iPhone.
void main() {
  /// The phone, with its notch. Set on the view rather than wrapped around the
  /// app, so the `MediaQuery` every widget reads is the one a device builds.
  void usePhone(WidgetTester tester) {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = _phone
      ..padding = const FakeViewPadding(top: _statusBar)
      ..viewPadding = const FakeViewPadding(top: _statusBar);
    addTearDown(tester.view.reset);
  }

  Future<void> pumpHosted(
    WidgetTester tester, {
    required ServiceKey service,
    required ServiceTab tab,
    required Widget child,
    List<Override> overrides = const [],
    bool phone = true,
  }) async {
    if (phone) usePhone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: [service]),
          ...overrides,
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: ServiceHomeScreen(
              service: service,
              child: ServiceTabScaffold(
                service: service,
                tab: tab,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Where the tab bar ends: the line no hosted content may start above.
  double barBottom(WidgetTester tester) => tester
      .getRect(
        find.ancestor(
          of: find.byType(ServiceTabBar),
          matching: find.byType(GlassSurface),
        ),
      )
      .bottom;

  void expectClearsTheBar(WidgetTester tester, Finder content) {
    expect(content, findsWidgets);
    expect(
      tester.getTopLeft(content.first).dy,
      greaterThanOrEqualTo(barBottom(tester)),
      reason: 'the first content starts under the tab bar',
    );
  }

  group('the phone the cases run on', () {
    testWidgets('has a status bar, and the bar sits an inset below the band', (
      tester,
    ) async {
      // The fixture itself, asserted: if the inset ever stopped reaching the
      // tree, every case below would pass for the wrong reason.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        child: const SizedBox.expand(),
      );

      expect(
        MediaQuery.paddingOf(tester.element(find.byType(ServiceTabBar))).top,
        _statusBar,
      );
      expect(
        barBottom(tester),
        _statusBar + kToolbarHeight + ServiceTabBar.height,
      );
      expect(barBottom(tester), _statusBar + _hostedTopPadding);
    });
  });

  group('ArrTabScreen clears the glass bars', () {
    final overrides = <Override>[
      radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
    ];

    testWidgets('an empty queue starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('Queue is empty'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
      // The picture the user reported: the icon, not just the well around it.
      expectClearsTheBar(tester, find.byIcon(Icons.download_done_rounded));
    });

    testWidgets('an empty history starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.history,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.history,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.text('No history yet'), findsOneWidget);
      expectClearsTheBar(tester, find.byType(AppEmptyState));
    });

    testWidgets('Wanted draws its pills below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.wanted,
        overrides: overrides,
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.wanted,
          topPadding: _hostedTopPadding,
        ),
      );

      // The pills are Wanted's first row: missing against cutoff unmet.
      expectClearsTheBar(tester, find.text('Missing'));
    });

    testWidgets('a queue still loading starts below the tab bar', (
      tester,
    ) async {
      // Not the empty state: the skeleton is the first thing every tab shows,
      // and it rides the same padding.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.queue,
        overrides: [
          radarrServiceProvider.overrideWith((ref) => _NeverAnswers()),
        ],
        child: const ArrTabScreen(
          serviceType: ServiceType.movies,
          mode: ArrTabMode.queue,
          topPadding: _hostedTopPadding,
        ),
      );

      expect(find.byType(AppEmptyState), findsNothing);
      expectClearsTheBar(tester, find.byType(ShimmerList));
    });
  });

  group('ServiceOverviewPage clears the glass bars', () {
    // The one page every Overview but Stream's is: its body is a `SafeArea`
    // that takes the status bar's inset and hands `topPadding` to the scroll
    // view, so a first region starts below the tab bar on a notched phone.
    // The guard excuses each `*OverviewScreen` by leaning on this case.
    testWidgets('the first region starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.overview,
        overrides: [
          serviceSummaryProvider(
            ServiceKey.radarr,
          ).overrideWith((ref) => Completer<ServiceSummary>().future),
        ],
        child: ServiceOverviewPage(
          service: ServiceKey.radarr,
          topPadding: _hostedTopPadding,
          kpis: (ref) => const AsyncData(<ServiceKpi>[]),
          refresh: (ref) {},
          sections: (ref) => const [Text('First region')],
        ),
      );

      expectClearsTheBar(tester, find.byType(ServiceOverviewIdentity));
      expectClearsTheBar(tester, find.text('First region'));
    });
  });

  group('on a desktop window the inset adds nothing', () {
    testWidgets('an empty queue still sits right under the tab row', (
      tester,
    ) async {
      // A desktop window has no status bar, so the inset the fix adds is zero
      // there and the hosted screen lands exactly where it did: the phone's
      // band and bar reserved, and the screen lifted by the band the window
      // does not draw.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        tester.view
          ..devicePixelRatio = 1
          ..physicalSize = const Size(1200, 800);
        addTearDown(tester.view.reset);

        await pumpHosted(
          tester,
          service: ServiceKey.radarr,
          tab: ServiceTab.queue,
          phone: false,
          overrides: [
            radarrServiceProvider.overrideWith((ref) => FakeRadarrService()),
          ],
          child: const ArrTabScreen(
            serviceType: ServiceType.movies,
            mode: ArrTabMode.queue,
            topPadding: _hostedTopPadding,
          ),
        );

        expect(find.text('Queue is empty'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(AppEmptyState)).dy,
          ServiceTabBar.height,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Prowlarr tabs clear the glass bars', () {});

  group('The download clients\' tabs clear the glass bars', () {
    testWidgets('qBittorrent RSS starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.qbittorrent,
        tab: ServiceTab.rss,
        overrides: [
          qbittorrentRssFeedsProvider.overrideWith((ref) => _pending()),
          qbittorrentRssRulesProvider.overrideWith((ref) => _pending()),
        ],
        child: const QbittorrentRssScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });
  });

  // These five pages wrapped their body in a `SafeArea` that took the top inset
  // only when they drew an app bar of their own, and hosted they draw none.
  group('The pages that skipped the status bar clear the glass bars', () {
    testWidgets('Dockge Stacks starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.dockge,
        tab: ServiceTab.stacks,
        overrides: [
          dockgeStackListProvider.overrideWith(
            (ref) => const Stream<List<DockgeStack>>.empty(),
          ),
          serviceKpiProvider(
            ServiceKey.dockge,
          ).overrideWith((ref) => _pending()),
        ],
        child: const DockgeScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ServiceKpiPeek));
    });

    testWidgets('Dockge Terminal starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.dockge,
        tab: ServiceTab.terminal,
        overrides: [
          dockgeStackListProvider.overrideWith(
            (ref) => const Stream<List<DockgeStack>>.empty(),
          ),
        ],
        child: const DockgeTerminalScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(SectionHeader));
    });
  });

  group('ServiceListPage takes the inset itself', () {});

  // These pages put the room the bands take, and the inset, into their own
  // header or list padding rather than into a `SafeArea`.
  group('The library, calendar and request tabs clear the glass bars', () {
    testWidgets('Radarr Library starts below the tab bar', (tester) async {
      // The shared browse scaffold, which Sonarr's and Lidarr's libraries
      // hand their room to unchanged.
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.library,
        overrides: [moviesProvider.overrideWith((ref) => _pending())],
        child: const MoviesScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(SearchBarHeader));
    });

    testWidgets('a Calendar still loading starts below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.radarr,
        tab: ServiceTab.calendar,
        overrides: [
          calendarSourceProvider.overrideWith((ref, key) => _pending()),
        ],
        child: const ArrCalendarScreen(
          service: ServiceKey.radarr,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(ShimmerList));
    });

    testWidgets('qBittorrent Queue draws its figures below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.qbittorrent,
        tab: ServiceTab.queue,
        overrides: [
          torrentsProvider.overrideWith((ref) => _pending()),
          torrentPollingProvider.overrideWith((ref) {}),
          serviceKpiProvider(
            ServiceKey.qbittorrent,
          ).overrideWith((ref) => _pending()),
        ],
        child: const QbittorrentScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ServiceKpiPeek));
    });

    testWidgets('Seerr Requests starts its list below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.requests,
        overrides: [requestsProvider.overrideWith((ref) => _pending())],
        child: const ServiceAllRequestsScreen(
          showAppBar: false,
          topPadding: _hostedTopPadding,
        ),
      );

      expectClearsTheBar(tester, find.byType(RequestsBoard));
    });

    testWidgets('Seerr Issues draws its filter pills below the tab bar', (
      tester,
    ) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.issues,
        overrides: [
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          seerrIssuesProvider.overrideWith((ref, filter) => _pending()),
        ],
        child: const SeerrIssuesScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, _selectionPills);
    });

    testWidgets('Seerr Users starts below the tab bar', (tester) async {
      await pumpHosted(
        tester,
        service: ServiceKey.seerr,
        tab: ServiceTab.users,
        overrides: [
          seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
          seerrUsersProvider.overrideWith((ref) => _pending()),
        ],
        child: const SeerrUsersScreen(topPadding: _hostedTopPadding),
      );

      expectClearsTheBar(tester, find.byType(ListRowsShimmer));
    });

    testWidgets(
      'an account that may not manage users reads why below the bar',
      (tester) async {
        await pumpHosted(
          tester,
          service: ServiceKey.seerr,
          tab: ServiceTab.users,
          overrides: [
            seerrServiceProvider.overrideWith((ref) => FakeSeerrService()),
            roleGateProvider('').overrideWithValue(
              const RoleGate(
                audience: Audience.operator,
                grant: SeerrGrant.account(permissions: 0),
              ),
            ),
          ],
          child: const SeerrUsersScreen(topPadding: _hostedTopPadding),
        );

        expect(find.byType(ListRowsShimmer), findsNothing);
        expectClearsTheBar(tester, find.byType(AppEmptyState));
      },
    );
  });

  group('The media servers\' tabs clear the glass bars', () {});
}

/// A Radarr that never answers its queue, so the screen stays on its skeleton.
class _NeverAnswers extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({Map<String, dynamic>? queryParameters}) =>
      Completer<List<dynamic>>().future;
}

/// The filter pills a screen leads with. `SelectionPills` is generic over a
/// screen's private enum, so it can only be found by its name.
final _selectionPills = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString().startsWith('SelectionPills'),
  description: 'SelectionPills',
);

/// A read that never answers, so a screen stays on its loading state.
Future<T> _pending<T>() => Completer<T>().future;
