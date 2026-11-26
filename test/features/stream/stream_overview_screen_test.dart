import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_slab.dart';

import 'package:cupola/features/stream/presentation/stream_watching.dart';

import '../../test_helpers/settings_scope.dart';

/// The Overview of a media server, on both servers.
///
/// One screen parameterised by `ServiceKey`, so most of what is asserted here is
/// asserted twice, and the two cases where the servers genuinely differ (the On
/// deck rail and the Server region, both Plex-only) are asserted as *absences*
/// on Jellyfin, because an empty region there would be a claim the client never
/// made.
void main() {
  testWidgets('Jellyfin draws the regions the mobile board keeps', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin);

    expect(find.byType(ServiceKpiPeek), findsOneWidget);
    expect(
      tester
          .widgetList<SectionHeader>(find.byType(SectionHeader))
          .map((header) => header.title),
      ['Now playing', 'Continue watching', 'Recently added', 'Libraries'],
    );

    // Plex's word for the first shelf is its own.
    expect(find.text('On deck'), findsNothing);
    // And the board's other Jellyfin regions are absent rather than stubbed:
    // no `/ScheduledTasks`, no `/System/ActivityLog/Entries`.
    expect(find.text('Scheduled tasks'), findsNothing);
    expect(find.textContaining('Mb/s'), findsNothing);
  });

  testWidgets('one playback is drawn large, with what is left and the '
      'controls Jellyfin allows', (tester) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      sessions: [_session('a', 'Anna', 'Sintel')],
    );

    expect(find.byType(StreamSessionFeature), findsOneWidget);
    expect(find.byType(StreamSessionLine), findsNothing);
    expect(find.text('Anna\u00A0· Sintel'), findsOneWidget);
    expect(find.text('9\u00A0min left'), findsOneWidget);
    expect(find.byTooltip('Pause this playback'), findsOneWidget);
    expect(find.byTooltip('Send a message to this player'), findsOneWidget);
    expect(find.byTooltip('Stop this playback'), findsOneWidget);
    // The wide picture is the server's own, through its key.
    final picture = tester.widget<StreamSessionFeature>(
      find.byType(StreamSessionFeature),
    );
    expect(picture.picture?.url, contains('/Images/Backdrop/0'));
    expect(picture.picture?.headers, isNotEmpty);
    // The way to the tab that lists the playbacks.
    expect(
      tester
          .widget<SectionHeader>(
            find.widgetWithText(SectionHeader, 'Now playing'),
          )
          .semanticHint,
      'opens the Jellyfin Activity tab',
    );
  });

  testWidgets('playbacks do not overflow at an accessibility reading size', (
    tester,
  ) async {
    for (final sessions in [
      [_session('a', 'Anna', 'Sintel')],
      [_session('a', 'Giulia', 'Spring'), _session('b', 'Tom', 'Elephants')],
    ]) {
      await _pump(
        tester,
        service: ServiceKey.jellyfin,
        sessions: sessions,
        textScaleFactor: 2.0,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('a scan in progress speaks one sentence', (tester) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      libraries: [_library(name: 'Films', refreshing: true)],
    );

    // One node for the whole row, with the layout's dots read as pauses, not
    // three fragments a screen reader walks separately.
    expect(find.semantics.byLabel('Films, Movies, Scanning'), findsOneWidget);
  });

  testWidgets('a library list that never answered reads `—` and never 0', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin, failLibraries: true);

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // Never "0 libraries" over a question nobody got an answer to: the reading
    // a user would act on is the opposite one.
    expect(header.subtitle, '—');
    expect(find.textContaining('0 libraries'), findsNothing);
    // The failed region says so in its own slot…
    expect(find.byType(InlineErrorRetry), findsOneWidget);
    // …and Now playing above it still drew.
    expect(find.text('Now playing'), findsOneWidget);
  });

  testWidgets('a Jellyfin server at rest still names its rooms', (
    tester,
  ) async {
    await _pump(
      tester,
      service: ServiceKey.jellyfin,
      libraries: [
        _library(name: 'Films'),
        _library(name: 'Kids TV'),
      ],
    );

    // Nothing playing and no scan running is the *majority* state of a home
    // server, so it is the typical view of this page rather than the
    // pathological one. `getLibraries` already answered names and kinds, so
    // the region says what is on the shelf instead of only whether a broom is
    // being pushed across it.
    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Kids TV'), findsOneWidget);
    // Jellyfin exposes no per-library scan timestamp, so null means "not
    // reported" and "never scanned" at once. The region says neither.
    expect(find.textContaining('never'), findsNothing);
    // The count is still reported, because that one is free.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    expect(header.subtitle, '2 libraries');
  });

  testWidgets('a server that answered and holds nothing says so, whatever '
      'the probe is doing', (tester) async {
    // The probe still in flight (or reading offline) no longer turns an
    // answered empty shelf into "The server did not answer": the libraries
    // read throws on its own failure, so an empty list is only ever an answer.
    await _pump(tester, service: ServiceKey.jellyfin, answering: false);

    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // The empty note says it in words; a count of nothing over it would say
    // it twice (the Overview draws no `0` under a heading).
    expect(header.subtitle, isNull);
    expect(find.text('No libraries on this server'), findsOneWidget);
    expect(find.text('The server did not answer'), findsNothing);
  });

  testWidgets('a server that answered and holds nothing says so', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin);

    // The other half of the same pair: the probe landed, the server is up, and
    // an empty shelf is a fact it genuinely stated.
    final header = tester.widget<SectionHeader>(
      find.widgetWithText(SectionHeader, 'Libraries'),
    );
    // The empty note says it in words; a count of nothing over it would say
    // it twice (the Overview draws no `0` under a heading).
    expect(header.subtitle, isNull);
    expect(find.text('No libraries on this server'), findsOneWidget);
  });

  testWidgets('a server that was never set up gets its own door', (
    tester,
  ) async {
    await _pump(tester, service: ServiceKey.jellyfin, configured: false);

    final placeholder = tester.widget<NotConfiguredPlaceholder>(
      find.byType(NotConfiguredPlaceholder),
    );
    expect(placeholder.service, ServiceKey.jellyfin);
    // Nothing behind the door was built, which is the point: the client
    // providers throw "not configured", and a provider that throws is a
    // *failed* provider retrying on a backoff for a condition no waiting
    // changes. The sessions providers carry `retry: noProviderRetry` precisely
    // so a dark server is not hammered; reaching them here would undo it.
    expect(find.byType(SectionHeader), findsNothing);
  });
}

