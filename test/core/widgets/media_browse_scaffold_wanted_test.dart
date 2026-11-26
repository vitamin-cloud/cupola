import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _query = StateProvider<String>((ref) => '');

const _titles = ['Anton Bruckner', 'Bill Evans', 'Brian Eno', 'Clara Schumann'];

Widget _wall({
  MediaBrowseWanted? wanted,
  List<String> titles = _titles,
  Set<int>? cutoff = const {},
}) {
  final library = FutureProvider<List<String>>((ref) async => titles);
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: MediaBrowseScaffold<String>(
        title: 'Music',
        searchHint: 'Search',
        activityRoute: '/activity',
        navigationSection: NavigationSection.stack,
        serviceName: 'Lidarr',
        heroTagPrefix: 'artist',
        libraryProvider: library,
        searchQueryProvider: _query,
        find: MediaFind.libraryOnly(
          libraryBody: (context, query) => Text('find:$query'),
        ),
        titleExtractor: (title) => title,
        subtitleExtractor: (_) => '6 albums',
        imagesExtractor: (_) => null,
        idExtractor: (title) => title.hashCode,
        // Every artist is "available": Missing would find none of them, which
        // is the case the Wanted chip exists for.
        statusExtractor: (_) =>
            const MediaStatusInfo(availability: MediaAvailability.available),
        settingsSelector: (_) => ('', '', const NoAccess()),
        onItemTap: (_, _, _) {},
        tileShape: MediaBrowseTileShape.circle,
        cutoffUnmetIds: cutoff,
        wanted: wanted,
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget wall) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(wall);
  await tester.pumpAndSettle();
}

/// The chips, left to right.
List<String> _chips(WidgetTester tester) {
  final labels = [
    for (final label in const [
      'All',
      'Available',
      'Missing',
      'Wanted',
      'In queue',
      'Cutoff unmet',
      'Unmonitored',
    ])
      if (find.text(label).evaluate().isNotEmpty) label,
  ];
  labels.sort(
    (a, b) => tester
        .getTopLeft(find.text(a))
        .dx
        .compareTo(tester.getTopLeft(find.text(b)).dx),
  );
  return labels;
}

void main() {
  group('the chips', () {
    testWidgets('every other wall keeps Missing and has no Wanted', (
      tester,
    ) async {
      await _pump(tester, _wall());

      expect(_chips(tester), [
        'All',
        'Available',
        'Missing',
        'In queue',
        'Cutoff unmet',
        'Unmonitored',
      ]);
      expect(find.text('Wanted'), findsNothing);
    });
  });

  group('under the Wanted chip', () {});

  group('while the answer is out or failed', () {});
}
