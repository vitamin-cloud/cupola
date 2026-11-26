/// A household member's Jellyfin token, read the same way on every surface,
/// per connection.
///
/// A non-administrator's token plays, browses and controls its own sessions,
/// and is refused the elevated reads: `/Users`, `/Devices`, `/ScheduledTasks`
/// and `/Library/VirtualFolders`. Devices, Tasks and Libraries said so
/// calmly; Users drew the refusal as a fault, the Overview's Libraries region
/// did too, the viewer picker said the server reports no users, the
/// connection test said the token was refused, and Activity read every
/// connection without saying which ones show only their own playback. The credential kind was the lens's alone. It is now asked per
/// connection and read wherever an elevated read is made.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_overview_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/jellyfin_viewer_picker.dart';

import '../../test_helpers/profiles/profiles.dart';

const _ownPlayback = 'Showing only this account\'s playback';

Future<ProfileHarness> _pump(
  WidgetTester tester,
  ConfigProfile profile,
  Widget child,
) async {
  final harness = await ProfileHarness.start(profile);
  await tester.binding.setSurfaceSize(const Size(430, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: child),
    ),
  );
  await harness.settle(tester);
  return harness;
}

void main() {
  group('the credential kind, per connection', () {});

  group('P2+J, Anna\'s own token', () {
    test(
      'the connection test accepts it, as the Dashboard\'s probe does',
      () async {
        final harness = await ProfileHarness.start(Profiles.p2WithJellyfin);
        final diagnosis = await harness
            .container(retry: (_, _) => null)
            .read(instanceDiagnosisProvider(WorldIds.jellyfin).future);

        expect(diagnosis.status, ServiceConnectionStatus.connected);
      },
    );

    testWidgets('the viewer picker offers the token\'s own person', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const Scaffold(
          body: JellyfinViewerPicker(instanceId: WorldIds.jellyfin),
        ),
      );

      expect(find.widgetWithText(ChoiceChip, WorldPeople.anna), findsOneWidget);
      expect(find.text('This server reports no users.'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('the Overview says the one Jellyfin shows only her playback', (
      tester,
    ) async {
      final harness = await _pump(
        tester,
        Profiles.p2WithJellyfin,
        const Scaffold(
          body: StreamOverviewScreen(service: ServiceKey.jellyfin),
        ),
      );

      expect(find.text(_ownPlayback), findsOneWidget);
      expect(
        find.text('Other people\'s sessions need an administrator to see.'),
        findsOneWidget,
      );
      await harness.unmount(tester);
    });
  });
}
