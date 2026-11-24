import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/discover/domain/seerr_sign_in.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/plex/data/plex_client.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/readarr/data/readarr_service.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/unraid/data/unraid_client.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/capturing_http_adapter.dart';
import '../../../test_helpers/fixtures.dart';
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

/// Answers the author list and refuses the queue, which is the half-broken
/// Readarr the queue KPI had no way to draw: `getQueue` swallowed its own
/// failure, so the rail read `Queue 0` over a queue nobody had read.
class _ReadarrClientWithDeadQueue extends FakeApiClient {
  @override
  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) {
    if (path.contains('queue')) throw Exception('queue unreachable');
    return super.get(
      path,
      queryParameters: queryParameters,
      cancelToken: cancelToken,
      receiveTimeout: receiveTimeout,
    );
  }
}

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

    test('Lidarr prints em dashes, not "Artists 0"', () async {
      final kpis = await _kpisFor(ServiceKey.lidarr, [
        lidarrServiceProvider.overrideWithValue(LidarrService(_deadClient())),
      ]);

      expect(kpis['Artists']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Albums']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Tracks']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
    });

    test('Readarr prints em dashes, not "Authors 0"', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrServiceProvider.overrideWithValue(ReadarrService(_deadClient())),
      ]);

      expect(kpis['Authors']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Books']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Missing']!.value, ServiceKpi.unavailableValue);
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

  group('stream server KPIs preserve reachability', () {
    test(
      'an answered empty Jellyfin server still reports real zeroes',
      () async {
        final client = JellyfinClient(
          baseUrl: 'https://jellyfin.test',
          apiKey: 'key',
          deviceName: 'test',
          deviceId: 'test-device',
        );
        client.dio.httpClientAdapter = CapturingHttpAdapter(response: const []);
        addTearDown(client.close);

        final container = ProviderContainer(
          overrides: [jellyfinClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        final kpis = _byLabel(
          await container.read(serviceKpiProvider(ServiceKey.jellyfin).future),
        );
        expect(kpis['Streams']!.value, '0');
        expect(kpis['Transcodes']!.value, '0');
        expect(kpis['Libraries']!.value, '0');
      },
    );

    test('Jellyfin transport failure reaches the KPI provider', () async {
      final client = JellyfinClient(
        baseUrl: 'https://jellyfin.test',
        apiKey: 'key',
        deviceName: 'test',
        deviceId: 'test-device',
      );
      client.dio.httpClientAdapter = CapturingHttpAdapter(
        response: '',
        statusCode: 500,
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [jellyfinClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(serviceKpiProvider(ServiceKey.jellyfin).future),
        throwsA(isA<DioException>()),
      );
    });

    test('an answered empty Plex server still reports real zeroes', () async {
      final client = PlexClient(
        url: 'https://plex.test:32400',
        token: 'token',
        clientIdentifier: 'test-client',
        platform: 'macOS',
      );
      client.api.dio.httpClientAdapter = CapturingHttpAdapter(
        response: const {
          'MediaContainer': {'size': 0},
        },
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [plexClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      final kpis = _byLabel(
        await container.read(serviceKpiProvider(ServiceKey.plex).future),
      );
      expect(kpis['Streams']!.value, '0');
      expect(kpis['Transcodes']!.value, '0');
      expect(kpis['Libraries']!.value, '0');
    });

    test('Plex transport failure reaches the KPI provider', () async {
      final client = PlexClient(
        url: 'https://plex.test:32400',
        token: 'token',
        clientIdentifier: 'test-client',
        platform: 'macOS',
      );
      client.api.dio.httpClientAdapter = CapturingHttpAdapter(
        response: '',
        statusCode: 500,
      );
      addTearDown(client.close);

      final container = ProviderContainer(
        overrides: [plexClientProvider.overrideWithValue(client)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(serviceKpiProvider(ServiceKey.plex).future),
        throwsA(isA<PlexException>()),
      );
    });

    test('a named Plex connection reads its own KPI source', () async {
      const lens = ServiceInstance(
        id: 'plex',
        service: ServiceKey.plex,
        label: 'Home',
        url: 'https://plex-home.test',
        credential: 'home-token',
      );
      const other = ServiceInstance(
        id: 'plex-away',
        service: ServiceKey.plex,
        label: 'Away',
        url: 'https://plex-away.test',
        credential: 'away-token',
      );

      PlexClient client({required int libraryCount}) {
        final value = PlexClient(
          url: 'https://plex.test:32400',
          token: 'token',
          clientIdentifier: 'test-client',
          platform: 'macOS',
        );
        value.api.dio.httpClientAdapter = CapturingHttpAdapter(
          byPath: {
            '/status/sessions': const {
              'MediaContainer': {'size': 0, 'Metadata': []},
            },
            '/library/sections': {
              'MediaContainer': {
                'size': libraryCount,
                'Directory': [
                  for (var i = 0; i < libraryCount; i++)
                    {'key': '$i', 'type': 'movie', 'title': 'Library $i'},
                ],
              },
            },
          },
        );
        addTearDown(value.close);
        return value;
      }

      final homeClient = client(libraryCount: 1);
      final awayClient = client(libraryCount: 3);
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWithValue(
            const SettingsModel(instances: [lens, other]),
          ),
          plexClientProvider.overrideWithValue(homeClient),
          plexClientForProvider.overrideWith((ref, instanceId) => awayClient),
        ],
      );
      addTearDown(container.dispose);

      final kpis = await container.read(
        serviceKpiForProvider((
          service: ServiceKey.plex,
          instanceId: other.id,
        )).future,
      );

      expect(kpis, isNotNull);
      expect(kpis!.firstWhere((kpi) => kpi.label == 'Libraries').value, '3');
    });
  });

  group('Readarr queue', () {
    test('a queue endpoint that is down reads "—", not an idle 0', () async {
      // The library answers and the queue does not, which is the ordinary
      // shape of a half-broken Readarr. Three figures are real; only the
      // fourth is unknown, and only the fourth says so.
      final client = _ReadarrClientWithDeadQueue()
        ..getResponseData = <dynamic>[
          {
            'id': 1,
            'authorName': 'Le Guin',
            'statistics': {'bookCount': 4, 'bookFileCount': 4},
          },
        ];
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrServiceProvider.overrideWithValue(ReadarrService(client)),
      ]);

      expect(kpis['Authors']!.value, '1');
      expect(kpis['Queue']!.value, ServiceKpi.unavailableValue);
      expect(kpis['Queue']!.note, isNotNull);
      // The reason belongs to the figure that has it: naming the whole service
      // here would read as "Readarr is down" over three figures Readarr just
      // answered.
      expect(kpis['Authors']!.note, isNull);
    });
  });

  group('a queue figure is only as much as the walk read', () {
    // A proxy that drops `totalRecords` stops the queue walk on its first
    // full page. The rails counted the rows and stated them as the queue.
    final fullPage = [
      for (var i = 0; i < 200; i++) {'id': i, 'movieId': i + 1},
    ];

    test('Readarr states the server\'s own count over the rows', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrKpiLibraryProvider.overrideWith((ref) async => const []),
        readarrQueueProvider.overrideWith(
          (ref) async => ArrRecordPage(
            records: fullPage.take(3).toList(),
            total: 340,
            cutShort: true,
          ),
        ),
      ]);

      expect(kpis['Queue']!.value, '340');
    });

    test('Readarr reads 200+ for a full page with no count', () async {
      final kpis = await _kpisFor(ServiceKey.readarr, [
        readarrKpiLibraryProvider.overrideWith((ref) async => const []),
        readarrQueueProvider.overrideWith(
          (ref) async =>
              ArrRecordPage(records: fullPage, total: null, cutShort: true),
        ),
      ]);

      expect(kpis['Queue']!.value, '200+');
      expect(kpis['Queue']!.semanticLabel, 'Queue: at least 200');
    });

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

/// Answers each Unraid GraphQL document by what it asks for: the array, the
/// containers, or a refusal. Both documents go to the same `/graphql`, so a
/// per-path adapter cannot tell them apart.
class _UnraidAdapter implements HttpClientAdapter {
  _UnraidAdapter({this.array = true, this.docker = true});

  final bool array;
  final bool docker;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final query = (options.data as Map)['query'] as String;
    final (fixture, answers) = query.contains('array {')
        ? ('unraid/array.json', array)
        : ('unraid/docker.json', docker);
    return answers
        ? ResponseBody.fromString(
            jsonEncode(jsonFixtureMap(fixture)),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          )
        : ResponseBody.fromString(
            jsonEncode({
              'errors': [
                {
                  'message': 'This read failed',
                  'extensions': {'code': 'INTERNAL_SERVER_ERROR'},
                },
              ],
            }),
            500,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
  }
}

UnraidClient _unraidClient({bool array = true, bool docker = true}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://unraid.test'))
    ..httpClientAdapter = _UnraidAdapter(array: array, docker: docker);
  final client = UnraidClient(
    url: 'https://unraid.test',
    apiKey: 'key',
    dio: dio,
  );
  addTearDown(client.close);
  return client;
}

void _expectArrayFigures(Map<String, ServiceKpi> kpis, {required bool kept}) {
  for (final label in ['Array', 'Used', 'Disks']) {
    expect(
      kpis[label]!.isUnavailable,
      !kept,
      reason: '$label ${kept ? 'keeps its value' : 'reads —'}',
    );
    if (!kept) expect(kpis[label]!.note, isNull, reason: '$label has no note');
  }
}

void _expectContainersFigure(
  Map<String, ServiceKpi> kpis, {
  required bool kept,
}) {
  expect(kpis['Containers']!.isUnavailable, !kept);
  if (kept) {
    expect(kpis['Containers']!.value, '1/2');
  } else {
    expect(kpis['Containers']!.note, isNull);
  }
}

void _unraidRailTests() {
  group('Unraid rail degrades per document', () {
    // The lens path reads the two providers the pages already load; the
    // per-connection path reads its own client. Same rule on both.
    const lensInstance = ServiceInstance(
      id: 'unraid',
      service: ServiceKey.unraid,
      label: 'Home',
      url: 'https://unraid-home.test',
      credential: 'home-key',
    );
    const otherInstance = ServiceInstance(
      id: 'unraid-away',
      service: ServiceKey.unraid,
      label: 'Away',
      url: 'https://unraid-away.test',
      credential: 'away-key',
    );

    final arrayValue = UnraidArray.fromJson(
      (jsonFixtureMap('unraid/array.json')['data'] as Map)['array']
          as Map<String, dynamic>,
    );
    final containers = [
      for (final c
          in ((jsonFixtureMap('unraid/docker.json')['data'] as Map)['docker']
                  as Map)['containers']
              as List)
        UnraidDockerContainer.fromJson((c as Map).cast<String, dynamic>()),
    ];

    Future<List<ServiceKpi>> lens({
      required bool arrayFails,
      required bool dockerFails,
    }) {
      final container = ProviderContainer(
        overrides: [
          unraidArrayProvider.overrideWith(
            (ref) async =>
                arrayFails ? throw Exception('array down') : arrayValue,
          ),
          unraidDockerProvider.overrideWith(
            (ref) async =>
                dockerFails ? throw Exception('docker down') : containers,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(serviceKpiProvider(ServiceKey.unraid).future);
    }

    Future<List<ServiceKpi>?> connection({
      bool array = true,
      bool docker = true,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWithValue(
            const SettingsModel(instances: [lensInstance, otherInstance]),
          ),
          unraidClientForProvider.overrideWith(
            (ref, id) => _unraidClient(array: array, docker: docker),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(
        serviceKpiForProvider((
          service: ServiceKey.unraid,
          instanceId: otherInstance.id,
        )).future,
      );
    }

    test('both documents answer: four figures with values', () async {
      final kpis = _byLabel(await lens(arrayFails: false, dockerFails: false));
      _expectArrayFigures(kpis, kept: true);
      _expectContainersFigure(kpis, kept: true);
      expect(kpis.keys, ['Array', 'Used', 'Containers', 'Disks']);
    });

    test(
      'lens: Docker failing leaves Array, Used and Disks standing',
      () async {
        final baseline = _byLabel(
          await lens(arrayFails: false, dockerFails: false),
        );
        final kpis = _byLabel(await lens(arrayFails: false, dockerFails: true));

        _expectArrayFigures(kpis, kept: true);
        _expectContainersFigure(kpis, kept: false);
        for (final label in ['Array', 'Used', 'Disks']) {
          expect(kpis[label]!.value, baseline[label]!.value);
        }
      },
    );

    test('lens: the array failing leaves Containers standing', () async {
      final kpis = _byLabel(await lens(arrayFails: true, dockerFails: false));

      _expectArrayFigures(kpis, kept: false);
      _expectContainersFigure(kpis, kept: true);
    });

    test('lens: both failing fails the rail, into its single card', () async {
      await expectLater(
        lens(arrayFails: true, dockerFails: true),
        throwsA(isA<Exception>()),
      );
    });

    test('connection: Docker failing leaves the array figures', () async {
      final kpis = _byLabel((await connection(docker: false))!);

      _expectArrayFigures(kpis, kept: true);
      _expectContainersFigure(kpis, kept: false);
    });

    test('connection: the array failing leaves Containers', () async {
      final kpis = _byLabel((await connection(array: false))!);

      _expectArrayFigures(kpis, kept: false);
      _expectContainersFigure(kpis, kept: true);
    });

    test('connection: both failing fails the rail', () async {
      await expectLater(
        connection(array: false, docker: false),
        throwsA(isA<UnraidException>()),
      );
    });

    test('connection: both answering gives the same four figures', () async {
      final kpis = _byLabel((await connection())!);
      _expectArrayFigures(kpis, kept: true);
      _expectContainersFigure(kpis, kept: true);
    });
  });
}
