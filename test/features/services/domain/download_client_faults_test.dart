import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/in_flight.dart';

/// The moment every reading below is taken at.
final _now = DateTime(2026, 10, 9, 21);

/// [_now] less [ago], in the epoch seconds the clients send.
int _secondsAgo(Duration ago) =>
    _now.subtract(ago).millisecondsSinceEpoch ~/ 1000;

Torrent _qb(
  String state, {
  int lastActivity = 0,
  int addedOn = 0,
  int resumedOn = 0,
  double progress = 0,
}) => Torrent.fromJson({
  kQbittorrentResumedOn: resumedOn,
  'hash': 'abc',
  'name': 'Big.Buck.Bunny.2008.1080p.BluRay',
  'state': state,
  'progress': progress,
  'last_activity': lastActivity,
  'added_on': addedOn,
});

void main() {
  group('transmissionInFlight', () {







  });

  group('qbittorrentInFlight', () {
    test('downloading, fetching metadata and moving are transfers', () {
      for (final state in [
        'downloading',
        'forcedDL',
        'metaDL',
        'moving',
        'allocating',
      ]) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          const InFlightReading.moving(),
          reason: state,
        );
      }
    });

    test('a finished download whose files move to their folder is done', () {
      expect(
        qbittorrentInFlight(_qb('moving', progress: 1), now: _now),
        isNull,
      );
    });

    test('a download waiting its turn (queuedDL) is queued, not moving', () {
      expect(
        qbittorrentInFlight(_qb('queuedDL'), now: _now),
        const InFlightReading.queued(),
      );
      // A queued upload is a seeding torrent's wait, and not in flight.
      expect(qbittorrentInFlight(_qb('queuedUP'), now: _now), isNull);
    });

    test('a stalled download is a stall', () {
      expect(
        qbittorrentInFlight(_qb('stalledDL'), now: _now),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('error and missingFiles are failures, never dropped', () {
      expect(
        qbittorrentInFlight(_qb('error'), now: _now),
        const InFlightReading.fault(InFlightFault.failed),
      );
      expect(
        qbittorrentInFlight(_qb('missingFiles'), now: _now),
        const InFlightReading.fault(
          InFlightFault.failed,
          reason: qbittorrentMissingFiles,
        ),
      );
    });

    test('seeding, checking and finished stopped torrents are not in '
        'flight', () {
      for (final state in [
        'uploading',
        'stalledUP',
        'forcedUP',
        'queuedUP',
        'pausedUP',
        'stoppedUP',
        'checkingDL',
        'checkingUP',
        'something-new',
      ]) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          isNull,
          reason: state,
        );
      }
    });

    test('a download paused or stopped on purpose is held', () {
      for (final state in ['pausedDL', 'stoppedDL']) {
        expect(
          qbittorrentInFlight(_qb(state), now: _now),
          const InFlightReading.held(),
          reason: state,
        );
      }
    });
  });

  group('stuck only after 30 minutes with nothing arriving', () {
    test('qBittorrent: stalledDL is a slow moment until 30 minutes pass', () {
      expect(
        qbittorrentInFlight(
          _qb(
            'stalledDL',
            lastActivity: _secondsAgo(const Duration(minutes: 29)),
          ),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
      expect(
        qbittorrentInFlight(
          _qb('stalledDL', lastActivity: _secondsAgo(stuckAfter)),
          now: _now,
        ),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('qBittorrent: a metadata wait nobody answers is stuck at 30 '
        'minutes, dated from when it was added', () {
      expect(
        qbittorrentInFlight(
          _qb('metaDL', addedOn: _secondsAgo(const Duration(minutes: 10))),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
      expect(
        qbittorrentInFlight(
          _qb('metaDL', addedOn: _secondsAgo(const Duration(days: 2))),
          now: _now,
        ),
        const InFlightReading.fault(InFlightFault.stalled),
      );
    });

    test('qBittorrent: a torrent that received data lately is not stuck, '
        'however long ago it was added', () {
      expect(
        qbittorrentInFlight(
          _qb(
            'stalledDL',
            addedOn: _secondsAgo(const Duration(days: 3)),
            lastActivity: _secondsAgo(const Duration(minutes: 5)),
          ),
          now: _now,
        ),
        const InFlightReading.moving(),
      );
    });

    test('qBittorrent: a torrent stopped for weeks and started again waits '
        'from when Cupola saw it start', () {
      final resumed = _qb(
        'stalledDL',
        lastActivity: _secondsAgo(const Duration(days: 26)),
        addedOn: _secondsAgo(const Duration(days: 40)),
        resumedOn: _secondsAgo(const Duration(minutes: 10)),
      );
      expect(
        qbittorrentInFlight(resumed, now: _now),
        const InFlightReading.moving(),
      );
    });



    test('idleSince reads the last activity, else the time added, else '
        'nothing', () {
      expect(
        idleSince(lastActivity: 1000, added: 10),
        DateTime.fromMillisecondsSinceEpoch(1000 * 1000),
      );
      expect(
        idleSince(lastActivity: 0, added: 10),
        DateTime.fromMillisecondsSinceEpoch(10 * 1000),
      );
      expect(idleSince(lastActivity: 0, added: 0), isNull);
    });
  });

  group('InFlightReading', () {
    test('queued is its own reading, equal to itself and to nothing else', () {
      expect(const InFlightReading.queued(), const InFlightReading.queued());
      expect(
        const InFlightReading.queued(),
        isNot(const InFlightReading.moving()),
      );
      expect(const InFlightReading.queued().fault, isNull);
      expect(const InFlightReading.queued().held, isFalse);
      expect(const InFlightReading.queued().queued, isTrue);
      expect(const InFlightReading.moving().queued, isFalse);
      expect(const InFlightReading.held().queued, isFalse);
      expect(
        const InFlightReading.fault(InFlightFault.stalled).queued,
        isFalse,
      );
      expect(const InFlightReading.queued().toString(), contains('queued'));
    });
  });

  group('stuckRemedyFor', () {
    test('somebody has the whole file: look for peers again', () {
      expect(stuckRemedyFor(swarmSeeds: 3), StuckRemedy.lookForPeers);
    });

    test('nobody has it, or the client cannot say: try another '
        'download', () {
      expect(stuckRemedyFor(swarmSeeds: 0), StuckRemedy.tryAnotherDownload);
      expect(stuckRemedyFor(swarmSeeds: null), StuckRemedy.tryAnotherDownload);
    });
  });

  group('usenetQueueStoppedByDisk', () {
    const gb = 1024 * 1024 * 1024;

    test('a paused queue that cannot hold its smallest job was stopped by '
        'its disk', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: gb ~/ 2,
          remainingBytes: [8 * gb, gb],
        ),
        isTrue,
      );
    });

    test('a paused queue with room for a job was paused on purpose', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: 2 * gb,
          remainingBytes: [8 * gb, gb],
        ),
        isFalse,
      );
    });

    test('a running queue, a timed pause, an unknown free space and an '
        'empty queue prove nothing', () {
      expect(
        usenetQueueStoppedByDisk(
          paused: false,
          freeBytes: 0,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          timedPause: true,
          freeBytes: 0,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: null,
          remainingBytes: [gb],
        ),
        isFalse,
      );
      expect(
        usenetQueueStoppedByDisk(
          paused: true,
          freeBytes: 0,
          remainingBytes: [0, null],
        ),
        isFalse,
      );
    });
  });


}
