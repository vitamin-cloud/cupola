/// The library wall in selection mode: how it is entered and left, what it
/// shows while it lasts, where its bar stands, and what an action that some
/// titles refused leaves behind.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/count_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _query = StateProvider<String>((ref) => '');

const _titles = ['Anton Bruckner', 'Bill Evans', 'Brian Eno', 'Clara Schumann'];

int _id(String title) => title.hashCode;

/// What a test learns of the actions it ran.
class _Asked {
  /// The titles each run was for, in the order they ran.
  final runs = <List<String>>[];

  /// The titles Remove was asked about, in the order it was.
  final removing = <List<String>>[];

  /// How many times an action asked what it needed.
  var prepared = 0;

  /// What the library said changed.
  var changed = 0;

  /// What reading the library again does, when a test makes it matter.
  void Function(WidgetRef ref)? reread;
}

MediaBulkFailure _refused(String title) => MediaBulkFailure(
  id: _id(title),
  name: title,
  line: 'Lidarr refused $title: the folder is not reachable.',
  error: DioException(
    requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
    response: Response(
      requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
      statusCode: 400,
    ),
    type: DioExceptionType.badResponse,
  ),
);

/// Search and Remove over [_titles], answering with [outcome].
MediaBulk<String> _bulk(
  _Asked asked, {
  Future<MediaBulkOutcome> Function(List<String> titles)? outcome,
  String instanceId = 'lidarr-one',
  bool removeRuns = false,
}) {
  Future<MediaBulkOutcome> whole(List<String> titles) async =>
      MediaBulkOutcome(done: [for (final title in titles) _id(title)]);
  return MediaBulk<String>(
    singular: 'artist',
    plural: 'artists',
    noneHint: 'Select an artist first',
    service: ServiceKey.sonarr,
    instanceId: instanceId,
    onChanged: (ref) {
      asked.changed++;
      asked.reread?.call(ref);
    },
    actions: [
      MediaBulkAction<String>(
        label: 'Search',
        icon: Icons.search_rounded,
        prepare: (context, titles) async {
          asked.prepared++;
          return MediaBulkJob<String>(
            run: (items) {
              asked.runs.add(items);
              return (outcome ?? whole)(items);
            },
            doneLine: (count) => 'Searching $count',
            partialLine: (done, total) => '$done of $total artists updated',
          );
        },
      ),
      MediaBulkAction<String>(
        label: 'Remove',
        icon: Icons.delete_outline_rounded,
        shownOnly: true,
        // Backs out of what it asks, unless the test lets it run.
        prepare: (context, titles) async {
          asked.prepared++;
          asked.removing.add(titles);
          if (!removeRuns) return null;
          return MediaBulkJob<String>(
            run: (items) async =>
                MediaBulkOutcome(done: [for (final title in items) _id(title)]),
            doneLine: (count) => 'Removed $count',
            partialLine: (done, total) => '$done of $total removed',
          );
        },
      ),
    ],
  );
}

Widget _wall({
  MediaBulk<String>? bulk,
  List<String> titles = _titles,
  MediaStatusInfo Function(String title)? status,
  bool peek = false,
  FutureProvider<List<String>>? library,
  Map<String, int> ids = const {},
}) {
  library ??= FutureProvider<List<String>>((ref) async => titles);
  return MediaBrowseScaffold<String>(
    title: 'Music',
    searchHint: 'Search',
    activityRoute: '/activity',
    navigationSection: NavigationSection.stack,
    serviceName: 'Lidarr',
    service: ServiceKey.sonarr,
    heroTagPrefix: 'artist',
    libraryProvider: library,
    searchQueryProvider: _query,
    find: MediaFind.libraryOnly(
      libraryBody: (context, query) => Text('find:$query'),
    ),
    titleExtractor: (title) => title,
    subtitleExtractor: (_) => '6 albums',
    imagesExtractor: (_) => null,
    idExtractor: (title) => ids[title] ?? _id(title),
    statusExtractor: status,
    settingsSelector: (_) => ('', '', const NoAccess()),
    onItemTap: (_, _, _) {},
    tileShape: MediaBrowseTileShape.circle,
    bulk: bulk,
    kpiPeek: peek ? const Text('the peek') : null,
  );
}

