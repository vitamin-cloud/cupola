/// Movies, Series and Authors in selection mode over the profiles' arrs: the
/// app's own services, providers and walls, and a network that answers as the
/// arrs do. What is asserted is what each arr was asked and what the wall then
/// says, in its own nouns.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/movies/presentation/movies_screen.dart';
import 'package:cupola/features/series/presentation/series_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

Future<ProfileHarness> _open(
  WidgetTester tester,
  ConfigProfile profile,
  Widget screen,
) async {
  final harness = await ProfileHarness.start(profile);
  harness.network.live();
  harness.network.followFakeTime(tester.binding);
  tester.view
    ..physicalSize = const Size(390, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: harness.overrides,
      child: MaterialApp(theme: AppTheme.darkTheme(), home: screen),
    ),
  );
  await harness.settle(tester);
  return harness;
}

List<NetworkRequest> _writes(ProfileHarness harness, String id) => [
  for (final request in harness.network.requestsTo(id))
    if (request.method != 'GET') request,
];

/// Enters selection with `Select` and takes everything the wall shows.
Future<void> _selectAll(WidgetTester tester, ProfileHarness harness) async {
  await tester.tap(find.text('Select'));
  await harness.settle(tester);
  await tester.tap(find.textContaining('Select all'));
  await harness.settle(tester);
}

void main() {
  testWidgets('Movies: Select is offered, the bar counts movies, and Monitor '
      'is one edit of what is selected', (tester) async {
    final harness = await _open(tester, Profiles.p1, const MoviesScreen());
    expect(find.text('Select'), findsOneWidget);

    await _selectAll(tester, harness);
    expect(
      find.bySemanticsLabel(RegExp(r'^[\d,]+ movies? selected$')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('library-selection-monitor')));
    await harness.settle(tester);
    expect(find.textContaining('Monitor new'), findsNothing);
    await tester.tap(find.text('Stop monitoring'));
    await harness.settle(tester);
    await tester.tap(find.textContaining('Apply to'));
    await harness.settle(tester);

    final edits = _writes(harness, WorldIds.radarr);
    expect(edits, hasLength(1));
    expect(edits.single.path, '/api/v3/movie/editor');
    expect((edits.single.json as Map)['monitored'], isFalse);
    expect(find.textContaining('Updated'), findsOneWidget);

    await harness.unmount(tester);
  });

  testWidgets('Series: nothing selected says `Select a series first`, and '
      'Monitor has `Monitor new seasons`', (tester) async {
    final harness = await _open(tester, Profiles.p1, const SeriesScreen());
    await tester.tap(find.text('Select'));
    await harness.settle(tester);

    await tester.tap(find.byKey(const ValueKey('library-selection-search')));
    await tester.pump();
    expect(find.text('Select a series first'), findsOneWidget);

    await tester.tap(find.textContaining('Select all'));
    await harness.settle(tester);
    await tester.tap(find.byKey(const ValueKey('library-selection-monitor')));
    await harness.settle(tester);
    expect(find.text('Monitor new seasons'), findsOneWidget);
    await tester.tap(find.text('None'));
    await harness.settle(tester);
    await tester.tap(find.textContaining('Apply to'));
    await harness.settle(tester);

    final edits = _writes(harness, WorldIds.sonarr);
    expect(edits.single.path, '/api/v3/series/editor');
    expect((edits.single.json as Map)['monitorNewItems'], 'none');

    await harness.unmount(tester);
  });
}
