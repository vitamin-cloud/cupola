import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/settings_scope.dart';

SeerrRequest _request({
  required int id,
  RequestStatus status = RequestStatus.completed,
  SeerrMediaAvailability mediaStatus = SeerrMediaAvailability.unknown,
}) => SeerrRequest(
  id: id,
  status: status,
  media: RequestMedia(title: 'Title $id', tmdbId: id, status: mediaStatus),
  createdAt: '2024-01-01T00:00:00Z',
  type: 'movie',
);

/// The rail of a Seerr read with the operator's key and [open] issues: a
/// null [open] is a count that does not answer. [permissions] makes the
/// connection an account of those rights instead of the key.
Future<List<ServiceKpi>> _seerrRail(
  List<SeerrRequest> requests, {
  int? open = 0,
  int? permissions,
}) async {
  final base = settingsWith(seerrUrl: 'https://seerr.test', seerrApiKey: 'key');
  final instance = base.instancesOf(ServiceKey.seerr).first;
  final settings = permissions == null
      ? base
      : base.copyWithInstance(
          instance.copyWith(
            credential: '',
            account: SeerrAccountSignIn(
              kind: SeerrAccountKind.local,
              login: 'luca',
              userId: 7,
              displayName: 'Luca',
              session: 'session',
              permissions: permissions,
            ),
          ),
        );
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWithValue(settings),
      requestRowsProvider.overrideWith((ref) async => requests),
      issueCountProvider.overrideWith(
        (ref, id) async => open == null
            ? throw Exception('no count')
            : SeerrIssueCount(open: open),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container.read(serviceKpiProvider(ServiceKey.seerr).future);
}

Future<Map<String, String>> _seerrKpis(List<SeerrRequest> requests) async {
  final kpis = await _seerrRail(requests);
  return {for (final ServiceKpi kpi in kpis) kpi.label: kpi.value};
}

/// A real service over a client that fails every GET.
///
/// The gap the defect lives in is between "the library is empty" and "nobody
/// answered", and the only way to stand in it is to let the transport fail the
/// way it fails in the field. A hand-written fake that returns `[]` *is* the
/// bug, so it cannot be the harness that catches it.
FakeApiClient _deadClient() =>
    FakeApiClient()..getException = Exception('unreachable');

Map<String, ServiceKpi> _byLabel(List<ServiceKpi> kpis) => {
  for (final kpi in kpis) kpi.label: kpi,
};

Future<Map<String, ServiceKpi>> _kpisFor(
  ServiceKey service,
  List<Override> overrides,
) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  return _byLabel(await container.read(serviceKpiProvider(service).future));
}