Widget _app(Widget home) => ProviderScope(
  overrides: [
    currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
  ],
  child: MaterialApp(theme: AppTheme.darkTheme(), home: home),
);

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(home));
  await tester.pumpAndSettle();
}

/// The phone's shell, as the app builds it: the wall over the floating
/// navigation bar, which steps down while the wall selects.
class _Shell extends StatelessWidget {
  const _Shell({
    required this.controller,
    required this.wall,
    required this.tapped,
  });

  final LibrarySelectionController controller;
  final Widget wall;
  final List<int> tapped;

  @override
  Widget build(BuildContext context) => LibrarySelectionScope(
    controller: controller,
    child: Scaffold(
      extendBody: true,
      body: wall,
      bottomNavigationBar: LibrarySelectionNavSlot(
        child: FloatingBottomNavBar(
          selectedIndex: 3,
          onDestinationSelected: tapped.add,
          destinations: const [
            FloatingNavDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Home',
            ),
            FloatingNavDestination(
              icon: Icons.explore_outlined,
              selectedIcon: Icons.explore_rounded,
              label: 'Discover',
            ),
            FloatingNavDestination(
              icon: Icons.monitor_heart_outlined,
              selectedIcon: Icons.monitor_heart_rounded,
              label: 'Activity',
            ),
            FloatingNavDestination(
              icon: Icons.layers_outlined,
              selectedIcon: Icons.layers_rounded,
              label: 'Stack',
            ),
          ],
        ),
      ),
    ),
  );
}

final _navSurface = find.byKey(const ValueKey('floating-nav-surface'));
final _bar = find.byKey(const ValueKey('library-selection-bar'));
final _search = find.byKey(const ValueKey('library-selection-search'));
final _remove = find.byKey(const ValueKey('library-selection-remove'));

Future<void> _select(WidgetTester tester) async {
  await tester.tap(find.text('Select'));
  await tester.pumpAndSettle();
}

Future<void> _longPress(WidgetTester tester, String title) async {
  await tester.longPress(find.text(title));
  await tester.pumpAndSettle();
}

