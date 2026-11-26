/// Back while a library selects, in the shape the app is built in: the wall
/// lives in a nested navigator (a service's tabs) inside a page that was
/// pushed over another. The swipe is the gesture of that outer route, and a
/// `PopScope` under the inner navigator never hears it.
library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _query = StateProvider<String>((ref) => '');
final _library = FutureProvider<List<String>>(
  (ref) async => const ['Anton Bruckner', 'Bill Evans'],
);

Widget _wall() => MediaBrowseScaffold<String>(
  title: 'Music',
  searchHint: 'Search',
  activityRoute: '/activity',
  navigationSection: NavigationSection.stack,
  serviceName: 'Lidarr',
  service: ServiceKey.sonarr,
  heroTagPrefix: 'series',
  libraryProvider: _library,
  searchQueryProvider: _query,
  find: MediaFind.libraryOnly(libraryBody: (context, query) => Text(query)),
  titleExtractor: (title) => title,
  subtitleExtractor: (_) => '',
  imagesExtractor: (_) => null,
  idExtractor: (title) => title.hashCode,
  settingsSelector: (_) => ('', '', const NoAccess()),
  onItemTap: (_, _, _) {},
  showAppBar: false,
  tileShape: MediaBrowseTileShape.circle,
  bulk: MediaBulk<String>(
    singular: 'series',
    plural: 'series',
    noneHint: 'Select a series first',
    service: ServiceKey.sonarr,
    instanceId: '',
    actions: [
      MediaBulkAction<String>(
        label: 'Search',
        icon: Icons.search_rounded,
        prepare: (context, titles) async => null,
      ),
    ],
  ),
);

/// The page pushed over `Base`: the guard, and a nested navigator with
/// [inner] as its first route.
Future<(LibrarySelectionController, PageRoute<void>)> _pump(
  WidgetTester tester,
  Widget Function() inner,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = LibrarySelectionController();
  addTearDown(controller.dispose);
  final navigator = GlobalKey<NavigatorState>();
  final route = CupertinoPageRoute<void>(
    builder: (_) => LibrarySelectionBackGuard(
      child: Navigator(
        onGenerateRoute: (_) =>
            MaterialPageRoute<void>(builder: (_) => inner()),
      ),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      ],
      child: MaterialApp(
        navigatorKey: navigator,
        home: LibrarySelectionScope(
          controller: controller,
          child: const Scaffold(body: Text('Base')),
        ),
        builder: (context, child) =>
            LibrarySelectionScope(controller: controller, child: child!),
      ),
    ),
  );
  navigator.currentState!.push(route);
  await tester.pumpAndSettle();
  return (controller, route);
}

void main() {
  testWidgets('while the wall selects, the page it is in cannot be swiped '
      'away, and Back ends the selection and stays', (tester) async {
    final (controller, route) = await _pump(tester, _wall);
    expect(find.text('Bill Evans'), findsOneWidget);
    expect(
      (route as CupertinoRouteTransitionMixin).popGestureEnabled,
      isTrue,
      reason: 'at rest the page swipes back as ever',
    );

    await tester.longPress(find.text('Bill Evans'));
    await tester.pumpAndSettle();
    expect(controller.isSelecting, isTrue);
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      route.popGestureEnabled,
      isFalse,
      reason: 'the outer route’s swipe is off while a library selects',
    );
    expect(route.popDisposition, RoutePopDisposition.doNotPop);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(controller.isSelecting, isFalse);
    expect(
      find.text('Bill Evans'),
      findsOneWidget,
      reason: 'still on the wall',
    );
    expect(find.text('Base'), findsNothing);
    expect(route.popGestureEnabled, isTrue);

    // Selection over, Back pops the page as before.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('Bill Evans'), findsNothing);
  });

  testWidgets('the guard alone holds the outer route: a Back it hears asks '
      'the library to cancel, and pops nothing', (tester) async {
    // No wall of its own here, so nothing under the inner navigator can answer.
    final (controller, route) = await _pump(
      tester,
      () => const Scaffold(body: Text('Inside')),
    );
    var cancelled = 0;
    final owner = Object();
    controller.claim(
      owner,
      onCancel: () {
        cancelled++;
        controller.release(owner);
      },
    );
    await tester.pumpAndSettle();
    expect((route as CupertinoRouteTransitionMixin).popGestureEnabled, isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(cancelled, 1);
    expect(find.text('Inside'), findsOneWidget);
    expect(find.text('Base'), findsNothing);
  });

  test('the service page, the outer route of every service’s tabs, holds the '
      'guard', () {
    expect(
      File(
        'lib/features/services/presentation/service_home_screen.dart',
      ).readAsStringSync(),
      contains('LibrarySelectionBackGuard('),
    );
  });
}
