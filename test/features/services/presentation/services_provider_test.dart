import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/api/api_client.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/movies/domain/radarr_status.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/home/domain/arrived.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_api_client.dart';
import '../../../test_helpers/fake_services.dart';
import '../../../test_helpers/model_builders.dart';

import '../../../test_helpers/settings_scope.dart';

void main() {
  group('serviceSummaryProvider', () {
    test('returns offline summary when service is not configured', () async {
      final container = _container();

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.service, ServiceKey.radarr);
      expect(summary.status, ServiceSummaryStatus.offline);
      expect(summary.host, isEmpty);
    });

    test('returns online summary with version', () async {
      final container = _container(
        settings: settingsWith(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _StatusClient({'version': '5.4.6'}),
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.online);
      expect(summary.host, 'radarr.local:7878');
      expect(summary.versionLabel, 'v5.4.6');
    });

    test('returns offline summary when status endpoint fails', () async {
      final container = _container(
        settings: settingsWith(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _ThrowingStatusClient(),
        radarrService: _MoviesRadarrService([buildMovie(title: 'Dune')]),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.offline);
      expect(summary.host, 'radarr.local:7878');
    });

    test('stays online when the library call fails', () async {
      final container = _container(
        settings: settingsWith(
          radarrUrl: 'http://radarr.local:7878',
          radarrApiKey: 'key',
        ),
        statusClient: _StatusClient({'version': '5.4.6'}),
        radarrService: _ThrowingMoviesRadarrService(),
      );

      final summary = await container.read(
        serviceSummaryProvider(ServiceKey.radarr).future,
      );

      expect(summary.status, ServiceSummaryStatus.online);
      // Reachability is settled by the version probe alone. The summary no
      // longer fetches a library count, so a failing library call cannot
      // downgrade it: that whole fetch was removed when the status card that
      // displayed the count gave way to the stack matrix's live signal.
      expect(summary.versionLabel, 'v5.4.6');
    });

    test(
      'Seerr health checks the API key before the public status endpoint',
      () async {
        final container = _container(
          settings: settingsWith(
            seerrUrl: 'http://seerr.local:5055',
            seerrApiKey: 'wrong',
          ),
          statusClient: _SeerrRejectingStatusClient(),
        );

        final summary = await container.read(
          serviceSummaryProvider(ServiceKey.seerr).future,
        );

        // Refused, and an answer: a fault, amber, never "did not answer".
        expect(summary.status, ServiceSummaryStatus.fault);
        expect(summary.failureReason, ServiceFailureReason.unauthorized);
      },
    );

    test('trusting a certificate for the origin re-probes the service', () async {
      // The subtlest field in the watched key, and the one whose absence would
      // be worst: answering the trust prompt is precisely the moment the probe
      // can start succeeding, so a summary that did not re-run would sit on
      // "offline" until something else happened to invalidate it.
      final status = _CountingStatusClient();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        statusClient: status,
      );

      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithTrustedCertificate(
              url: _secureRadarr.urlFor(ServiceKey.radarr),
              fingerprint: 'ab:cd:ef',
            ),
          );
      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);

      expect(status.calls, 2);
    });

    test('another service moving does not re-probe this one', () async {
      final status = _CountingStatusClient();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        statusClient: status,
      );

      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithService(
              ServiceKey.sonarr,
              url: 'https://sonarr.local:8989',
            ),
          );
      await container.read(serviceSummaryProvider(ServiceKey.radarr).future);

      expect(status.calls, 1);
    });
  });

  group('serviceSummaryProvider Bazarr', () {});

  group('servicesQueueProvider', () {
    // Both arrs configured: the provider now skips any source the user has not
    // set up, so an unconfigured service contributes nothing rather than a
    // failed fetch.
    final bothArrs = settingsWith(
      radarrUrl: 'http://radarr.local:7878',
      radarrApiKey: 'key',
      sonarrUrl: 'http://sonarr.local:8989',
      sonarrApiKey: 'key',
    );

    test(
      'combines Radarr and Sonarr queue items with media-first hierarchy',
      () async {
        final container = _container(
          settings: bothArrs,
          radarrService: _QueueRadarrService([
            {
              'title': 'Furiosa.2024.2160p.WEB-DL-GROUP',
              'status': 'downloading',
              'size': 100,
              'sizeleft': 25,
              'movie': {'title': 'Furiosa', 'year': 2024},
              'quality': {
                'quality': {'name': 'WEB-DL 1080p'},
              },
            },
          ]),
          sonarrService: _QueueSonarrService([
            {
              'title': 'The.Boys.S04E07.1080p.WEB-DL-GROUP',
              'status': 'downloading',
              'size': 200,
              'sizeleft': 100,
              'series': {'title': 'The Boys'},
              'episode': {'seasonNumber': 4, 'episodeNumber': 7},
              'trackedDownloadStatus': 'warning',
              'statusMessages': ['Unable to Import Automatically'],
            },
            {
              'title': 'Shogun',
              'series': {'title': 'Shogun'},
            },
            {'title': 'Slow Horses'},
          ]),
        );

        final items = (await container.read(
          servicesQueueProvider.future,
        )).items;

        // Ordered by progress, closest to landing first, with the two items
        // whose client reported no progress last and in source order.
        expect(items.map((item) => item.title), [
          'Furiosa',
          'The Boys\u00A0· S4\u00A0E7',
          'Shogun',
          'Slow Horses',
        ]);
        expect(items[0].service, ServiceKey.radarr);
        // The row's four fields are the row's four fields, whatever the source:
        // the quality the \*arr grabbed under, and the client actually moving
        // the bytes, which is the one fact a merged queue cannot leave to a
        // glyph. The pre-joined per-service subtitle is gone; see
        // `domain/in_flight.dart`.
        expect(items[0].quality, 'WEB-DL 1080p');
        expect(items[0].clientLabel, isNotEmpty);
        expect(items[0].progress, 0.75);
        expect(items[1].service, ServiceKey.sonarr);
        // A warning on a record whose bytes are still moving is not a fault.
        // "Any warning is a stall" was the rule that turned a blocked import
        // into "Open in qBittorrent" (APP-04): the record keeps the arr's own
        // words and stays in flight.
        expect(items[1].fault, isNull);
        expect(items[1].isActive, isTrue);
        expect(items[1].warning, isNotNull);
        expect(items[1].progress, 0.5);
        expect(items[2].progress, isNull);
        expect(items[3].progress, isNull);
      },
    );

    test('skips a source the user has not configured', () async {
      final container = _container(
        settings: settingsWith(
          sonarrUrl: 'http://sonarr.local:8989',
          sonarrApiKey: 'key',
        ),
        // Configured nowhere, so this must never be asked.
        radarrService: _ThrowingRadarrService(),
        sonarrService: _QueueSonarrService([
          {'title': 'Shogun', 'size': 100, 'sizeleft': 0},
        ]),
      );

      final items = (await container.read(servicesQueueProvider.future)).items;

      expect(items.single.service, ServiceKey.sonarr);
    });

    test('caps the preview and keeps the closest to landing', () async {
      final container = _container(
        settings: bothArrs,
        radarrService: _QueueRadarrService([
          for (var index = 0; index < 8; index++)
            {
              'title': 'Release $index',
              'size': 100,
              // Ascending progress, so the last ones added are the furthest
              // along and must be the ones that survive the cap.
              'sizeleft': 100 - (index * 10),
            },
        ]),
      );

      // The cap belongs to the *region*, not to the fetch: the decisions region
      // reads the same provider looking for stalls, and a list trimmed to five
      // before it got there could hide the stuck one behind five healthy
      // transfers.
      final all = (await container.read(servicesQueueProvider.future)).items;
      expect(all, hasLength(8));

      final inFlight = await container.read(servicesInFlightProvider.future);
      expect(inFlight.preview, hasLength(servicesQueuePreviewLimit));
      expect(inFlight.preview.first.title, 'Release 7');
      expect(inFlight.preview.last.title, 'Release 3');
      // APP-01: the eyebrow's figure is the count, not the preview's length:
      // eight transfers used to read "5 downloading".
      expect(inFlight.activeCount, 8);
    });

    test('a queue walk that stopped short makes the count a floor', () async {
      // A full page and no `totalRecords`: the walk had no reason to ask for
      // another page, and the region stated its rows as the queue.
      final container = _container(
        settings: bothArrs,
        radarrService: _PageRadarrService(
          ArrRecordPage(
            records: [
              for (var index = 0; index < 3; index++)
                {
                  'title': 'Release $index',
                  'downloadId': 'id-$index',
                  'size': 100,
                  'sizeleft': 50,
                },
            ],
            total: null,
            cutShort: true,
          ),
        ),
      );

      final inFlight = await container.read(servicesInFlightProvider.future);

      expect(inFlight.coverage.isFloor, isTrue);
      // Nobody failed, so there is no one to name under the figure.
      expect(coverageNote(inFlight.coverage), isNull);
    });

    test('a change to a source service does re-poll the queue', () async {
      // The other half: narrowing the watch must not make it deaf. Repointing
      // Radarr has to invalidate, or the preview keeps showing the old server's
      // queue.
      final radarr = _CountingQueueRadarrService();
      final container = _mutableSettingsContainer(
        initial: bothArrs,
        radarrService: radarr,
      );

      await container.read(servicesQueueProvider.future);
      container
          .read(_settingsHolderProvider.notifier)
          .set(
            bothArrs.copyWithService(
              ServiceKey.radarr,
              url: 'http://moved.local:7878',
            ),
          );
      await container.read(servicesQueueProvider.future);

      expect(radarr.calls, 2);
    });

    test('trusting a certificate for a source re-polls the queue', () async {
      // Every field of the watched key has to earn its place, and this is the
      // one a narrowing pass is most likely to drop: the pin is what lets a
      // self-signed host answer at all, so a queue that ignored it would stay
      // empty after the user answered the trust prompt.
      final radarr = _CountingQueueRadarrService();
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        radarrService: radarr,
      );

      await container.read(servicesQueueProvider.future);
      expect(radarr.calls, 1);

      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithTrustedCertificate(
              url: _secureRadarr.urlFor(ServiceKey.radarr),
              fingerprint: 'ab:cd:ef',
            ),
          );
      await container.read(servicesQueueProvider.future);

      expect(radarr.calls, 2);
    });

    test('keeps queue available when one service fails', () async {
      final container = _container(
        settings: bothArrs,
        radarrService: _ThrowingRadarrService(),
        sonarrService: _QueueSonarrService([
          {'title': 'Shogun', 'size': 100, 'sizeleft': 0},
        ]),
      );

      final queue = await container.read(servicesQueueProvider.future);
      final items = queue.items;

      expect(items, hasLength(1));
      expect(items.single.service, ServiceKey.sonarr);
      expect(items.single.title, 'Shogun');
      // And the failure is kept, not swallowed into an empty Radarr queue: the
      // count above the rows can only be a count of what answered.
      expect(queue.coverage.answered.map((source) => source.service), [
        ServiceKey.sonarr,
      ]);
      expect(queue.coverage.failedServices, {ServiceKey.radarr});
      expect(queue.coverage.isPartial, isTrue);
    });
  });

  // APP-02: the arr queues and the client queues were concatenated, so a
  // Radarr grab moving through qBittorrent was two rows and two in the count.
  group('one row per transfer', () {
    final radarrAndQb = settingsWith(
      radarrUrl: 'http://radarr.local:7878',
      radarrApiKey: 'key',
      qbittorrentUrl: 'http://qb.local:8080',
      qbittorrentUsername: 'admin',
      qbittorrentPassword: 'secret',
    );

    test(
      'an arr grab and the torrent moving it are one row, counted once',
      () async {
        final container = _container(
          settings: radarrAndQb,
          radarrService: _QueueRadarrService([
            {
              'id': 1,
              'title': 'Dune.Part.Two.2024.2160p.WEB-DL-GROUP',
              'status': 'downloading',
              'trackedDownloadState': 'downloading',
              // The arr's spelling of the hash is upper case; qBittorrent's is
              // lower. Same transfer.
              'downloadId': 'ABCDEF0123456789',
              'downloadClient': 'qBittorrent',
              'size': 100,
              'sizeleft': 50,
              'movieId': 12,
              'movie': {'title': 'Dune: Part Two'},
              'quality': {
                'quality': {'name': 'WEB-DL 2160p'},
              },
            },
          ]),
          overrides: [
            allTorrentsProvider.overrideWith(
              (ref) async => [
                _torrent('abcdef0123456789', 'Dune.Part.Two.2024', 0.8),
                // Added by hand: no arr claims it, so it stays a row of its own.
                _torrent('0000feed', 'debian-12.iso', 0.3),
              ],
            ),
          ],
        );

        final items = (await container.read(
          servicesQueueProvider.future,
        )).items;

        expect(items.map((item) => item.title), [
          'Dune: Part Two',
          'debian-12.iso',
        ]);
        final dune = items.first;
        // The arr row wins: it knows the title and the quality …
        expect(dune.service, ServiceKey.radarr);
        expect(dune.quality, 'WEB-DL 2160p');
        // … and the client lends it what only the client measures.
        expect(dune.progress, 0.8);
        expect(dune.clientService, ServiceKey.qbittorrent);

        final inFlight = await container.read(servicesInFlightProvider.future);
        expect(inFlight.activeCount, 2);
        // One client, its rate summed once, not once per row it contributed.
        expect(inFlight.clients, 1);
        expect(inFlight.rateBytesPerSecond, 2048);
      },
    );

    test(
      'a stall only the client has noticed is one decision, not two',
      () async {
        final container = _container(
          settings: radarrAndQb,
          radarrService: _QueueRadarrService([
            {
              'id': 1,
              'title': 'Furiosa.2024.1080p',
              'status': 'downloading',
              'trackedDownloadState': 'downloading',
              'downloadId': 'CAFE',
              'downloadClient': 'qBittorrent',
              'movie': {'title': 'Furiosa'},
            },
          ]),
          overrides: [
            allTorrentsProvider.overrideWith(
              (ref) async => [
                _torrent('cafe', 'Furiosa.2024.1080p', 0.4, state: 'stalledDL'),
              ],
            ),
          ],
        );

        final items = (await container.read(
          servicesQueueProvider.future,
        )).items;
        expect(items, hasLength(1));
        expect(items.single.fault, InFlightFault.stalled);

        final decisions = await _settledDecisions(container);
        expect(decisions, hasLength(1));
        expect(decisions.single.kind, DecisionKind.stalledDownload);
        expect(decisions.single.title, 'Furiosa');
        // The join names the client exactly, so the control opens it.
        expect(decisions.single.requiresService, ServiceKey.qbittorrent);
      },
    );

    test(
      'a tick of the client page does not start the arr queue again',
      () async {
        final radarr = _CountingQueueRadarrService();
        final container = _container(
          settings: radarrAndQb,
          radarrService: radarr,
          overrides: [
            allTorrentsProvider.overrideWith((ref) async => const []),
          ],
        );
        container.listen(servicesQueueProvider, (_, _) {});
        await container.read(servicesQueueProvider.future);
        expect(radarr.calls, 1);

        // The qBittorrent page's three-second tick: its list is read again.
        container.invalidate(allTorrentsProvider);
        await container.read(allTorrentsProvider.future);
        await Future<void>.delayed(Duration.zero);
        await container.read(servicesQueueProvider.future);
        expect(radarr.calls, 1);

        // A poll that reads the group again (Home, Activity, the desktop's) does.
        container.invalidate(servicesQueueProvider);
        await container.read(servicesQueueProvider.future);
        expect(radarr.calls, 2);
      },
    );

    test('a season pack is one download, not one row per episode', () async {
      final container = _container(
        settings: settingsWith(
          sonarrUrl: 'http://sonarr.local:8989',
          sonarrApiKey: 'key',
        ),
        sonarrService: _QueueSonarrService([
          for (var episode = 1; episode <= 3; episode++)
            {
              'id': episode,
              'title': 'The.Boys.S04.2160p',
              'status': 'downloading',
              'trackedDownloadState': 'downloading',
              'downloadId': 'PACKHASH',
              // Every record of a pack reports the pack's size.
              'size': 300,
              'sizeleft': 150,
              'seriesId': 5,
              'series': {'title': 'The Boys'},
              'episode': {'seasonNumber': 4, 'episodeNumber': episode},
            },
        ]),
      );

      final items = (await container.read(servicesQueueProvider.future)).items;

      expect(items, hasLength(1));
      expect(items.single.title, 'The Boys\u00A0· 3 episodes');
      // A sentence names it by its episodes: `The Boys S4\u00A0E1–E3 needs a
      // manual import`, never `The Boys · 3 episodes needs …`.
      expect(items.single.subject, 'The Boys S4\u00A0E1–E3');
      // The pack's figures once, never summed into three times its size.
      expect(items.single.totalBytes, 300);
      expect(items.single.progress, 0.5);
      expect(items.single.mediaId, 5);
    });
  });

  // APP-04: any arr warning used to mark a record stalled, so a finished
  // download the arr would not import became "Open in qBittorrent", and a queue
  // of blocked imports printed "The queue is empty".
  group('a blocked import', () {
    final sonarrOnly = settingsWith(
      sonarrUrl: 'http://sonarr.local:8989',
      sonarrApiKey: 'key',
    );

    Map<String, dynamic> blocked(int index, {int seriesId = 5}) => {
      'id': index,
      'title': 'Show.S01E${index.toString().padLeft(2, '0')}.1080p',
      'status': 'completed',
      'trackedDownloadState': 'importBlocked',
      'trackedDownloadStatus': 'warning',
      'statusMessages': ['No files found are eligible for import'],
      'downloadId': 'HASH$index',
      'downloadClient': 'qBittorrent',
      'size': 100,
      'sizeleft': 0,
      'seriesId': seriesId,
      'outputPath': '/downloads/Show.S01E$index/Show.S01E$index.mkv',
      'series': {'title': 'Show'},
      'episode': {'seasonNumber': 1, 'episodeNumber': index},
    };

    test('is a manual import, and eighteen of them are one decision', () async {
      final container = _container(
        settings: sonarrOnly,
        sonarrService: _QueueSonarrService([
          for (var i = 1; i <= 18; i++) blocked(i, seriesId: i),
        ]),
      );

      final inFlight = await container.read(servicesInFlightProvider.future);
      expect(inFlight.activeCount, 0);
      expect(inFlight.faults, hasLength(18));
      expect(
        inFlight.faults.every(
          (item) => item.fault == InFlightFault.needsImport,
        ),
        isTrue,
      );

      final decisions = await _settledDecisions(container);
      expect(decisions, hasLength(1));
      final row = decisions.single;
      expect(row.kind, DecisionKind.importBlocked);
      expect(row.count, 18);
      expect(row.title, '18 need a manual import');
      // Not a client jump: the bytes are on disk.
      expect(row.requiresService, isNull);
      expect(
        decisionActionLabel(row.kind, target: row.actionTarget),
        'Manual import',
      );
      // Eighteen different series: no one of them files the group.
      expect(row.actionId, isNull);
      // Bound to the connection the records came off.
      expect(
        row.instanceId,
        container.read(activeInstanceProvider(ServiceKey.sonarr))!.id,
      );
    });

    test(
      'alone, it is filed under its item and seeded with its folder',
      () async {
        final container = _container(
          settings: sonarrOnly,
          sonarrService: _QueueSonarrService([blocked(7)]),
        );

        final decisions = await _settledDecisions(container);
        final row = decisions.single;
        expect(row.kind, DecisionKind.importBlocked);
        expect(row.count, 1);
        expect(row.title, 'Show\u00A0· S1\u00A0E7');
        expect(row.detail, contains('No files found are eligible for import'));
        expect(row.actionId, 5);
      },
    );
  });

  // The page of twenty is still what the failed-import decisions and
  // Downloads' "last download finished" read. Its Lidarr records have to
  // arrive with their artist and album, or a decision names a release.
  group('servicesArrHistoryProvider', () {});

  group('servicesArrivalsProvider', () {
    test('repointing a source re-reads the week', () async {
      // The other half: the artwork URLs are built from the source's own base
      // URL and key, so a rail that ignored a move would keep pointing its
      // images at the old server.
      final container = _mutableSettingsContainer(
        initial: _secureRadarr,
        radarrService: _HistoryRadarrService([_importedRecord]),
      );

      final first = (await _arrivals(container)).entries;
      container
          .read(_settingsHolderProvider.notifier)
          .set(
            _secureRadarr.copyWithService(
              ServiceKey.radarr,
              url: 'https://moved.local:7878',
            ),
          );
      final second = (await _arrivals(container)).entries;

      expect(identical(first, second), isFalse);
    });

    test('it asks Radarr for the last seven days of imports, with the movie '
        'embedded', () async {
      final radarr = _HistoryRadarrService([_importedRecord]);
      final container = _container(
        settings: _secureRadarr,
        radarrService: radarr,
        overrides: _pinnedNow,
      );

      await _arrivals(container);

      expect(radarr.asked, hasLength(1));
      expect(radarr.asked.single.since, _now.subtract(arrivalsWindow));
      expect(radarr.asked.single.query['eventType'], 'downloadFolderImported');
      expect(radarr.asked.single.query['includeMovie'], isTrue);
    });

    test('a season imported episode by episode is one card, and the count is '
        'cards', () async {
      Map<String, dynamic> episode(int id, int number) => {
        'id': id,
        'eventType': 'downloadFolderImported',
        'date': _now
            .subtract(Duration(hours: 3, minutes: number))
            .toIso8601String(),
        'seriesId': 4,
        'series': {
          'title': "Marvel's Daredevil",
          'tmdbId': 61889,
          'added': _now.subtract(const Duration(days: 1)).toIso8601String(),
        },
        'episode': {'seasonNumber': 1, 'episodeNumber': number},
      };

      final client = FakeApiClient();
      client.getResponseData = [for (var n = 1; n <= 6; n++) episode(n, n)];

      final container = _container(
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.local:8989',
          sonarrApiKey: 'key',
        ),
        sonarrService: SonarrService(client),
        overrides: _pinnedNow,
      );

      final history = await _arrivals(container);
      expect(history.entries, hasLength(6));
      final cards = arrivedOf(
        history.entries,
        since: _now.subtract(arrivalsWindow),
      );

      expect(cards, hasLength(1));
      expect(cards.single.title, "Marvel's Daredevil");
      // The newest of the six is the one the card stands for.
      expect(
        cards.single.at,
        _now.subtract(const Duration(hours: 3, minutes: 1)),
      );
      expect(
        arrivedSubtitle(cards.length, history.coverage),
        'Last 7 days\u00A0· 1 new',
      );
      expect(client.lastGetPath, '/api/v3/history/since');
      expect(
        client.lastGetQueryParameters?['eventType'],
        'downloadFolderImported',
      );
      expect(client.lastGetQueryParameters?['includeSeries'], isTrue);
      expect(client.lastGetQueryParameters?['includeEpisode'], isTrue);
    });

    test('an episode of a series that was already there is not an arrival, '
        'and a series that does not say when it was added is kept', () async {
      Map<String, dynamic> episode(int id, String title, {String? added}) => {
        'id': id,
        'eventType': 'downloadFolderImported',
        'date': _now.subtract(const Duration(hours: 5)).toIso8601String(),
        'seriesId': id,
        'series': {'title': title, 'tmdbId': 100 + id, 'added': ?added},
        'episode': {'seasonNumber': 3, 'episodeNumber': 1},
      };

      final client = FakeApiClient();
      client.getResponseData = [
        episode(
          1,
          'Long Running',
          added: _now.subtract(const Duration(days: 300)).toIso8601String(),
        ),
        episode(
          2,
          'Just Added',
          added: _now.subtract(const Duration(days: 2)).toIso8601String(),
        ),
        episode(3, 'Added Unknown'),
      ];

      final container = _container(
        settings: settingsWith(
          sonarrUrl: 'https://sonarr.local:8989',
          sonarrApiKey: 'key',
        ),
        sonarrService: SonarrService(client),
        overrides: _pinnedNow,
      );

      final history = await _arrivals(container);
      final cards = arrivedOf(
        history.entries,
        since: _now.subtract(arrivalsWindow),
      );

      expect(cards.map((card) => card.title), ['Just Added', 'Added Unknown']);
    });

    test('a movie imported twice is one card, the newer import\'s, and the '
        'cards run newest first', () async {
      Map<String, dynamic> imported(
        int id,
        String title,
        int tmdbId,
        Duration ago,
      ) => {
        'id': id,
        'eventType': 'downloadFolderImported',
        'date': _now.subtract(ago).toIso8601String(),
        'movieId': id,
        'movie': {'title': title, 'tmdbId': tmdbId, 'images': <dynamic>[]},
      };

      final container = _container(
        settings: _secureRadarr,
        radarrService: _HistoryRadarrService([
          imported(1, 'Sintel', 45745, const Duration(days: 2)),
          imported(2, 'Spring', 593910, const Duration(hours: 2)),
          // Upgraded: the same movie again, a day after the first.
          imported(3, 'Sintel', 45745, const Duration(days: 1)),
          // Last month's, outside the week.
          imported(4, 'Elephants Dream', 9761, const Duration(days: 30)),
        ]),
        overrides: _pinnedNow,
      );

      final history = await _arrivals(container);
      final cards = arrivedOf(
        history.entries,
        since: _now.subtract(arrivalsWindow),
      );

      expect(cards.map((card) => card.title), ['Spring', 'Sintel']);
      expect(cards.last.id, 3, reason: 'the newer copy stands for the title');
    });

    test('it keeps only what was imported: a failed import is not what '
        'arrived', () async {
      // The import event is asked for by name, and checked again on each
      // record: a server that ignores the filter still gives only imports.
      // A failed import is a decision, and Needs you's.
      final container = _container(
        settings: _secureRadarr,
        radarrService: _HistoryRadarrService([
          _importedRecord,
          {
            'id': 2,
            'eventType': 'grabbed',
            'date': '2024-05-05T09:00:00Z',
            'sourceTitle': 'Something.Grabbed',
          },
          {
            'id': 3,
            'eventType': 'downloadFailed',
            'date': '2024-05-05T07:00:00Z',
            'sourceTitle': 'Nickel.Boys.2024',
            'movieId': 77,
          },
        ]),
      );

      final history = await _arrivals(container);

      expect(history.entries.map((entry) => entry.title), ['Poor Things']);
      expect(
        history.entries.every(
          (entry) => entry.outcome == ArrImportOutcome.imported,
        ),
        isTrue,
      );
    });
  });

  // The ids a badge looks a title up by, read off each queue's own shape:
  // the nested record or the flat id, and nothing for an id that names no
  // title.
  group('a queue snapshot is indexed by the title each record names', () {
    test('Radarr records by movie id', () async {
      final container = _container(
        radarrService: _QueueRadarrService([
          {
            'movie': {'id': 10, 'title': 'Dune'},
          },
          {'movieId': 11},
          {'movieId': 0},
          'ignored',
        ]),
      );

      final snapshot = await container.read(radarrQueueSnapshotProvider.future);

      expect(snapshot.entriesById.keys.toSet(), {10, 11});
    });

    test('Sonarr records by series id', () async {
      final container = _container(
        sonarrService: _QueueSonarrService([
          {
            'series': {'id': 20, 'title': 'The Boys'},
          },
          {'seriesId': 21},
          {'seriesId': -1},
        ]),
      );

      final snapshot = await container.read(sonarrQueueSnapshotProvider.future);

      expect(snapshot.entriesById.keys.toSet(), {20, 21});
    });
  });

  group('a queue snapshot says what it could not read', () {
    test('a Radarr queue that failed leaves a film with no file unknown, '
        'never Missing', () async {
      final container = _container(radarrService: _ThrowingRadarrService());

      final snapshot = await container.read(radarrQueueSnapshotProvider.future);

      // It used to degrade to the empty snapshot, an answer that says nothing
      // is downloading, and every film being downloaded read "Missing".
      expect(snapshot.answered, isFalse);
      expect(snapshot.isWhole, isFalse);
      expect(snapshot.error, isNotNull);
      final status = radarrMovieStatus(
        buildMovie(id: 7, hasFile: false),
        queueEntry: snapshot.entryFor(7),
        queueUnknown: !snapshot.isWhole,
      );
      expect(status.label, 'Unknown');
    });

    test('a Radarr queue walk that stopped short keeps what it read and '
        'proves no absence', () async {
      final container = _container(
        radarrService: _PageRadarrService(
          const ArrRecordPage(
            records: [
              {'movieId': 10, 'status': 'downloading'},
            ],
            total: null,
            cutShort: true,
          ),
        ),
      );

      final snapshot = await container.read(radarrQueueSnapshotProvider.future);

      expect(snapshot.entryFor(10)?.pipeline, MediaPipeline.downloading);
      expect(snapshot.cutShort, isTrue);
      expect(snapshot.isWhole, isFalse);
    });

    test('a Sonarr queue that failed is unknown, not empty', () async {
      final container = _container(sonarrService: _ThrowingSonarrService());

      final snapshot = await container.read(sonarrQueueSnapshotProvider.future);

      expect(snapshot.answered, isFalse);
    });

    test('a queue that answered empty is still an answer', () async {
      final container = _container(radarrService: _QueueRadarrService([]));

      final snapshot = await container.read(radarrQueueSnapshotProvider.future);

      expect(snapshot.isWhole, isTrue);
      final status = radarrMovieStatus(
        buildMovie(id: 7, hasFile: false),
        queueEntry: snapshot.entryFor(7),
        queueUnknown: !snapshot.isWhole,
      );
      expect(status.label, 'Missing');
    });
  });
}

