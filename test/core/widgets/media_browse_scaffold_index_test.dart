import 'dart:ui' show SemanticsAction;

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
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _query = StateProvider<String>((ref) => '');

/// A long alphabetical wall: [perLetter] titles (and a few more for some
/// letters) under each letter of [letters], and a few that start with a digit,
/// which the wall heads with `#`.
List<String> _titles({
  String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
  int perLetter = 13,
  int digits = 4,
}) => [
  for (var i = 0; i < digits; i++) '${i + 1}$i Hours',
  for (final letter in letters.split(''))
    for (var i = 0; i < perLetter + (letter.codeUnitAt(0) % 7); i++)
      '$letter${i.toString().padLeft(2, '0')} title',
];

/// Exactly [count] titles, spread over the alphabet.
List<String> _numbered(int count) => [
  for (var i = 0; i < count; i++)
    '${String.fromCharCode(65 + i % 26)}${(i ~/ 26).toString().padLeft(2, '0')}',
];

/// Which titles carry a caption: not all, so that rows are of two heights.
bool _captioned(String title) => title.hashCode % 3 != 0;

Widget _wall(
  List<String> titles, {
  MediaBrowseTileShape shape = MediaBrowseTileShape.circle,
  bool showAppBar = true,
  double topPadding = 0,
  List<MediaBrowseSort<String>> sorts = const [],
  String Function(String title)? subtitle,
}) {
  final library = FutureProvider<List<String>>((ref) async => titles);
  return ProviderScope(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: MediaBrowseScaffold<String>(
        title: 'Wall',
        searchHint: 'Search',
        activityRoute: '/activity',
        navigationSection: NavigationSection.stack,
        serviceName: 'Lidarr',
        heroTagPrefix: 'wall',
        libraryProvider: library,
        searchQueryProvider: _query,
        find: MediaFind.libraryOnly(
          libraryBody: (context, query) => Text('find:$query'),
        ),
        titleExtractor: (title) => title,
        subtitleExtractor:
            subtitle ?? (title) => _captioned(title) ? 'Caption' : '',
        imagesExtractor: (_) => null,
        idExtractor: (title) => title.hashCode,
        settingsSelector: (_) => ('', '', const NoAccess()),
        onItemTap: (_, _, _) {},
        tileShape: shape,
        showAppBar: showAppBar,
        topPadding: topPadding,
        sorts: sorts,
        kpiPeek: const SizedBox(height: 96, child: Placeholder()),
      ),
    ),
  );
}

Future<void> _phone(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Rect _strip(WidgetTester tester) =>
    tester.getRect(find.byType(MediaBrowseIndex));

/// The point on the strip where [letter] is drawn.
Offset _at(WidgetTester tester, String letter) {
  final rect = _strip(tester);
  final index = MediaBrowseIndex.letters.indexOf(letter);
  return Offset(
    rect.center.dx,
    rect.top + rect.height * (index + 0.5) / MediaBrowseIndex.letters.length,
  );
}

/// Where the top of the body is: the scroll view's top.
double _bodyTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(CustomScrollView).last).dy;

double _headingTop(WidgetTester tester, String letter) =>
    tester.getTopLeft(find.byKey(ValueKey('media-browse-section-$letter'))).dy;

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position;

/// Taps [letter] on the strip and lets the wall settle.
Future<void> _jump(WidgetTester tester, String letter) async {
  await tester.tapAt(_at(tester, letter));
  await tester.pumpAndSettle();
}

/// Where a heading lands under a bar: its fade, and the wall's own margin.
const _landing = ScrollEdgeFade.height + AppSpacing.sm;

/// What a screen reader does to the strip.
void _perform(WidgetTester tester, SemanticsAction action) {
  tester.semantics.performAction(
    find.semantics.byLabel('Jump to letter'),
    action,
  );
}

/// The strip alone, in a box [height] tall at the right edge of a room.
Widget _stripAlone({
  required Set<String> present,
  required void Function(String letter) onJump,
  double height = 600,
}) => MaterialApp(
  theme: AppTheme.darkTheme(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topRight,
      child: SizedBox(
        height: height,
        child: MediaBrowseIndex(present: present, onJump: onJump),
      ),
    ),
  ),
);

Finder _letter(String letter) => find.descendant(
  of: find.byType(MediaBrowseIndex),
  matching: find.text(letter),
);

