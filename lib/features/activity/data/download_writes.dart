/// What a download's page writes to the client moving its bytes.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/activity/domain/download_page.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Stops [download] in its client, keeping what has arrived, or resumes it
/// ([stopped] false): qBittorrent's stop and start, Transmission's
/// `torrent-stop` and `torrent-start`, SABnzbd's and NZBGet's pause and
/// resume of one job.
///
/// NZBGet edits a job by its NZBID, which a row does not carry when an
/// \*arr named the job (its `drone` id): the client's groups are read to
/// find it.
Future<void> setDownloadStopped(
  WidgetRef ref,
  DownloadClientHandle download, {
  required bool stopped,
}) async {
  switch (download.client) {
    case ServiceKey.qbittorrent:
      final client = ref.read(
        qbittorrentServiceForProvider(download.instanceId),
      );
      stopped
          ? await client.pauseTorrents([download.id])
          : await client.resumeTorrents([download.id]);
    default:
      throw ArgumentError.value(download.client, 'client', 'not a client');
  }
}