void main() {
  _unraidRailTests();
  group('Seerr KPIs', () {
    test('counts pending approvals off the request, not the media', () async {
      // The trap: `displayStatus` checks `media.status` first, so a request
      // still awaiting a human reports "Available" the moment Radarr has the
      // file. Counting off it showed "Pending 0" on the dashboard while
      // /activity was offering an Approve button for the same record.
      final pendingButAvailable = _request(
        id: 1,
        status: RequestStatus.pendingApproval,
        mediaStatus: SeerrMediaAvailability.available,
      );
      expect(pendingButAvailable.displayStatus.label, 'Available');

      final kpis = await _seerrKpis([pendingButAvailable]);

      expect(kpis['Waiting for approval'], '1');
      // Its media really is available, and that tile is about the media.
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '1');
    });

    test('counts an ordinary pending request once', () async {
      final kpis = await _seerrKpis([
        _request(id: 1, status: RequestStatus.pendingApproval),
      ]);

      expect(kpis['Waiting for approval'], '1');
      expect(kpis['Processing'], '0');
      expect(kpis['Available'], '0');
    });

    test('does not count settled requests as pending', () async {
      final kpis = await _seerrKpis([
        _request(
          id: 1,
          status: RequestStatus.approved,
          mediaStatus: SeerrMediaAvailability.processing,
        ),
        _request(
          id: 2,
          status: RequestStatus.completed,
          mediaStatus: SeerrMediaAvailability.available,
        ),
        _request(id: 3, status: RequestStatus.declined),
      ]);

      expect(kpis['Waiting for approval'], '0');
      expect(kpis['Processing'], '1');
      expect(kpis['Available'], '1');
      expect(kpis['Requests'], '3');
    });
  });

  group('Seerr Open problems', () {
    final requests = [_request(id: 1)];

    test(
      'reads Seerr\'s own count, amber above zero, before Available',
      () async {
        final kpis = await _seerrRail(requests, open: 3);

        expect(
          [for (final kpi in kpis) kpi.label],
          [
            'Requests',
            'Waiting for approval',
            'Processing',
            'Open problems',
            'Available',
          ],
        );
        final problems = _byLabel(kpis)['Open problems']!;
        expect(problems.value, '3');
        expect(problems.tone, StatusTone.warning);
        // Amber in Seerr's Overview, and no card or band reads it.
        expect(problems.overviewOnly, isTrue);
      },
    );

    test('nothing open reads 0 and carries no tone', () async {
      final problems = _byLabel(await _seerrRail(requests))['Open problems']!;

      expect(problems.value, '0');
      expect(problems.tone, isNull);
    });

    test('a count that did not answer reads a dash, never 0', () async {
      final problems = _byLabel(
        await _seerrRail(requests, open: null),
      )['Open problems']!;

      expect(problems.isUnavailable, isTrue);
      expect(problems.overviewOnly, isTrue);
      expect(problems.value, ServiceKpi.unavailableValue);
    });

    test('an account that may not view issues has no readout', () async {
      // REQUEST alone: Seerr would refuse the count, so nothing is asked.
      final kpis = await _seerrRail(requests, open: 4, permissions: 32);

      expect(_byLabel(kpis), isNot(contains('Open problems')));
    });

    test('an account that may view them reads the count', () async {
      final kpis = await _seerrRail(
        requests,
        open: 2,
        permissions: SeerrPermission.viewIssues.value,
      );

      expect(_byLabel(kpis)['Open problems']!.value, '2');
    });
  });

  test('two Seerr fold only the readouts both have: the fleet card keeps its '
      'figures when one account may not view issues', () {
    List<ServiceKpi> rail({required bool problems}) => [
      const ServiceKpi(label: 'Processing', value: '1', icon: Icons.sync),
      if (problems)
        const ServiceKpi(label: 'Open problems', value: '2', icon: Icons.flag),
    ];

    final folded = aggregateServiceKpis(
      withCommonOpenProblems([rail(problems: true), rail(problems: false)]),
    );
    expect([for (final kpi in folded!) kpi.label], ['Processing']);

    final both = withCommonOpenProblems([
      rail(problems: true),
      rail(problems: true),
    ]);
    expect(aggregateServiceKpis(both)!.last.value, '4');
  });

  group('a *arr that did not answer states nothing', () {
    // Every figure below is derived from a library fetch that swallows its own
    // failure into `[]`. An unreachable server therefore resolved the rail
    // *successfully* with a full set of confident zeros, printed on the
    // Dashboard card and on the service home directly under an identity band
    // whose own probe already read Unreachable.

    test('Sonarr prints em dashes, not "Series 0"', () async {
      final kpis = await _kpisFor(ServiceKey.sonarr, [
        sonarrServiceProvider.overrideWithValue(SonarrService(_deadClient())),
      ]);

      expect(kpis['Series']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Episodes']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Monitored']!.value, ServiceKpi.unavailableValue);
      // One card says why; the other three keep their own labels, because four
      // identical reasons is a rail nobody can read a figure off.
      expect(kpis['Series']!.note, isNotNull);
      // Untoned on purpose: an absence is neither a fault nor a backlog.
      expect(kpis.values.every((kpi) => kpi.tone == null), isTrue);
    });

    test('Radarr prints em dashes, not "Movies 0"', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrServiceProvider.overrideWithValue(RadarrService(_deadClient())),
      ]);

      expect(kpis['Movies']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Monitored']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
      // The queue figure is a count off the same dark server: a snapshot that
      // degrades to empty cannot be told from a queue that drained.
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
    });

    test('a library that really is empty still reads zero', () async {
      // The other half of the pair. An em dash for an answered-and-empty
      // library would be the same lie pointing the other way.
      final client = FakeApiClient()..getResponseData = <dynamic>[];
      final kpis = await _kpisFor(ServiceKey.sonarr, [
        sonarrServiceProvider.overrideWithValue(SonarrService(client)),
      ]);

      expect(kpis['Series']!.value, '0');
      expect(kpis['Series']!.note, isNull);
    });
  });

  group('stream server KPIs preserve reachability', () {});

  group('Readarr queue', () {});

  group('a queue figure is only as much as the walk read', () {
    // A proxy that drops `totalRecords` stops the queue walk on its first
    // full page. The rails counted the rows and stated them as the queue.
    final fullPage = [
      for (var i = 0; i < 200; i++) {'id': i, 'movieId': i + 1},
    ];

    test('Radarr reads 200+ over a queue snapshot cut short', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.fromQueueItems(
            fullPage,
            idsFor: (item) => [item['movieId'] as int],
            cutShort: true,
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '200+');
    });

    test('Radarr reads the queue it read to the end as it is', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.fromQueueItems(
            fullPage.take(3),
            idsFor: (item) => [item['movieId'] as int],
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '3');
    });

    test('Radarr: a queue that did not answer under a library that did '
        'reads "—" with its own reason, never Queue 0', () async {
      final kpis = await _kpisFor(ServiceKey.radarr, [
        radarrKpiLibraryProvider.overrideWith((ref) async => const []),
        radarrQueueSnapshotProvider.overrideWith(
          (ref) async => ArrQueueSnapshot.failed(Exception('queue down')),
        ),
      ]);

      expect(kpis['Movies']!.value, '0');
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Queue']!.note, startsWith('Queue\u00A0· '));
      expect(kpis['Movies']!.note, isNull);
    });
  });
}

void _unraidRailTests() {}
