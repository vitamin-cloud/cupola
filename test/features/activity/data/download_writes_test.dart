import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/activity/data/download_writes.dart';
import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/profiles/profiles.dart';

const _mib = 1024 * 1024;

const _torrent = WorldDownload(
  id: 'b2c3d4e5f60718293a4b5c6d7e8f90123456789a',
  release: 'Torrent.Job.2024.1080p',
  client: 'transmission',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

const _usenet = WorldDownload(
  id: 'SABnzbd_nzo_4kq2',
  release: 'Usenet.Job.2024.1080p',
  client: 'sabnzbd',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

/// An \*arr sent this one, so its queue row names it by the `drone` id and
/// never by the NZBID that NZBGet edits it with.
const _drone = WorldDownload(
  id: 'f00dcafe0123',
  release: 'Drone.Job.2024.1080p',
  client: 'nzbget',
  arr: 'sonarr',
  state: DownloadState.downloading,
  progress: 0.3,
  size: 800 * _mib,
);

/// Every client but qBittorrent (held by `qbittorrent_service_test`), one
/// download each, through the app's own clients against the world.
void main() {
  Future<(ProfileHarness, WidgetRef)> pump(WidgetTester tester) async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withDownloads(const [_torrent, _usenet, _drone]),
    );
    late WidgetRef captured;
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: Consumer(
          builder: (context, ref, _) {
            captured = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return (harness, captured);
  }

  /// Runs one write to its end and gives back what it threw, if anything.
  Future<Object?> write(
    WidgetTester tester,
    ProfileHarness harness,
    WidgetRef ref,
    DownloadClientHandle download, {
    required bool stopped,
  }) async {
    Object? failure;
    var done = false;
    Future<void> run() async {
      try {
        await setDownloadStopped(ref, download, stopped: stopped);
      } catch (error) {
        failure = error;
      }
      done = true;
    }

    unawaited(run());
    await harness.settle(tester);
    expect(done, isTrue, reason: 'the write never settled');
    return failure;
  }

  testWidgets('a service that moves no bytes is refused before any write', (
    tester,
  ) async {
    final (harness, ref) = await pump(tester);
    final before = harness.network.requests.length;

    final failure = await write(tester, harness, ref, (
      client: ServiceKey.radarr,
      instanceId: WorldIds.radarr,
      id: 'x',
    ), stopped: true);

    expect(failure, isA<ArgumentError>());
    expect(harness.network.requests.length, before);
    await harness.unmount(tester);
  });
}