// ─── Harness ────────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required ServiceKey service,
  List<StreamLibrary> libraries = const [],
  List<StreamSession> sessions = const [],
  List<StreamItem> onDeck = const [],
  bool failLibraries = false,
  bool configured = true,
  bool answering = true,
  double textScaleFactor = 1.0,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 3200));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final settings = configured
      ? (service == ServiceKey.jellyfin
            ? settingsWith(
                jellyfinUrl: 'http://jelly.lan:8096',
                jellyfinApiKey: 'key',
                jellyfinUserId: 'viewer-1',
              )
            : settingsWith())
      : const SettingsModel();

  await tester.pumpWidget(
    ProviderScope(
      // Riverpod 3 re-runs a failed provider on an exponential backoff, so one
      // `pumpAndSettle` would otherwise watch a deliberately failing region
      // retry a dozen times and never settle.
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings),
        // Both sessions providers: the page reads one of them, and overriding
        // the other costs nothing while keeping the harness symmetrical.
        jellyfinSessionsProvider.overrideWith((ref) async => sessions),
        jellyfinLibrariesProvider.overrideWith((ref) async {
          if (failLibraries) throw Exception('libraries failed');
          return libraries;
        }),
        streamWatchingProvider.overrideWith(
          (ref, key) async => switch (key.shelf) {
            StreamWatchingShelf.continueWatching => onDeck,
            _ => const <StreamItem>[],
          },
        ),
        // The reachability probe the identity line reads.
        serviceSummaryProvider.overrideWith(
          (ref, key) async => ServiceSummary(
            service: key,
            status: answering
                ? ServiceSummaryStatus.online
                : ServiceSummaryStatus.offline,
            host: 'media.lan',
            version: answering ? '10.10.6' : null,
          ),
        ),
        // The readout rail is not what these tests are about, and it reads the
        // sessions and libraries through providers of its own.
        serviceKpiProvider.overrideWith(
          (ref, key) async => const <ServiceKpi>[],
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: StreamOverviewScreen(service: service, topPadding: 0),
      ),
    ),
  );
  if (sessions.isEmpty) {
    await tester.pumpAndSettle();
    return;
  }
  // A playback's picture shimmers while it loads, for as long as it loads.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

StreamSession _session(String id, String user, String title) => StreamSession(
  id: id,
  userName: user,
  title: title,
  subtitle: null,
  deviceLabel: 'Living room TV',
  posterPath: '/Items/$id/Images/Primary',
  backdropPath: '/Items/$id/Images/Backdrop/0',
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.5,
  isPaused: false,
  remaining: const Duration(minutes: 9),
);

StreamLibrary _library({
  required String name,
  bool refreshing = false,
  DateTime? scannedAt,
}) => StreamLibrary(
  id: name,
  name: name,
  kind: StreamLibraryKind.movies,
  itemCount: null,
  lastScannedAt: scannedAt,
  isRefreshing: refreshing,
);
