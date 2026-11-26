import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_watching.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_tab_screens.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _configured = const SettingsModel().copyWithService(
  ServiceKey.jellyfin,
  url: 'https://jellyfin.test',
  apiKey: 'key',
);

void main() {
  testWidgets('activity reuses the live-session idle state', (tester) async {
    await _pump(
      tester,
      screen: const JellyfinActivityScreen(),
      overrides: [
        jellyfinSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith((ref, key) async => const []),
      ],
    );

    expect(find.text('Now playing'), findsOneWidget);
    expect(find.text('Nobody is watching right now'), findsOneWidget);
  });

  testWidgets('activity draws what is in progress, up next and added under '
      'Now playing, and asks whose watch state when nobody is chosen', (
    tester,
  ) async {
    await _pump(
      tester,
      screen: const JellyfinActivityScreen(),
      overrides: [
        jellyfinSessionsProvider.overrideWith((ref) async => const []),
        streamWatchingProvider.overrideWith(
          (ref, key) async => switch (key.shelf) {
            StreamWatchingShelf.recentlyAdded => const [
              StreamItem(
                id: 'jf-1',
                title: 'Sintel',
                subtitle: null,
                kind: StreamItemKind.movie,
                posterPath: null,
                year: 2010,
                runtimeMs: 888000,
                isPlayed: false,
                resumeOffsetMs: null,
                unplayedChildCount: null,
              ),
            ],
            _ => throw const JellyfinViewerRequired(),
          },
        ),
      ],
    );

    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Next up'), findsOneWidget);
    // A watch state with nobody to read it for is a question, not a fault.
    expect(find.text('Choose whose watch state to show'), findsNWidgets(2));
    expect(find.byType(InlineErrorRetry), findsNothing);
    // The page's own list, not the grid inside it.
    final page = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Recently added'),
      200,
      scrollable: page,
    );
    await tester.scrollUntilVisible(
      find.bySemanticsLabel('Sintel'),
      200,
      scrollable: page,
    );
    expect(find.bySemanticsLabel('Sintel'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  SettingsModel? settings,
  List<Override> overrides = const [],
  double textScaleFactor = 1,
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        currentSettingsProvider.overrideWith((ref) => settings ?? _configured),
        ...overrides,
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScaleFactor)),
          child: child!,
        ),
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
