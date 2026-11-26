import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_bottom_sheet.dart';

/// A page at [size] with a button that opens what [open] opens.
Future<void> _pump(
  WidgetTester tester,
  Size size,
  void Function(BuildContext button) open,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topRight,
          child: Builder(
            builder: (button) => IconButton(
              key: const ValueKey('more'),
              icon: const Icon(Icons.more_horiz),
              onPressed: () => open(button),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('more')));
  await tester.pumpAndSettle();
}

/// The dialog's panel.
Size _panel(WidgetTester tester) => tester.getSize(
  find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first,
);

void _picker(BuildContext context) => AppBottomSheet.show<void>(
  context: context,
  title: 'Quality profile',
  builder: (_) => const Text('HD-1080p'),
);

void main() {
  testWidgets('on a phone a sheet rises from the bottom, with its handle', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844), _picker);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AppSheetHandle), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('a phone on its side keeps the sheet: 900 wide, 430 tall', (
    tester,
  ) async {
    await _pump(tester, const Size(900, 430), _picker);

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('where there is room it is a dialog: 520 wide, a close button, '
      'no handle, and Esc closes it', (tester) async {
    await _pump(tester, const Size(1024, 768), _picker);

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AppSheetHandle), findsNothing);
    expect(find.byType(CloseButton), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(_panel(tester).width, 520);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('HD-1080p'), findsNothing);
  });

  testWidgets('a long list is a tall dialog at 680', (tester) async {
    await _pump(
      tester,
      const Size(1280, 800),
      (context) => AppBottomSheet.showScrollable<void>(
        context: context,
        title: 'Interactive search',
        builder: (_, controller) => ListView(
          controller: controller,
          children: [for (var i = 0; i < 40; i++) Text('Release $i')],
        ),
      ),
    );

    final size = _panel(tester);
    expect(size.width, 680);
    expect(size.height, 800 * 0.85);
  });

  group('the actions of an artist\'s page', () {});
}