/// The decisions once every source has answered. The region merges them as
/// they arrive, so a read before then is a read of whichever came first.
Future<List<DashboardDecision>> _settledDecisions(
  ProviderContainer container,
) async {
  for (final source in DecisionSource.values) {
    await container.read(dashboardDecisionSourceProvider(source).future);
  }
  return container.read(dashboardDecisionsProvider).decisions;
}

ProviderContainer _container({
  SettingsModel settings = const SettingsModel(),
  RadarrService? radarrService,
  SonarrService? sonarrService,
  ApiClient? statusClient,
  List<Override> overrides = const [],
}) {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      currentSettingsProvider.overrideWith((ref) => settings),
      if (statusClient != null)
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
                Map<String, String> accessHeaders = const {},
              }) => statusClient,
        ),
      // Seerr's probe builds its client through its own constructor.
      if (statusClient != null)
        seerrClientFactoryProvider.overrideWith(
          (ref) =>
              (
                instance, {
                ConnectionReach? reach,
                SeerrSessionEvents events = const SeerrSessionEvents(),
              }) => statusClient,
        ),
      radarrServiceProvider.overrideWith(
        (ref) => radarrService ?? FakeRadarrService(),
      ),
      sonarrServiceProvider.overrideWith(
        (ref) => sonarrService ?? FakeSonarrService(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// A torrent in the only shape the queue loader reads.
Torrent _torrent(
  String hash,
  String name,
  double progress, {
  String state = 'downloading',
}) => Torrent(
  hash: hash,
  name: name,
  size: 100,
  progress: progress,
  state: state,
  parsedState: TorrentState.fromString(state),
  dlSpeed: 1024,
  upSpeed: 0,
  eta: 60,
  category: '',
  tracker: '',
  tags: const [],
  ratio: 0,
  addedOn: 0,
  completed: 0,
  leechers: 0,
  seeders: 3,
);

class _MoviesRadarrService extends FakeRadarrService {
  _MoviesRadarrService(this.movies);

  final List<RadarrMovie> movies;

  @override
  Future<List<RadarrMovie>> getMovies() async => movies;
}

/// What Arrived asks a Radarr: the week's imports since a date, in one answer.
/// Records what it was asked, so a test can see the window and the narrowing.
class _HistoryRadarrService extends FakeRadarrService {
  _HistoryRadarrService(this.records);

  final List<Map<String, dynamic>> records;

  /// Each `/history/since` this service answered.
  final List<({DateTime since, Map<String, dynamic> query})> asked = [];

  @override
  Future<List<dynamic>> getHistorySince(
    DateTime date, {
    Map<String, dynamic>? queryParameters,
  }) async {
    asked.add((since: date, query: queryParameters ?? const {}));
    return records;
  }
}

/// The moment the week is read from, pinned so a record's age is not the
/// clock's.
final _now = DateTime.utc(2026, 10, 7, 12);

final _pinnedNow = [
  arrivalsClockProvider.overrideWith(
    (ref) =>
        () => _now,
  ),
];

/// The week's answer, held open: the provider lets go of its answer when
/// nothing listens, and a test that reads it twice is asking whether it was
/// read again.
Future<ArrHistory> _arrivals(ProviderContainer container) {
  container.listen(servicesArrivalsProvider, (_, _) {});
  return container.read(servicesArrivalsProvider.future);
}

const Map<String, dynamic> _importedRecord = {
  'id': 1,
  'eventType': 'downloadFolderImported',
  'date': '2024-05-05T08:12:00Z',
  'movieId': 10,
  'movie': {'title': 'Poor Things', 'images': <dynamic>[]},
};

class _ThrowingMoviesRadarrService extends FakeRadarrService {
  @override
  Future<List<RadarrMovie>> getMovies() async =>
      throw Exception('movies failed');
}

/// A settings source the test can move, so `select` can be observed doing its
/// job. The production chain is `currentSettingsProvider` → `settingsProvider`,
/// whose notifier needs SharedPreferences; this stands in for that one link.
final _settingsHolderProvider =
    NotifierProvider<_SettingsHolder, SettingsModel>(_SettingsHolder.new);

class _SettingsHolder extends Notifier<SettingsModel> {
  @override
  SettingsModel build() => const SettingsModel();

  void set(SettingsModel next) => state = next;
}

ProviderContainer _mutableSettingsContainer({
  required SettingsModel initial,
  RadarrService? radarrService,
  ApiClient? statusClient,
}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith(
        (ref) => ref.watch(_settingsHolderProvider),
      ),
      if (statusClient != null)
        serviceStatusClientFactoryProvider.overrideWith(
          (ref) =>
              ({
                required String baseUrl,
                required String apiKey,
                String? pinnedCertFingerprint,
                Map<String, String> accessHeaders = const {},
              }) => statusClient,
        ),
      // Seerr's probe builds its client through its own constructor.
      if (statusClient != null)
        seerrClientFactoryProvider.overrideWith(
          (ref) =>
              (
                instance, {
                ConnectionReach? reach,
                SeerrSessionEvents events = const SeerrSessionEvents(),
              }) => statusClient,
        ),
      radarrServiceProvider.overrideWith(
        (ref) => radarrService ?? FakeRadarrService(),
      ),
      sonarrServiceProvider.overrideWith((ref) => FakeSonarrService()),
    ],
  );
  addTearDown(container.dispose);
  container.read(_settingsHolderProvider.notifier).set(initial);
  return container;
}