Future<void> _tapTile(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// The artwork's opacity of the tile named [title]: 1 selected or at rest,
/// the dimmed step for an unselected one in selection mode.
double _artworkOpacity(WidgetTester tester, String title) {
  final tile = find.ancestor(
    of: find.text(title),
    matching: find.byType(InkWell),
  );
  final fade = find.descendant(
    of: tile.first,
    matching: find.byType(AnimatedOpacity),
  );
  // Outside selection mode the artwork is not wrapped at all: whole.
  return fade.evaluate().isEmpty
      ? 1
      : tester.widget<AnimatedOpacity>(fade.first).opacity;
}

void main() {
  group('entering', () {
    testWidgets('Select opens selection mode with nothing selected, and '
        'hides the field, the peek and the Select button', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked()), peek: true));
      expect(find.text('Select'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('the peek'), findsOneWidget);

      await _select(tester);

      expect(find.text('None selected'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Select all 4'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('the peek'), findsNothing);
      expect(find.text('Select'), findsNothing);
    });

    testWidgets('a long press on a tile enters with that tile selected', (
      tester,
    ) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));

      await _longPress(tester, 'Bill Evans');

      expect(find.text('1 selected'), findsOneWidget);
      expect(_artworkOpacity(tester, 'Bill Evans'), 1);
      expect(_artworkOpacity(tester, 'Anton Bruckner'), lessThan(1));
    });

    testWidgets('a wall without bulk actions never shows Select, and a long '
        'press opens nothing', (tester) async {
      await _pump(tester, _wall());

      expect(find.text('Select'), findsNothing);
      await tester.longPress(find.text('Bill Evans'));
      await tester.pumpAndSettle();

      expect(find.text('None selected'), findsNothing);
      expect(find.text('1 selected'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group('selecting', () {
    testWidgets('a tap toggles a tile, and the count follows', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _select(tester);

      await _tapTile(tester, 'Bill Evans');
      await _tapTile(tester, 'Brian Eno');
      expect(find.text('2 selected'), findsOneWidget);

      await _tapTile(tester, 'Bill Evans');
      expect(find.text('1 selected'), findsOneWidget);
      expect(_artworkOpacity(tester, 'Brian Eno'), 1);
      expect(_artworkOpacity(tester, 'Bill Evans'), lessThan(1));
    });

    testWidgets('a tile is a toggle for a screen reader, with its state, and '
        'the count is a live region', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');

      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Bill Evans'))),
        isSemantics(hasCheckedState: true, isChecked: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Anton Bruckner'))),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('1 selected')),
        isSemantics(isLiveRegion: true),
      );
    });

    testWidgets('Select all takes what the chip shows, and reads Deselect all '
        'once it has', (tester) async {
      await _pump(
        tester,
        _wall(
          bulk: _bulk(_Asked()),
          status: (title) => MediaStatusInfo(
            availability: title == 'Bill Evans'
                ? MediaAvailability.missing
                : MediaAvailability.available,
          ),
        ),
      );
      await _select(tester);
      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('Select all 1'), findsOneWidget);
      await tester.tap(find.text('Select all 1'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Deselect all'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      // Under All, what is shown is four and one of them is selected.
      expect(find.text('Select all 4'), findsOneWidget);
      await tester.tap(find.text('Select all 4'));
      await tester.pumpAndSettle();
      expect(find.text('4 selected'), findsOneWidget);

      await tester.tap(find.text('Deselect all'));
      await tester.pumpAndSettle();
      expect(find.text('None selected'), findsOneWidget);
    });

    testWidgets('titles a chip hides stay selected, are counted, and the '
        'header says so', (tester) async {
      await _pump(
        tester,
        _wall(
          bulk: _bulk(_Asked()),
          status: (title) => MediaStatusInfo(
            availability: title == 'Bill Evans'
                ? MediaAvailability.missing
                : MediaAvailability.available,
          ),
        ),
      );
      await _longPress(tester, 'Anton Bruckner');
      await _tapTile(tester, 'Bill Evans');
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.textContaining('hidden'), findsNothing);

      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.text('1 hidden by Missing'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('2 selected'))).label,
        '2 selected, 1 hidden by Missing',
      );

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.textContaining('hidden'), findsNothing);
    });

    testWidgets('a library of thousands counts with the thousands separator', (
      tester,
    ) async {
      final many = [for (var i = 0; i < 1284; i++) 'Artist ${i + 1}'];
      await _pump(tester, _wall(bulk: _bulk(_Asked()), titles: many));

      await _select(tester);

      expect(find.text('Select all 1,284'), findsOneWidget);
      expect(formatCount(1284), '1,284');
      expect(formatCount(34), '34');
      expect(formatCount(1000000), '1,000,000');
    });
  });

  group('leaving', () {
    testWidgets('Cancel ends it', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(_artworkOpacity(tester, 'Bill Evans'), 1);
    });

    testWidgets('Back ends it, and Back again leaves the wall alone', (
      tester,
    ) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');

      final handled = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(handled, isTrue);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('Esc ends it', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('Ctrl A selects all off Apple platforms', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _select(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.text('4 selected'), findsOneWidget);
    });

    testWidgets('Cmd A selects all on macOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await _pump(tester, _wall(bulk: _bulk(_Asked())));
        await _select(tester);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(find.text('4 selected'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('the bar', () {
    testWidgets('stands where the navigation bar stood, and takes its place '
        'over 320 ms', (tester) async {
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      final tapped = <int>[];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          MediaQuery(
            // A phone with a home indicator.
            data: const MediaQueryData(
              size: Size(390, 844),
              padding: EdgeInsets.only(bottom: 34),
              viewPadding: EdgeInsets.only(bottom: 34),
            ),
            child: _Shell(
              controller: controller,
              tapped: tapped,
              wall: _wall(bulk: _bulk(_Asked())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resting = tester.getRect(_navSurface);
      expect(_bar, findsNothing);

      await _select(tester);
      // The bar is where the navigation bar was, and it is the one that moved.
      expect(tester.getRect(_bar), resting);
      expect(
        tester.getRect(_navSurface).top,
        greaterThanOrEqualTo(844),
        reason: 'the navigation bar has stepped down out of sight',
      );
      expect(
        tester
            .widget<IgnorePointer>(
              find
                  .ancestor(
                    of: _navSurface,
                    matching: find.byType(IgnorePointer),
                  )
                  .first,
            )
            .ignoring,
        isTrue,
      );
    });

    testWidgets('one goes down while the other comes up, over the standard '
        'duration', (tester) async {
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          _Shell(
            controller: controller,
            tapped: [],
            wall: _wall(bulk: _bulk(_Asked())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resting = tester.getRect(_navSurface).top;

      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      final navMid = tester.getRect(_navSurface).top;
      final barMid = tester.getRect(_bar).top;
      expect(navMid, greaterThan(resting), reason: 'going down');
      expect(barMid, greaterThan(resting), reason: 'still coming up');
      expect(
        navMid - resting,
        lessThan(tester.getRect(_navSurface).height * 2),
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(_bar).top, resting);
      expect(tester.getRect(_navSurface).top, greaterThan(resting));

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));
      // The bar is going down with what it said, the navigation bar coming up.
      expect(tester.getRect(_bar).top, greaterThan(resting));
      expect(tester.getRect(_navSurface).top, greaterThan(resting));
      await tester.pumpAndSettle();
      expect(_bar, findsNothing);
      expect(tester.getRect(_navSurface).top, resting);
    });

    testWidgets('under Reduce Motion they fade over 150 ms and do not '
        'slide', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          _Shell(
            controller: controller,
            tapped: [],
            wall: _wall(bulk: _bulk(_Asked())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final resting = tester.getRect(_navSurface).top;

      await tester.tap(find.text('Select'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));

      expect(tester.getRect(_navSurface).top, resting, reason: 'no slide');
      expect(tester.getRect(_bar).top, resting, reason: 'no slide');
      final fades = tester.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(Scaffold).first,
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fades.any((f) => f.opacity.value > 0 && f.opacity.value < 1),
        isTrue,
        reason: 'mid-fade',
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getRect(_navSurface).top, resting);
    });

    testWidgets('tabs cannot be switched while selecting, and can once it is '
        'done', (tester) async {
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      final tapped = <int>[];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          _Shell(
            controller: controller,
            tapped: tapped,
            wall: _wall(bulk: _bulk(_Asked())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final home = tester.getCenter(find.text('Home'));

      await _select(tester);
      // A tap where the Home tab was lands on the bar that took its place.
      await tester.tapAt(home);
      await tester.pumpAndSettle();
      expect(tapped, isEmpty);
      expect(
        find.semantics.byLabel(RegExp('^Home')),
        findsNothing,
        reason: 'the bar says nothing while it is hidden',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tapAt(home);
      await tester.pumpAndSettle();
      expect(tapped, [0]);
    });

    testWidgets('on a tablet the bar floats at the foot of the list, clear '
        'of the foot', (tester) async {
      tester.view.physicalSize = const Size(1024, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(_wall(bulk: _bulk(_Asked()))));
      await tester.pumpAndSettle();

      await _select(tester);

      final rect = tester.getRect(_bar);
      expect(
        760 - rect.bottom,
        AppSpacing.xl,
        reason: 'a rail layout has no navigation bar to stand where',
      );
      expect(rect.height, FloatingNavBarMetrics.barHeight);
      expect(rect.left, greaterThan(0));
    });

    testWidgets('names what is selected, and its four columns of one width '
        'are actions at 44 points', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');
      await _tapTile(tester, 'Brian Eno');

      expect(
        tester.getSemantics(find.bySemanticsLabel('2 artists selected')),
        isSemantics(),
      );
      expect(tester.getSize(_search).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(_search).width, greaterThanOrEqualTo(44));
    });
  });

  group('with nothing selected', () {
    testWidgets('the actions are dimmed but tappable: a tap says why it did '
        'nothing, and they carry that as their hint', (tester) async {
      final asked = _Asked();
      await _pump(tester, _wall(bulk: _bulk(asked)));
      await _select(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('No artists selected')),
        isSemantics(),
      );
      expect(tester.getSemantics(_search).hint, 'Select an artist first');
      expect(tester.getSemantics(_remove).hint, 'Select an artist first');
      expect(
        tester.getSemantics(_search),
        isSemantics(isButton: true, hasTapAction: true, hasEnabledState: false),
        reason: 'never Semantics(enabled: false)',
      );

      await tester.tap(_search);
      await tester.pump();

      expect(find.text('Select an artist first'), findsOneWidget);
      expect(asked.prepared, 0);
      expect(asked.runs, isEmpty);

      // Tapped again, it is still one toast, not a queue of them.
      await tester.tap(_search);
      await tester.pump();
      expect(find.text('Select an artist first'), findsOneWidget);
    });

    testWidgets('the actions come alive with the first title', (tester) async {
      await _pump(tester, _wall(bulk: _bulk(_Asked())));
      await _longPress(tester, 'Bill Evans');

      expect(tester.getSemantics(_search).hint, anyOf(isNull, isEmpty));
    });
  });

  group('an action', () {
    testWidgets('runs for the selected titles in the wall’s order, says how '
        'many, ends the selection and reads the library again', (tester) async {
      final asked = _Asked();
      await _pump(tester, _wall(bulk: _bulk(asked)));
      await _longPress(tester, 'Brian Eno');
      await _tapTile(tester, 'Anton Bruckner');

      await tester.tap(_search);
      await tester.pumpAndSettle();

      expect(asked.runs, [
        ['Anton Bruckner', 'Brian Eno'],
      ]);
      expect(asked.changed, 1);
      expect(find.text('Searching 2'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
    });

    testWidgets('Remove takes only the selected titles the chip shows, the '
        'others stay selected and are not touched', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          bulk: _bulk(asked, removeRuns: true),
          status: (title) => MediaStatusInfo(
            availability: title == 'Bill Evans'
                ? MediaAvailability.missing
                : MediaAvailability.available,
          ),
        ),
      );
      await _longPress(tester, 'Anton Bruckner');
      await _tapTile(tester, 'Bill Evans');
      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();
      expect(find.text('1 hidden by Missing'), findsOneWidget);

      await tester.tap(_remove);
      await tester.pumpAndSettle();

      expect(asked.removing, [
        ['Bill Evans'],
      ], reason: 'the confirmation counts only what the wall shows');
      expect(find.text('Removed 1'), findsOneWidget);
      // The hidden one is still selected, and the header still says so.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('1 hidden by Missing'), findsOneWidget);
    });

    testWidgets('Remove with every selected title hidden does not start, '
        'and says why', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          bulk: _bulk(asked, removeRuns: true),
          status: (title) => MediaStatusInfo(
            availability: title == 'Bill Evans'
                ? MediaAvailability.missing
                : MediaAvailability.available,
          ),
        ),
      );
      await _longPress(tester, 'Anton Bruckner');
      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      await tester.tap(_remove);
      await tester.pumpAndSettle();

      expect(asked.prepared, 0);
      expect(
        find.text('None of the selected artists show under Missing'),
        findsOneWidget,
      );
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('Search still takes the whole selection, hidden titles '
        'included', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          bulk: _bulk(asked),
          status: (title) => MediaStatusInfo(
            availability: title == 'Bill Evans'
                ? MediaAvailability.missing
                : MediaAvailability.available,
          ),
        ),
      );
      await _longPress(tester, 'Anton Bruckner');
      await _tapTile(tester, 'Bill Evans');
      await tester.tap(find.text('Missing'));
      await tester.pumpAndSettle();

      await tester.tap(_search);
      await tester.pumpAndSettle();

      expect(asked.runs, [
        ['Anton Bruckner', 'Bill Evans'],
      ]);
    });

    testWidgets('one that is backed out of leaves the selection as it was', (
      tester,
    ) async {
      final asked = _Asked();
      await _pump(tester, _wall(bulk: _bulk(asked)));
      await _longPress(tester, 'Bill Evans');

      await tester.tap(_remove);
      await tester.pumpAndSettle();

      expect(asked.prepared, 1);
      expect(asked.runs, isEmpty);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('shows progress on the action and leaves the others inert, '
        'and neither Cancel nor Back stop a write in flight', (tester) async {
      final asked = _Asked();
      final out = Completer<MediaBulkOutcome>();
      await _pump(
        tester,
        _wall(bulk: _bulk(asked, outcome: (_) => out.future)),
      );
      await _longPress(tester, 'Bill Evans');

      await tester.tap(_search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.descendant(
          of: _search,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(tester.getSemantics(_search).hint, 'In progress');

      final preparedBefore = asked.prepared;
      await tester.tap(_remove);
      await tester.pump();
      expect(asked.prepared, preparedBefore, reason: 'inert while one is out');

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.text('Anton Bruckner'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      out.complete(MediaBulkOutcome(done: [_id('Bill Evans')]));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group('a partial outcome', () {
    Future<_Asked> partial(
      WidgetTester tester, {
      List<String> failing = const ['Brian Eno'],
      Future<MediaBulkOutcome> Function(List<String> titles)? then,
    }) async {
      final asked = _Asked();
      var first = true;
      await _pump(
        tester,
        _wall(
          bulk: _bulk(
            asked,
            outcome: (titles) async {
              if (!first) {
                return then != null
                    ? then(titles)
                    : MediaBulkOutcome(done: [for (final t in titles) _id(t)]);
              }
              first = false;
              return MediaBulkOutcome(
                done: [
                  for (final title in titles)
                    if (!failing.contains(title)) _id(title),
                ],
                failures: [for (final title in failing) _refused(title)],
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all 4'));
      await tester.pumpAndSettle();
      await tester.tap(_search);
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets('ends the selection and puts the notice over the wall, in '
        'the refusal’s words', (tester) async {
      await partial(tester);

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('3 of 4 artists updated'), findsOneWidget);
      expect(
        find.text('Lidarr refused Brian Eno: the folder is not reachable.'),
        findsOneWidget,
      );
      expect(find.text('Try Brian Eno again'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      // The one that took it is not in the notice.
      expect(find.textContaining('Bill Evans:'), findsNothing);
    });

    testWidgets('Try again runs the same action for the refused titles and '
        'no others, and a success removes the notice', (tester) async {
      final asked = await partial(tester);

      await tester.tap(find.text('Try Brian Eno again'));
      await tester.pumpAndSettle();

      expect(asked.runs, [
        _titles,
        ['Brian Eno'],
      ]);
      expect(find.text('3 of 4 artists updated'), findsNothing);
      expect(find.text('Searching 4'), findsOneWidget);
      expect(asked.changed, 2);
    });

    testWidgets('several refusals are one retry for those, named by count', (
      tester,
    ) async {
      final asked = await partial(
        tester,
        failing: ['Brian Eno', 'Bill Evans'],
        then: (titles) async => MediaBulkOutcome(
          done: [_id(titles.first)],
          failures: [_refused(titles.last)],
        ),
      );
      expect(find.text('2 of 4 artists updated'), findsOneWidget);
      expect(find.text('Try 2 artists again'), findsOneWidget);

      await tester.tap(find.text('Try 2 artists again'));
      await tester.pumpAndSettle();

      expect(asked.runs.last, ['Bill Evans', 'Brian Eno']);
      // One took it this time: the count moves, and one is still refused.
      expect(find.text('3 of 4 artists updated'), findsOneWidget);
      expect(find.text('Try Brian Eno again'), findsOneWidget);
    });

    testWidgets('Dismiss removes the notice', (tester) async {
      await partial(tester);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      expect(find.text('3 of 4 artists updated'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
    });
  });

  group('an outcome that is no title’s', () {
    testWidgets('a failure of the request keeps the selection, with the '
        'failure line and its remedy', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          bulk: _bulk(
            asked,
            outcome: (_) => Future.error(
              DioException.connectionError(
                requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
                reason: 'Connection refused',
              ),
            ),
          ),
        ),
      );
      await _longPress(tester, 'Bill Evans');

      await tester.tap(_search);
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(find.textContaining('nothing was changed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(asked.changed, 0);

      // The selection is intact, and Retry asks the same of the same titles.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(asked.runs, [
        ['Bill Evans'],
        ['Bill Evans'],
      ]);
      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('every title refused keeps the selection under the refusals', (
      tester,
    ) async {
      await _pump(
        tester,
        _wall(
          bulk: _bulk(
            _Asked(),
            outcome: (titles) async => MediaBulkOutcome(
              done: const [],
              failures: [for (final title in titles) _refused(title)],
            ),
          ),
        ),
      );
      await _longPress(tester, 'Bill Evans');
      await _tapTile(tester, 'Brian Eno');

      await tester.tap(_search);
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(find.textContaining('Lidarr refused Bill Evans'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('another connection', () {
    // Ids are one connection's. Two Lidarrs number their artists alike.
    const first = {'Anton Bruckner': 1, 'Bill Evans': 2, 'Brian Eno': 3};
    const second = {'Alice Coltrane': 1, 'Bobby Hutcherson': 2, 'Can': 3};

    Widget wallOf(String lens, {_Asked? asked, Completer<void>? hold}) {
      final names = lens == 'one' ? first : second;
      return _wall(
        titles: names.keys.toList(),
        ids: names,
        bulk: _bulk(
          asked ?? _Asked(),
          instanceId: 'lidarr-$lens',
          outcome: hold == null
              ? null
              : (titles) async {
                  await hold.future;
                  return MediaBulkOutcome(
                    done: const [1],
                    failures: [_refused('Bill Evans')],
                  );
                },
        ),
      );
    }

    testWidgets('a selection does not follow the wall to the other '
        'connection, where its ids are other titles', (tester) async {
      final asked = _Asked();
      await _pump(tester, wallOf('one', asked: asked));
      await _longPress(tester, 'Bill Evans');
      expect(find.text('1 selected'), findsOneWidget);

      await tester.pumpWidget(_app(wallOf('two', asked: asked)));
      await tester.pumpAndSettle();

      expect(find.text('Bobby Hutcherson'), findsOneWidget);
      expect(find.textContaining('selected'), findsNothing);
      expect(_bar, findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(asked.runs, isEmpty);
    });

    testWidgets('what the last action left (a failure and its retry) does '
        'not follow either', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          titles: first.keys.toList(),
          ids: first,
          bulk: _bulk(
            asked,
            outcome: (_) => Future.error(
              DioException.connectionError(
                requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
                reason: 'Connection refused',
              ),
            ),
          ),
        ),
      );
      await _longPress(tester, 'Bill Evans');
      await tester.tap(_search);
      await tester.pumpAndSettle();
      expect(find.byType(InlineErrorRetry), findsOneWidget);

      await tester.pumpWidget(_app(wallOf('two', asked: asked)));
      await tester.pumpAndSettle();

      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('an action still out when the connection changes paints '
        'nothing on the new wall, and reads the library again', (tester) async {
      final asked = _Asked();
      final hold = Completer<void>();
      await _pump(tester, wallOf('one', asked: asked, hold: hold));
      await _longPress(tester, 'Bill Evans');
      await tester.tap(_search);
      await tester.pump();

      await tester.pumpWidget(_app(wallOf('two', asked: asked)));
      await tester.pump();
      hold.complete();
      await tester.pumpAndSettle();

      expect(find.textContaining('selected'), findsNothing);
      expect(find.byType(InlineErrorRetry), findsNothing);
      expect(find.textContaining('updated'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(asked.changed, 1);
    });
  });

  group('an outcome nobody can know', () {
    DioException receiveTimeout() => DioException.receiveTimeout(
      timeout: const Duration(seconds: 30),
      requestOptions: RequestOptions(path: '/api/v1/artist/editor'),
    );

    testWidgets('a timeout after the request went out does not say nothing '
        'was changed, and the library is read again', (tester) async {
      final asked = _Asked();
      await _pump(
        tester,
        _wall(
          bulk: _bulk(asked, outcome: (_) => Future.error(receiveTimeout())),
        ),
      );
      await _longPress(tester, 'Bill Evans');

      await tester.tap(_search);
      await tester.pumpAndSettle();

      expect(find.byType(InlineErrorRetry), findsOneWidget);
      expect(find.textContaining('nothing was changed'), findsNothing);
      expect(find.textContaining('may have changed'), findsOneWidget);
      expect(asked.changed, 1);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('Retry acts on the selected titles the library still holds, '
        'not on the list captured before', (tester) async {
      final asked = _Asked();
      final held = StateProvider<List<String>>((ref) => _titles);
      final library = FutureProvider<List<String>>(
        (ref) async => ref.watch(held),
      );
      asked.reread = (ref) {
        // The write had gone through for Bill Evans.
        ref.read(held.notifier).state = [
          for (final title in _titles)
            if (title != 'Bill Evans') title,
        ];
      };
      var calls = 0;
      await _pump(
        tester,
        _wall(
          library: library,
          bulk: _bulk(
            asked,
            outcome: (titles) {
              if (calls++ == 0) return Future.error(receiveTimeout());
              return Future.value(
                MediaBulkOutcome(done: [for (final t in titles) _id(t)]),
              );
            },
          ),
        ),
      );
      await _longPress(tester, 'Bill Evans');
      await _tapTile(tester, 'Brian Eno');

      await tester.tap(_search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(asked.runs, [
        ['Bill Evans', 'Brian Eno'],
        ['Brian Eno'],
      ]);
    });
  });

  group('leaving the wall', () {
    testWidgets('a wall that is no longer the page on screen ends its '
        'selection', (tester) async {
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        LibrarySelectionScope(
          controller: controller,
          child: _wall(bulk: _bulk(_Asked())),
        ),
      );
      await _longPress(tester, 'Bill Evans');
      expect(controller.isSelecting, isTrue);

      // The branch it lives in goes offstage, as a tab left does.
      await tester.pumpWidget(
        _app(
          LibrarySelectionScope(
            controller: controller,
            child: TickerMode(
              enabled: false,
              child: _wall(bulk: _bulk(_Asked())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.isSelecting, isFalse);
    });

    testWidgets('tearing the wall down lets go of the shell', (tester) async {
      final controller = LibrarySelectionController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        LibrarySelectionScope(
          controller: controller,
          child: _wall(bulk: _bulk(_Asked())),
        ),
      );
      await _longPress(tester, 'Bill Evans');
      expect(controller.isSelecting, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(controller.isSelecting, isFalse);
    });
  });
}

String _read(String path) => File(path).readAsStringSync();
