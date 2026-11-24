/// Something other than the service answers at its address, and the app says
/// so: on the Stack, on the service's library and in its connection test.
///
/// The case behind "Radarr and Sonarr answering, with empty libraries": a web
/// page (a proxy's default page, an address missing its base path) answered
/// every request with a 200, the probe called any 2xx answering, and every
/// list read turned the page into `[]`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_offline_state.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/music/presentation/music_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ServiceSummary> _probe(
  ConfigProfile profile,
  ServiceKey service,
  String id,
) async {
  final harness = await ProfileHarness.start(profile);
  final container = harness.container(retry: (_, _) => null);
  return container.read(
    instanceSummaryProvider((service: service, instanceId: id)).future,
  );
}

/// What the connection test says about [id] on [profile].
Future<ServiceDiagnosis> _test(ConfigProfile profile, String id) async {
  await ProfileHarness.start(profile);
  return diagnoseInstance(
    profile.connection(id).instance,
    profile.settings,
    route: ConnectionRoute.home,
  );
}

Color _amber() {
  final scheme = AppTheme.darkTheme().colorScheme;
  return statusToneColor(scheme, StatusTone.warning);
}

void main() {
  group('a web page answering for an arr', () {
    test('is a fault on the probe, never answering', () async {
      final summary = await _probe(
        Profiles.p1.withBehaviour(
          WorldIds.radarr,
          ConnectionBehaviour.servesHtmlPage,
        ),
        ServiceKey.radarr,
        WorldIds.radarr,
      );

      expect(summary.isOnline, isFalse);
      expect(summary.status, ServiceSummaryStatus.fault);
    });

    final libraries = <(String, ServiceKey, String, String, Widget)>[
      (
        'Radarr',
        ServiceKey.radarr,
        WorldIds.radarr,
        'nas.home.arpa:7878',
        const MoviesScreen(showAppBar: false),
      ),
      (
        'Sonarr',
        ServiceKey.sonarr,
        WorldIds.sonarr,
        'nas.home.arpa:8989',
        const SeriesScreen(showAppBar: false),
      ),
      (
        'Lidarr',
        ServiceKey.lidarr,
        WorldIds.lidarr,
        'nas.home.arpa:8686',
        const MusicScreen(showAppBar: false),
      ),
    ];

    for (final (name, _, id, host, screen) in libraries) {
      testWidgets('the $name library says what answered, not that it is '
          'empty', (tester) async {
        final harness = await pumpWithProfile(
          tester,
          Profiles.p1.withBehaviour(id, ConnectionBehaviour.servesHtmlPage),
          child: screen,
        );

        expect(find.byType(ServiceOfflineState), findsOneWidget);
        expect(find.text('$name is not at this address'), findsOneWidget);
        expect(find.textContaining('library is empty'), findsNothing);
        final glyph = tester.widget<Icon>(
          find
              .descendant(
                of: find.byType(ServiceOfflineState),
                matching: find.byType(Icon),
              )
              .first,
        );
        expect(glyph.color, _amber());
        expect(
          find.text(
            'A web page answered at $host instead of $name.\n'
            'If $name sits under a path, add it: http://$host/'
            '${name.toLowerCase()}',
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(FilledButton, 'Check the address'),
          findsOneWidget,
        );

        await harness.unmount(tester);
      });
    }

    testWidgets('Home, Settings and the library say one thing about it', (
      tester,
    ) async {
      final profile = Profiles.p1.withBehaviour(
        WorldIds.radarr,
        ConnectionBehaviour.servesHtmlPage,
      );
      final harness = await pumpWithProfile(
        tester,
        profile,
        child: const MoviesScreen(showAppBar: false),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MoviesScreen)),
      );
      // Asked in real time: the probe and the test run their own deadlines.
      final (summary, diagnosis) = (await tester.runAsync(
        () async => (
          await container.read(
            instanceSummaryProvider((
              service: ServiceKey.radarr,
              instanceId: WorldIds.radarr,
            )).future,
          ),
          await diagnoseInstance(
            profile.connection(WorldIds.radarr).instance,
            profile.settings,
            route: ConnectionRoute.home,
          ),
        ),
      ))!;

      final home = describeFailureOf(ServiceKey.radarr, summary.failure);
      final settings = describeConnection(
        ServiceKey.radarr,
        status: diagnosis.status,
        reason: diagnosis.reason,
        gateway: diagnosis.gateway,
      );
      const sentence =
          'A web page answered at nas.home.arpa:7878 instead of Radarr.\n'
          'If Radarr sits under a path, add it: http://nas.home.arpa:7878/radarr';

      // Home: the summary's own words.
      expect(home.headline, 'Radarr is not at this address');
      expect(home.label, 'API not at this address');
      expect(home.remedy, 'Check the address');
      expect(failureMessageOf(ServiceKey.radarr, summary.failure), sentence);
      // Settings: the same label and sentence.
      expect(settings.label, home.label);
      expect(diagnosis.messageFor(ServiceKey.radarr), sentence);
      // The library: the same headline, sentence and remedy on screen.
      expect(find.text(home.headline), findsOneWidget);
      expect(find.text(sentence), findsOneWidget);
      expect(find.widgetWithText(FilledButton, home.remedy!), findsOneWidget);

      await harness.unmount(tester);
    });

    test('a body that is not a page and does not decode is unreadable, on '
        'Home and in Settings alike', () async {
      final harness = await ProfileHarness.start(Profiles.p1);
      harness.network.on(
        WorldIds.radarr,
        'GET',
        '/api/v3/system/status',
        (_) => NetworkReply.text('{"appName": "Radarr", "vers'),
      );
      final container = harness.container(retry: (_, _) => null);
      final summary = await container.read(
        instanceSummaryProvider((
          service: ServiceKey.radarr,
          instanceId: WorldIds.radarr,
        )).future,
      );
      final diagnosis = await diagnoseInstance(
        Profiles.p1.connection(WorldIds.radarr).instance,
        Profiles.p1.settings,
        route: ConnectionRoute.home,
      );

      expect(summary.failureReason, ServiceFailureReason.invalidResponse);
      expect(
        describeFailureOf(ServiceKey.radarr, summary.failure).headline,
        describeUnreadable(ServiceKey.radarr),
      );
      expect(diagnosis.reason, ServiceFailureReason.invalidResponse);
      expect(
        diagnosis.messageFor(ServiceKey.radarr),
        failureMessageOf(ServiceKey.radarr, summary.failure),
      );
    });
  });

  group('SABnzbd\'s lists are a fault, not empty, when SABnzbd did not '
      'answer them', () {
    Future<Object> failureOf(
      ConfigProfile profile,
      ProviderListenable<Future<Object?>> provider, {
      void Function(ProfileNetwork network)? routes,
    }) async {
      final harness = await ProfileHarness.start(profile);
      routes?.call(harness.network);
      final container = harness.container(retry: (_, _) => null);
      try {
        await container.read(provider);
      } catch (error) {
        return error;
      }
      fail('expected the read to fail');
    }



  });


}

/// The headline the classification gives an answer nobody can read.
String describeUnreadable(ServiceKey service) => failureHeadline(
  ServiceFailureReason.invalidResponse,
  subject: service.title,
);