/// One HTTPS-addressed Radarr, so `pinForUrl` has an origin to key a trusted
/// certificate on: [UrlUtils.certOrigin] answers null for plain HTTP, and a
/// test that pinned against an `http://` URL would silently assert nothing.
final _secureRadarr = settingsWith(
  radarrUrl: 'https://radarr.local:7878',
  radarrApiKey: 'key',
);

class _CountingStatusClient extends ApiClient {
  _CountingStatusClient()
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  int calls = 0;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    calls++;
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const {'version': '5.4.6'},
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CountingQueueRadarrService extends FakeRadarrService {
  int calls = 0;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async {
    calls++;
    return const [];
  }
}

class _QueueRadarrService extends FakeRadarrService {
  _QueueRadarrService(this.items);

  final List<dynamic> items;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => items;
}

class _ThrowingRadarrService extends FakeRadarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Radarr failed');
}

/// A queue walk with its own envelope: the total and whether it stopped short.
class _PageRadarrService extends FakeRadarrService {
  _PageRadarrService(this.page);

  final ArrRecordPage page;

  @override
  Future<ArrRecordPage> getQueuePage({
    Map<String, dynamic>? queryParameters,
  }) async => page;
}

class _ThrowingSonarrService extends FakeSonarrService {
  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => throw Exception('Sonarr failed');
}

class _QueueSonarrService extends FakeSonarrService {
  _QueueSonarrService(this.items);

  final List<dynamic> items;

  @override
  Future<List<dynamic>> getQueue({
    Map<String, dynamic>? queryParameters,
  }) async => items;
}

class _StatusClient extends ApiClient {
  _StatusClient(this.data)
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  final Map<String, dynamic> data;

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: data,
    );
  }

  @override
  void close({bool force = false}) {}
}

class _ThrowingStatusClient extends ApiClient {
  _ThrowingStatusClient()
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    throw const SocketException('Connection refused');
  }

  @override
  void close({bool force = false}) {}
}

class _SeerrRejectingStatusClient extends ApiClient {
  _SeerrRejectingStatusClient()
    : super(baseUrl: 'https://status.example.com', apiKey: 'key');

  @override
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (path == '/api/v1/request') {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 403,
          data: const {},
        ),
      );
    }
    return Response(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: const {'version': '3.4.1'},
    );
  }

  @override
  void close({bool force = false}) {}
}
