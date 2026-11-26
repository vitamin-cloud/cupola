/// An issue's routes: where each audience opens one, that it resolves from its
/// path alone, that it carries the connection it was read from, and what it
/// draws once opened.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/router.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/seerr_admin_screens.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/seerr_issue_thread_screen.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../test_helpers/settings_scope.dart';

SeerrIssue _issue(int id, {int by = 5}) => SeerrIssue.fromJson({
  'id': id,
  'issueType': 2,
  'status': 1,
  'createdAt': '2026-09-26T21:40:00Z',
  'updatedAt': '2026-09-26T21:40:00Z',
  'media': {'id': 81, 'mediaType': 'movie', 'tmdbId': 603, 'status': 5},
  'createdBy': {'id': by, 'displayName': by == 2 ? 'Anna' : 'Luca'},
  'comments': [
    {
      'id': 1,
      'message': 'The audio is in Russian.',
      'user': {'id': by, 'displayName': by == 2 ? 'Anna' : 'Luca'},
    },
  ],
});

ServiceInstance _account(String id) => ServiceInstance(
  id: id,
  service: ServiceKey.seerr,
  url: 'https://seerr.test',
  account: const SeerrAccountSignIn(
    kind: SeerrAccountKind.local,
    userId: 2,
    displayName: 'Anna',
    session: 's',
  ),
);

