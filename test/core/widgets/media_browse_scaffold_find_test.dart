/// A wall that opts into [MediaFind] finds in two scopes, and a wall that
/// does not is left as it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: implementation_imports
import 'package:flutter_riverpod/legacy.dart';

import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_access.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

final _queryProvider = StateProvider<String>((ref) => '');
final _scopeProvider = StateProvider<MediaFindScope>(
  (ref) => MediaFindScope.library,
);
final _libraryProvider = FutureProvider<List<String>>(
  (ref) async => ['Alpha', 'Beta'],
);

/// The wall, with bodies that say which scope drew them and with what.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String? serviceLabel,
  double textScale = 1,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
    ],
  );
  addTearDown(container.dispose);
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: MediaBrowseScaffold<String>(
            title: 'Series',
            searchHint: 'Series',
            activityRoute: '/activity',
            navigationSection: NavigationSection.stack,
            serviceName: 'Sonarr',
            heroTagPrefix: 'a',
            libraryProvider: _libraryProvider,
            searchQueryProvider: _queryProvider,
            find: MediaFind(
              scopeProvider: _scopeProvider,
              serviceLabel: serviceLabel,
              libraryBody: (context, query) => Text('library:$query'),
              serviceBody: (context, query) => Text('service:$query'),
            ),
            titleExtractor: (item) => item,
            subtitleExtractor: (_) => '',
            imagesExtractor: (_) => null,
            idExtractor: (item) => item.hashCode,
            settingsSelector: (settings) => (
              settings.urlFor(ServiceKey.sonarr),
              settings.apiKeyFor(ServiceKey.sonarr),
              const NoAccess(),
            ),
            onItemTap: (_, _, _) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
}

Finder get _libraryCell => find.bySemanticsLabel('Your library');

void main() {
  testWidgets('no scope control while the field is empty', (tester) async {
    await _pump(tester);

    expect(find.text('Your library'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('typing opens the library scope at once, before the lookup '
      'debounce, with the control under the field', (tester) async {
    final container = await _pump(tester);

    await _type(tester, 'bjö');

    // The library answers from the first keystroke: nothing has waited 400ms.
    expect(find.text('library:bjö'), findsOneWidget);
    expect(container.read(_queryProvider), '');
    expect(find.text('Your library'), findsOneWidget);
    expect(find.text('Sonarr'), findsOneWidget);
    // The wall is gone behind the results.
    expect(find.text('Alpha'), findsNothing);

    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(_queryProvider), 'bjö');
  });

  testWidgets('the second segment carries the connection name', (tester) async {
    await _pump(tester, serviceLabel: 'Sonarr Hi-Fi');
    await _type(tester, 'el');

    expect(find.text('Sonarr Hi-Fi'), findsOneWidget);
  });

  testWidgets('switching scope keeps the text and hands the service the '
      'words as they are now', (tester) async {
    final container = await _pump(tester);
    await _type(tester, 'elbo');

    // Not yet through the debounce: the service would still ask for nothing.
    expect(container.read(_queryProvider), '');
    await tester.tap(find.text('Sonarr'));
    await tester.pump();

    expect(container.read(_scopeProvider), MediaFindScope.service);
    expect(container.read(_queryProvider), 'elbo');
    expect(find.text('service:elbo'), findsOneWidget);
    expect(find.text('library:elbo'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'elbo',
    );

    await tester.tap(find.text('Your library'));
    await tester.pump();

    expect(find.text('library:elbo'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'elbo',
    );
  });

  testWidgets('the segments are buttons with a selected state and a 44pt '
      'target', (tester) async {
    await _pump(tester);
    await _type(tester, 'el');
    final handle = tester.ensureSemantics();

    expect(
      tester.getSemantics(_libraryCell),
      matchesSemantics(
        label: 'Your library',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    for (final label in ['Your library', 'Sonarr']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(44), reason: label);
    }
    handle.dispose();
  });

  testWidgets('emptying the field ends the search, and the next one starts in '
      'the library', (tester) async {
    final container = await _pump(tester);
    await _type(tester, 'elbo');
    await tester.tap(find.text('Sonarr'));
    await tester.pump();
    expect(container.read(_scopeProvider), MediaFindScope.service);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    expect(find.text('service:elbo'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(container.read(_scopeProvider), MediaFindScope.library);
    expect(container.read(_queryProvider), '');
  });

  testWidgets('the back arrow leaves the search as it always did', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _type(tester, 'elbo');
    await tester.tap(find.text('Sonarr'));
    await tester.pump();

    await tester.tap(find.byTooltip('Exit search'));
    await tester.pump();

    expect(find.text('Alpha'), findsOneWidget);
    expect(container.read(_queryProvider), '');
    expect(container.read(_scopeProvider), MediaFindScope.library);
  });

  testWidgets('a link that arrives on the service scope with a word lands '
      'there, with the word in the field', (tester) async {
    final container = await _pump(tester);

    container.read(_scopeProvider.notifier).state = MediaFindScope.service;
    container.read(_queryProvider.notifier).state = 'elbow';
    await tester.pump();

    expect(find.text('service:elbow'), findsOneWidget);
    expect(find.text('library:elbow'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'elbow',
    );
  });

  testWidgets('a tap on the tab clears the search and the scope', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _type(tester, 'elbo');
    await tester.tap(find.text('Sonarr'));
    await tester.pump();

    container
        .read(navigationRefreshProvider(NavigationSection.stack).notifier)
        .state++;
    await tester.pumpAndSettle();

    expect(find.text('service:elbo'), findsNothing);
    expect(find.text('Alpha'), findsOneWidget);
    expect(container.read(_scopeProvider), MediaFindScope.library);
  });

  testWidgets('at 200% the segments fit without overflowing', (tester) async {
    await _pump(tester, textScale: 2, serviceLabel: 'Sonarr Hi-Fi');
    await _type(tester, 'el');

    expect(tester.takeException(), isNull);
  });
  testWidgets('a wall with only its library has no second scope and no '
      'control: the text finds in the library and nothing asks a service', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        currentSettingsProvider.overrideWith((ref) => const SettingsModel()),
      ],
    );
    addTearDown(container.dispose);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: MediaBrowseScaffold<String>(
            title: 'Authors',
            searchHint: 'Authors',
            activityRoute: '/activity',
            navigationSection: NavigationSection.stack,
            serviceName: 'Readarr',
            heroTagPrefix: 'a',
            libraryProvider: _libraryProvider,
            searchQueryProvider: _queryProvider,
            find: MediaFind.libraryOnly(
              libraryBody: (context, query) => Text('library:$query'),
            ),
            titleExtractor: (item) => item,
            subtitleExtractor: (_) => '',
            imagesExtractor: (_) => null,
            idExtractor: (item) => item.hashCode,
            settingsSelector: (settings) => (
              settings.urlFor(ServiceKey.radarr),
              settings.apiKeyFor(ServiceKey.radarr),
              const NoAccess(),
            ),
            onItemTap: (_, _, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _type(tester, 'jules');

    expect(find.text('library:jules'), findsOneWidget);
    expect(find.byType(MediaFindScopeControl), findsNothing);
    expect(find.text('Your library'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });
}