/// The bubble: the disc round the large copy of [letter], which is the last
/// one in the tree.
Rect _bubble(WidgetTester tester, String letter) => tester.getRect(
  find
      .ancestor(of: _letter(letter).last, matching: find.byType(DecoratedBox))
      .first,
);

Color _inkOf(WidgetTester tester, String letter) =>
    tester.widget<Text>(_letter(letter).first).style!.color!;

void main() {
  group('MediaBrowseIndex.letterAt', () {
    // `#` heads the strip, as it heads the wall.
    const present = {'#', 'B', 'D'};

    test('the strip runs in the order of the wall: # first, then A to Z', () {
      expect(MediaBrowseIndex.letters.first, '#');
      expect(MediaBrowseIndex.letters[1], 'A');
      expect(MediaBrowseIndex.letters.last, 'Z');
      expect(MediaBrowseIndex.letters, hasLength(27));
    });

    test('lands on the nearest present letter at or after the finger', () {
      expect(MediaBrowseIndex.letterAt(0.5 / 27, present), '#');
      expect(MediaBrowseIndex.letterAt(1.5 / 27, present), 'B');
      expect(MediaBrowseIndex.letterAt(2.5 / 27, present), 'B');
      expect(MediaBrowseIndex.letterAt(3.5 / 27, present), 'D');
      expect(MediaBrowseIndex.letterAt(4.5 / 27, present), 'D');
    });

    test(
      'falls back to the last present letter before it, never to nothing',
      () {
        expect(MediaBrowseIndex.letterAt(1, const {'B', 'D'}), 'D');
        expect(MediaBrowseIndex.letterAt(0.5, const {'B'}), 'B');
        expect(MediaBrowseIndex.letterAt(0.5, const {}), isNull);
      },
    );

    test('keeps a finger past either end on the strip', () {
      expect(MediaBrowseIndex.letterAt(-0.2, present), '#');
      expect(MediaBrowseIndex.letterAt(1.4, present), 'D');
    });

    test('is monotonic: a finger lower on the strip never lands higher', () {
      const all = {'#', 'A', 'C', 'F', 'M', 'N', 'Z'};
      var last = -1;
      for (var step = 0; step <= 100; step++) {
        final letter = MediaBrowseIndex.letterAt(step / 100, all)!;
        final at = MediaBrowseIndex.letters.indexOf(letter);
        expect(at, greaterThanOrEqualTo(last));
        last = at;
      }
    });
  });

  group('MediaBrowseIndex.drawnIndexes', () {
    test('draws every letter when they fit', () {
      expect(
        MediaBrowseIndex.drawnIndexes(27 * 14, 14),
        List.generate(27, (index) => index),
      );
    });

    test('drops letters in between, keeping the first and the last', () {
      final drawn = MediaBrowseIndex.drawnIndexes(300, 28);
      // 10 slots: 5 letters with 4 dots between.
      expect(drawn, hasLength(5));
      // `#`, `A` and `Z` are anchors.
      expect(drawn.first, 0);
      expect(drawn[1], 1);
      expect(drawn.last, 26);
      expect(drawn.toSet(), hasLength(drawn.length));
      expect(drawn, orderedEquals([...drawn]..sort()));
    });

    test('never draws fewer than the two ends', () {
      expect(MediaBrowseIndex.drawnIndexes(10, 28), [0, 26]);
    });
  });

  group('the strip as a control', () {
    const some = {'A', 'B', 'M', 'N', 'Z'};

    testWidgets('draws a letter with a section in ink and one without dimmed', (
      tester,
    ) async {
      await tester.pumpWidget(_stripAlone(present: some, onJump: (_) {}));
      final room = CupolaRoom.of(tester.element(find.byType(MediaBrowseIndex)));

      expect(_inkOf(tester, 'M'), room.ink);
      expect(_inkOf(tester, 'C'), room.inkDisabled);
      expect(_inkOf(tester, 'Z'), room.ink);
      expect(
        find.descendant(
          of: find.byType(MediaBrowseIndex),
          matching: find.byType(Text),
        ),
        findsNWidgets(27),
        reason: 'all 27 fit a tall strip, so none is left out',
      );
    });

    testWidgets('a tap on a dimmed letter lands on the next one with a '
        'section, and past the last on the last', (tester) async {
      final jumps = <String>[];
      await tester.pumpWidget(_stripAlone(present: some, onJump: jumps.add));

      await tester.tapAt(_at(tester, 'C'));
      await tester.pump();
      await tester.tapAt(_at(tester, 'Y'));
      await tester.pump();

      expect(jumps, ['M', 'Z']);
    });

    testWidgets('a drag jumps once per letter it lands on, not once per move', (
      tester,
    ) async {
      final jumps = <String>[];
      await tester.pumpWidget(_stripAlone(present: some, onJump: jumps.add));

      final gesture = await tester.startGesture(_at(tester, 'A'));
      for (final letter in ['A', 'B', 'C', 'M', 'N', 'O']) {
        await gesture.moveTo(_at(tester, letter));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      // C and O have no section: the finger on them lands on M and on Z, and
      // the finger moving from C to M stays on M.
      expect(jumps, ['A', 'B', 'M', 'N', 'Z']);
    });

    testWidgets('the bubble shows the letter while the finger is down, left '
        'of the strip and centred on it', (tester) async {
      await tester.pumpWidget(_stripAlone(present: some, onJump: (_) {}));
      expect(_letter('M'), findsOneWidget);

      final gesture = await tester.startGesture(_at(tester, 'M'));
      await tester.pump();

      // The strip's own M and the bubble's.
      expect(_letter('M'), findsNWidgets(2));
      final bubble = _bubble(tester, 'M');
      expect(bubble.size, const Size.square(MediaBrowseIndex.bubbleSize));
      expect(
        bubble.right,
        closeTo(_strip(tester).left - MediaBrowseIndex.bubbleGap, 0.01),
      );
      expect(bubble.center.dy, closeTo(_at(tester, 'M').dy, 0.01));

      await gesture.up();
      await tester.pump();
      expect(_letter('M'), findsOneWidget);
    });

    testWidgets('the bubble stays inside the strip at the top and the bottom', (
      tester,
    ) async {
      await tester.pumpWidget(_stripAlone(present: some, onJump: (_) {}));

      var gesture = await tester.startGesture(_at(tester, 'A'));
      await tester.pump();
      expect(_bubble(tester, 'A').top, _strip(tester).top);
      await gesture.up();
      await tester.pump();

      gesture = await tester.startGesture(_at(tester, 'Z'));
      await tester.pump();
      expect(_bubble(tester, 'Z').bottom, _strip(tester).bottom);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('a selection haptic on each letter change on iOS, none on a '
        'desktop', (tester) async {
      final haptics = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(_stripAlone(present: some, onJump: (_) {}));

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final gesture = await tester.startGesture(_at(tester, 'A'));
        await gesture.moveTo(_at(tester, 'A'));
        await gesture.moveTo(_at(tester, 'B'));
        await gesture.moveTo(_at(tester, 'M'));
        await gesture.up();
        await tester.pump();
        // A, B, M: the move that stayed on A changed nothing.
        expect(haptics, List.filled(3, 'HapticFeedbackType.selectionClick'));

        haptics.clear();
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await tester.tapAt(_at(tester, 'N'));
        await tester.pump();
        expect(haptics, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('is one adjustable control that steps through the letters '
        'with a section', (tester) async {
      final semantics = tester.ensureSemantics();
      final jumps = <String>[];
      await tester.pumpWidget(_stripAlone(present: some, onJump: jumps.add));

      var node = tester.getSemantics(find.byType(MediaBrowseIndex));
      expect(node.label, 'Jump to letter');
      expect(node.value, 'A');
      expect(node.getSemanticsData().flagsCollection.isSlider, isTrue);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.decrease),
        isFalse,
      );
      expect(node.increasedValue, 'B');
      // One control: its letters are not 27 nodes of their own.
      expect(node.childrenCount, 0);

      _perform(tester, SemanticsAction.increase);
      await tester.pump();
      _perform(tester, SemanticsAction.increase);
      await tester.pump();

      expect(jumps, ['B', 'M']);
      node = tester.getSemantics(find.byType(MediaBrowseIndex));
      expect(node.value, 'M');
      expect(node.decreasedValue, 'B');
      expect(node.increasedValue, 'N');

      _perform(tester, SemanticsAction.decrease);
      await tester.pump();
      expect(jumps, ['B', 'M', 'B']);
      semantics.dispose();
    });

    testWidgets('at twice the reading size a short strip draws a dot for the '
        'letters it leaves out, and a drag still reaches them', (tester) async {
      await _phone(tester, scale: 2);
      final jumps = <String>[];
      await tester.pumpWidget(
        _stripAlone(
          present: {for (final letter in MediaBrowseIndex.letters) letter},
          onJump: jumps.add,
          height: 400,
        ),
      );

      final drawn = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byType(MediaBrowseIndex),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .toList();
      expect(drawn.length, lessThan(27));
      expect(drawn.first, '#');
      expect(drawn[1], 'A');
      expect(drawn.last, 'Z');
      // No letter is drawn over the one above it, `#` and `A` included.
      final rects = [
        for (final text in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(MediaBrowseIndex),
            matching: find.byType(Text),
          ),
        ))
          tester.getRect(find.text(text.data!).first),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(
          rects[i].top,
          greaterThanOrEqualTo(rects[i - 1].bottom - 0.5),
          reason: drawn[i],
        );
      }
      // A dot sits in every gap between two letters that are drawn.
      final dots = find.descendant(
        of: find.byType(MediaBrowseIndex),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      // `#` and `A` are neighbours, so there is no gap between them to mark.
      expect(dots, findsNWidgets(drawn.length - 2));

      // 'C' is not drawn, and is a letter all the same.
      expect(drawn, isNot(contains('C')));
      await tester.tapAt(_at(tester, 'C'));
      await tester.pump();
      expect(jumps, ['C']);
    });
  });

  group('the strip on the wall', () {
    testWidgets('shows on a long Title A–Z wall with the field empty', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();

      expect(find.byType(MediaBrowseIndex), findsOneWidget);
      // On the right edge, 28 wide.
      final strip = _strip(tester);
      expect(strip.width, MediaBrowseIndex.width);
      expect(strip.right, 390);
    });

    testWidgets('the wall gives up 28 of right margin while it shows', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();

      // Three columns across 390 less 16 on the left, 28 on the right and
      // two gaps.
      final tile = tester.getRect(find.byType(AspectRatio).first).width;
      expect(tile, closeTo((390 - 16 - 28 - 2 * AppSpacing.gridGap) / 3, 0.01));
    });

    testWidgets('does not show on a wall of fewer than forty titles', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_numbered(MediaBrowseIndex.minTitles - 1)));
      await tester.pumpAndSettle();

      expect(find.byType(MediaBrowseIndex), findsNothing);
      // And the wall keeps its 16 of margin.
      final tile = tester.getRect(find.byType(AspectRatio).first).width;
      expect(tile, closeTo((390 - 32 - 2 * AppSpacing.gridGap) / 3, 0.01));
    });

    testWidgets('shows on a wall of exactly forty', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_numbered(MediaBrowseIndex.minTitles)));
      await tester.pumpAndSettle();

      expect(find.byType(MediaBrowseIndex), findsOneWidget);
    });

    testWidgets('does not show under an order that draws no headings', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _wall(
          _titles(),
          sorts: [MediaBrowseSort<String>.size((title) => title.length)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowseIndex), findsOneWidget);

      await tester.tap(find.byTooltip('Change sort order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Size').last);
      await tester.pumpAndSettle();

      expect(find.byType(MediaBrowseIndex), findsNothing);
      final tile = tester.getRect(find.byType(AspectRatio).first).width;
      expect(tile, closeTo((390 - 32 - 2 * AppSpacing.gridGap) / 3, 0.01));

      await tester.tap(find.byTooltip('Change sort order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Title A–Z').last);
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowseIndex), findsOneWidget);
    });

    testWidgets('does not show while the field holds a search', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();
      expect(find.byType(MediaBrowseIndex), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'a0');
      await tester.pumpAndSettle();

      expect(find.byType(MediaBrowseIndex), findsNothing);
      expect(find.text('find:a0'), findsOneWidget);
    });

    testWidgets('dims the letters the wall has no section for', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles(letters: 'ABCDEFGHIJKLMN')));
      await tester.pumpAndSettle();
      final room = CupolaRoom.of(tester.element(find.byType(MediaBrowseIndex)));

      expect(_inkOf(tester, 'M'), room.ink);
      expect(_inkOf(tester, 'X'), room.inkDisabled);
      // The wall heads the digits with `#`, and so does the strip.
      expect(_inkOf(tester, '#'), room.ink);
    });

    testWidgets('sits under the header and above the floating bar', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();

      // The header is showing: the strip starts where the body does.
      expect(_strip(tester).top, greaterThanOrEqualTo(_bodyTop(tester)));
      expect(_strip(tester).bottom, lessThan(844));
    });
  });

  group('a wall of accented names', () {
    const names = [
      'Édith Piaf',
      'Eagles',
      'Ólafur Arnalds',
      'Oasis',
      'Øyvind',
      '1000 Paper Boats',
    ];

    testWidgets('has one section per letter, in order, # first', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(names, subtitle: (_) => ''));
      await tester.pumpAndSettle();

      Finder section(String letter) =>
          find.byKey(ValueKey('media-browse-section-$letter'));
      expect(section('#'), findsOneWidget);
      expect(section('E'), findsOneWidget);
      expect(section('O'), findsOneWidget);
      // No Ø or Ó section of their own, and nothing headed after the Os.
      for (final letter in ['É', 'Ó', 'Ø', 'Z']) {
        expect(section(letter), findsNothing, reason: letter);
      }
      final top = [
        for (final l in ['#', 'E', 'O']) tester.getTopLeft(section(l)).dy,
      ];
      expect(top, orderedEquals([...top]..sort()));

      // Within a letter, by the folded name: Eagles, then Édith.
      expect(
        tester.getTopLeft(find.text('Eagles')).dx,
        lessThan(tester.getTopLeft(find.text('Édith Piaf')).dx),
      );
      // The Os: Oasis, Ólafur, Øyvind, one run.
      final oasis = tester.getTopLeft(find.text('Oasis')).dx;
      final olafur = tester.getTopLeft(find.text('Ólafur Arnalds')).dx;
      final oyvind = tester.getTopLeft(find.text('Øyvind')).dx;
      expect(oasis, lessThan(olafur));
      expect(olafur, lessThan(oyvind));
    });

    testWidgets('everything that is not A to Z is one # section, first, and '
        'the strip jumps to its start', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _wall([
          '1975',
          '~Tilde',
          'Кино',
          'Мумий Тролль',
          'Ásgeir',
          'Abba',
          for (var i = 0; i < 40; i++) 'Zed ${i.toString().padLeft(2, '0')}',
        ], subtitle: (_) => ''),
      );
      await tester.pumpAndSettle();

      Finder section(String letter) =>
          find.byKey(ValueKey('media-browse-section-$letter'));
      // One `#`, however many keys sort past the letters, above the A.
      expect(section('#'), findsOneWidget);
      expect(
        tester.getTopLeft(section('#')).dy,
        lessThan(tester.getTopLeft(section('A')).dy),
      );
      // Its titles in key order, then the As, Ásgeir among them.
      double at(String title) => tester.getTopLeft(find.text(title)).dy;
      final run = [
        for (final t in ['1975', '~Tilde', 'Кино', 'Мумий Тролль']) at(t),
      ];
      expect(run, orderedEquals([...run]..sort()));
      expect(run.last, lessThan(tester.getTopLeft(section('A')).dy));
      expect(
        tester.getTopLeft(find.text('Abba')).dx,
        lessThan(tester.getTopLeft(find.text('Ásgeir')).dx),
      );

      // From far down the wall, `#` lands at its top, not after the Z.
      await _jump(tester, 'Z');
      await _jump(tester, '#');
      expect(_position(tester).pixels, 0);
    });

    testWidgets('the strip draws the same letters, # included', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _wall([
          ...names,
          for (var i = 0; i < 40; i++) 'Zed ${i.toString().padLeft(2, '0')}',
        ]),
      );
      await tester.pumpAndSettle();
      final room = CupolaRoom.of(tester.element(find.byType(MediaBrowseIndex)));

      for (final letter in ['#', 'E', 'O', 'Z']) {
        expect(_inkOf(tester, letter), room.ink, reason: letter);
      }
      expect(_inkOf(tester, 'A'), room.inkDisabled);

      // `#` is the top of the strip and of the wall.
      expect(_at(tester, '#').dy, lessThan(_at(tester, 'A').dy));
      await _jump(tester, 'O');
      expect(
        _headingTop(tester, 'O'),
        closeTo(_bodyTop(tester) + _landing, 0.01),
      );
    });
  });

  group('a jump on a long wall', () {
    testWidgets('lands the heading at the top of the body, under a bar', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();

      // Several hundred titles: the sections are far below anything built.
      expect(_titles().length, greaterThan(300));
      // Z straight after M is a jump over a stretch nothing has built.
      for (final letter in ['M', 'Z', 'C', 'N', 'K']) {
        await _jump(tester, letter);
        expect(
          _headingTop(tester, letter),
          closeTo(_bodyTop(tester) + _landing, 0.01),
          reason: letter,
        );
      }
    });

    testWidgets('the first section lands at the top of the wall, whichever '
        'letter it is', (tester) async {
      await _phone(tester);
      // Digits sort first, so `#` is the wall's first heading here, and `A`
      // the second.
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();
      await _jump(tester, 'M');

      await _jump(tester, '#');

      // It cannot land lower than it starts: the wall's own margin above it.
      expect(_position(tester).pixels, 0);
      expect(
        _headingTop(tester, '#'),
        closeTo(_bodyTop(tester) + AppSpacing.sm, 0.01),
      );

      await _jump(tester, 'A');
      expect(
        _headingTop(tester, 'A'),
        closeTo(_bodyTop(tester) + _landing, 0.01),
      );
    });

    testWidgets('folds the header away, and the heading is not under it', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();
      final before = _bodyTop(tester);
      expect(before, greaterThan(150), reason: 'the header is showing');

      await _jump(tester, 'M');

      expect(_bodyTop(tester), lessThan(before));
      expect(
        _headingTop(tester, 'M'),
        greaterThan(tester.getBottomLeft(find.byType(GlassAppBar)).dy),
      );
    });

    testWidgets('is exact at twice the reading size, where captions grow', (
      tester,
    ) async {
      await _phone(tester, scale: 2);
      await tester.pumpWidget(_wall(_titles()));
      await tester.pumpAndSettle();

      for (final letter in ['T', 'F', 'B']) {
        await _jump(tester, letter);
        expect(
          _headingTop(tester, letter),
          closeTo(_bodyTop(tester) + _landing, 0.01),
          reason: letter,
        );
      }
    });

    testWidgets('is exact over posters, and over a wall with no captions', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _wall(
          _titles(),
          shape: MediaBrowseTileShape.poster,
          subtitle: (_) => '',
        ),
      );
      await tester.pumpAndSettle();

      for (final letter in ['S', 'D']) {
        await _jump(tester, letter);
        expect(
          _headingTop(tester, letter),
          closeTo(_bodyTop(tester) + _landing, 0.01),
          reason: letter,
        );
      }
    });

    testWidgets('lands under the chrome a service tab lays over the page', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _wall(_titles(), showAppBar: false, topPadding: 100),
      );
      await tester.pumpAndSettle();
      // The header is showing and the page's chrome is above it: the strip is
      // in the body, under it.
      expect(_strip(tester).top, greaterThanOrEqualTo(100));

      await _jump(tester, 'M');

      expect(_bodyTop(tester), 0);
      expect(
        _headingTop(tester, 'M'),
        closeTo(100 + AppSpacing.sm, 0.01),
        reason: 'under the 100 of chrome, with the wall\'s own margin',
      );
      // And the strip clears it too, now that the header is gone.
      expect(_strip(tester).top, greaterThanOrEqualTo(100));
    });

    testWidgets('a letter whose section is shorter than the page lands as far '
        'as the wall goes, and stays there', (tester) async {
      await _phone(tester);
      // The last section is a single row, much shorter than the page.
      final titles = [..._titles(letters: 'ABCDEFGH'), 'Zed', 'Zebra'];
      await tester.pumpWidget(_wall(titles));
      await tester.pumpAndSettle();

      await _jump(tester, 'Z');
      // A second past the settle: nothing is pulling it back.
      await tester.pump(const Duration(seconds: 1));

      final position = _position(tester);
      expect(position.pixels, position.maxScrollExtent);
      expect(
        _headingTop(tester, 'Z'),
        greaterThan(_bodyTop(tester) + _landing),
      );
    });
  });
}