void main() {
  /// The real router, on a phone, with a Seerr whose issue 12 is hers or
  /// Luca's. [requester] settles the audience the way the app does: a Seerr
  /// account and nothing else.
  Future<GoRouter> open(
    WidgetTester tester,
    String at, {
    bool requester = false,
    List<String> asked = const [],
  }) async {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...await settingsScopeOverrides(
          configured: requester ? const [] : const [ServiceKey.seerr],
          customize: requester
              ? (settings) => settings.copyWithInstance(_account('seerr'))
              : null,
        ),
        homeLivePollProvider.overrideWith((ref) {}),
        homeRecoveryPollProvider.overrideWith((ref) {}),
        activityLivePollProvider.overrideWith((ref, tab) {}),
        featuredAdvancesProvider.overrideWithValue(false),
        titleLightProvider.overrideWith((ref, url) async => null),
        roleGateProvider.overrideWith(
          (ref, id) => RoleGate(
            audience: requester ? Audience.requester : Audience.operator,
            grant: requester
                ? SeerrGrant.account(
                    permissions:
                        SeerrPermission.request.value |
                        SeerrPermission.createIssues.value,
                  )
                : const SeerrGrant.apiKey(),
          ),
        ),
        mediaReportIssueProvider.overrideWith(
          (ref, source) async => _issue(source.issueId, by: requester ? 2 : 5),
        ),
      ],
    );
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = container.read(routerProvider);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    router.go(at);
    await tester.pumpAndSettle();
    return router;
  }

  SeerrIssueThreadScreen screen(WidgetTester tester) => tester
      .widget<SeerrIssueThreadScreen>(find.byType(SeerrIssueThreadScreen));

  test('the spellings carry the number and the connection', () {
    expect(ServiceRoutes.seerrIssue(12), '/stack/seerr/issues/12');
    expect(
      ServiceRoutes.seerrIssue(12, instanceId: 'seerr-2'),
      '/stack/seerr/issues/12?i=seerr-2',
    );
    expect(ServiceRoutes.requestsIssue(12), '/requests/issues/12');
    expect(
      ServiceRoutes.requestsIssue(12, instanceId: 'seerr-2'),
      '/requests/issues/12?i=seerr-2',
    );
    // A blank connection is no connection: the lens.
    expect(
      ServiceRoutes.seerrIssue(12, instanceId: ''),
      '/stack/seerr/issues/12',
    );
  });

  group('the operator', () {
    testWidgets(
      "opens it inside Seerr's Issues tab, from the path and its connection alone",
      (tester) async {
        final router = await open(tester, '/stack/seerr/issues/12?i=seerr');
        expect(router.state.uri.path, '/stack/seerr/issues/12');
        expect(screen(tester).issueId, 12);
        expect(screen(tester).connectionId, 'seerr');
        // It draws the issue, not a route name.
        expect(find.text('The audio is in Russian.'), findsOneWidget);
        expect(find.text('Resolve'), findsOneWidget);
      },
    );

    testWidgets('a link with no connection reads the lens', (tester) async {
      await open(tester, '/stack/seerr/issues/12');
      expect(screen(tester).connectionId, '');
      expect(find.text('The audio is in Russian.'), findsOneWidget);
    });

    testWidgets('a number that is not one lands on the list', (tester) async {
      final router = await open(tester, '/stack/seerr/issues/not-a-number');
      expect(router.state.uri.path, ServiceRoutes.seerrIssues);
      expect(find.byType(SeerrIssuesScreen), findsOneWidget);
      expect(find.byType(SeerrIssueThreadScreen), findsNothing);
    });

    testWidgets("has no report of his own: the requester's path sends him to "
        "Seerr's requests", (tester) async {
      final router = await open(tester, '/requests/issues/12?i=seerr');
      expect(router.state.uri.path, ServiceRoutes.seerrRequests);
      expect(find.byType(SeerrIssueThreadScreen), findsNothing);
    });

    test('a title opened from it lands under the Issues tab', () {
      expect(
        ServiceRoutes.media(
          const MediaKey.movie(603),
          from: ServiceRoutes.seerrIssue(12, instanceId: 'seerr'),
        ),
        startsWith('${ServiceRoutes.seerrIssues}/media/movie/603'),
      );
      // And the requester's, under hers.
      expect(
        ServiceRoutes.media(
          const MediaKey.movie(603),
          from: ServiceRoutes.requestsIssue(12),
        ),
        startsWith('${ServiceRoutes.requests}/media/movie/603'),
      );
    });
  });

  group('the requester', () {
    testWidgets('opens her report under her Requests tab', (tester) async {
      final router = await open(
        tester,
        '/requests/issues/12?i=seerr',
        requester: true,
      );
      expect(router.state.uri.path, '/requests/issues/12');
      expect(screen(tester).connectionId, 'seerr');
      expect(find.text('The audio is in Russian.'), findsOneWidget);
      expect(find.text('Mark as resolved'), findsOneWidget);
      expect(find.text('Resolve'), findsNothing);
    });

    testWidgets('a number that is not one lands on her requests', (
      tester,
    ) async {
      final router = await open(
        tester,
        '/requests/issues/nope',
        requester: true,
      );
      expect(router.state.uri.path, ServiceRoutes.requests);
      expect(find.byType(SeerrIssueThreadScreen), findsNothing);
    });

    testWidgets("has no control room: Seerr's room sends her Home", (
      tester,
    ) async {
      final router = await open(
        tester,
        '/stack/seerr/issues/12?i=seerr',
        requester: true,
      );
      expect(router.state.uri.path, ServiceRoutes.home);
      expect(find.byType(SeerrIssueThreadScreen), findsNothing);
    });
  });

  group('opened from a page of another tab', () {
    int tabOf(WidgetTester tester) => tester
        .widget<StatefulNavigationShell>(
          find.byType(StatefulNavigationShell).first,
        )
        .currentIndex;

    testWidgets('the operator opens an issue from another service of the '
        'Stack, and from Discover, and Back returns', (tester) async {
      for (final from in ['/stack/radarr/overview', '/discover']) {
        final router = await open(tester, from);
        final before = tabOf(tester);
        unawaited(router.push('/stack/seerr/issues/12?i=seerr'));
        await tester.pumpAndSettle();
        expect(
          find.byType(SeerrIssueThreadScreen),
          findsOneWidget,
          reason: from,
        );
        expect(tabOf(tester), before, reason: from);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.state.uri.path, from);
        expect(tabOf(tester), before, reason: from);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
