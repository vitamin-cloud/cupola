/// What a row of a download client's own list is to In flight, read off the
/// client's own fields.
///
/// The four clients are one family and are read by one rule: a row is either
/// not in flight at all (seeding, or stopped on purpose), a transfer, or a
/// fault, and a fault is never a row that silently drops out. Each reader
/// below names the wire fields it decides on, so the rule can be checked
/// against the client's API rather than against this file.
///
/// Pure and top-level, so each mapping is testable without a container.
library;

import 'dart:math' as math;

import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/services/domain/in_flight.dart';

/// One client row, read: a transfer, a download waiting its turn, a download
/// held on purpose, or a fault, with the client's own words for the fault
/// when it gave any.
class InFlightReading {
  /// Bytes are moving, or about to: a transfer that has begun.
  const InFlightReading.moving()
    : fault = null,
      reason = null,
      held = false,
      queued = false;

  /// A download waiting its turn to start: the client has it in line behind
  /// others and has not begun. Still to come, so it is not backlog and not a
  /// fault; and not moving either, which is what it used to be counted as.
  const InFlightReading.queued()
    : fault = null,
      reason = null,
      held = false,
      queued = true;

  /// A download somebody stopped on purpose, with bytes still to come: the
  /// backlog, which the tone rule files under neutral. Not in flight and not
  /// a fault, the same on every client.
  const InFlightReading.held()
    : fault = null,
      reason = null,
      held = true,
      queued = false;

  /// The row stopped being a transfer, for [reason] when the client said why.
  const InFlightReading.fault(InFlightFault this.fault, {this.reason})
    : held = false,
      queued = false;

  final InFlightFault? fault;

  /// The client's reason, as it put it, or null when it gave none and the
  /// fault's own word stands.
  final String? reason;

  /// Stopped on purpose: see [InFlightReading.held].
  final bool held;

  /// Waiting its turn: see [InFlightReading.queued].
  final bool queued;

  @override
  bool operator ==(Object other) =>
      other is InFlightReading &&
      other.fault == fault &&
      other.reason == reason &&
      other.held == held &&
      other.queued == queued;

  @override
  int get hashCode => Object.hash(fault, reason, held, queued);

  @override
  String toString() =>
      'InFlightReading(${fault?.name ?? (held ? 'held' : (queued ? 'queued' : 'moving'))}'
      '${reason == null ? '' : ', $reason'})';
}

/// A qBittorrent torrent (`/api/v2/torrents/info`), or null when it is not in
/// flight. Decided on `state`, the raw wire value, and on how long nothing
/// has arrived.
///
/// `stalledDL` is a stall once nothing has arrived for [stuckAfter], by
/// `last_activity` (or `added_on` for a torrent that never received a byte, or
/// the moment Cupola saw it start again, [Torrent.resumedOn], if later):
/// qBittorrent sets it at any instant the payload rate is zero, so on its own
/// it is a slow moment, not a fault. `metaDL`, fetching the torrent's
/// metadata, is the same: it waits on peers, and a magnet nobody answers sits
/// in it at 0% for good, so past [stuckAfter] it is a stall too. `error` and
/// `missingFiles` are failures on any
/// row, a finished one included: qBittorrent stops a torrent it cannot read
/// or write, and dropping it with the seeding library made a broken download
/// vanish from Home with nothing saying so. `missingFiles` says why; a bare
/// `error` does not, and the API carries no message for it. A download paused
/// or stopped on purpose (`pausedDL`, `stoppedDL`) is held, and one waiting
/// its turn behind the client's active limit (`queuedDL`) is queued. Seeding, checking,
/// a finished torrent stopped (`pausedUP`, `stoppedUP`) and one whose files
/// are moving to their folder (`moving`) are not in flight.
InFlightReading? qbittorrentInFlight(Torrent torrent, {required DateTime now}) {
  final state = torrent.state;
  if (state == 'pausedDL' || state == 'stoppedDL') {
    return const InFlightReading.held();
  }
  if (state == 'missingFiles') {
    return const InFlightReading.fault(
      InFlightFault.failed,
      reason: qbittorrentMissingFiles,
    );
  }
  final idle = idleSince(
    lastActivity: torrent.lastActivity,
    added: torrent.addedOn,
    started: torrent.resumedOn,
  );
  return switch (TorrentState.fromString(state)) {
    TorrentState.downloading => const InFlightReading.moving(),
    TorrentState.queuedDl => const InFlightReading.queued(),
    // Without a date to measure by, the metadata wait is taken as a
    // transfer: the client has not said anything is wrong.
    TorrentState.metaDownloading => _stuckOnceIdle(
      idle,
      now,
      unknownIsStuck: false,
    ),
    // `stalled` is only ever `stalledDL`: a stalled upload parses as seeding.
    TorrentState.stalled => _stuckOnceIdle(idle, now, unknownIsStuck: true),
    TorrentState.error => const InFlightReading.fault(InFlightFault.failed),
    // A pause for the move, not an end: a download with bytes still to come
    // stays in flight, a finished one leaving its incomplete folder is done.
    TorrentState.movingFiles =>
      torrent.progress < 1 ? const InFlightReading.moving() : null,
    TorrentState.seeding ||
    TorrentState.checking ||
    TorrentState.paused ||
    TorrentState.queuedUp ||
    TorrentState.unknown => null,
  };
}

/// How long a download goes with nothing arriving before it is stuck.
///
/// The word promises it (`Stuck` only after 30 minutes with nothing arriving):
/// a torrent client's own stall flag flips on at any instant the rate touches
/// zero, so a fault raised on the flag alone came and went with every slow
/// minute of a healthy download.
const Duration stuckAfter = Duration(minutes: 30);

/// Since when a torrent has waited with nothing arriving, from the client's
/// epoch seconds: the latest of [lastActivity], [added] and [started]. A
/// torrent that never received a byte has waited since it was added, and one
/// stopped for weeks and started again has waited since it started (Transmission
/// says when, `startDate`): counting from its addition called it stuck the
/// moment it was resumed, `for 26 days`. Null when the client gave none.
DateTime? idleSince({
  required int lastActivity,
  required int added,
  int started = 0,
}) {
  final seconds = [lastActivity, added, started].reduce(math.max);
  if (seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

/// A stall once [since] is at least [stuckAfter] before [now], a transfer
/// before that. With no date, [unknownIsStuck] decides: the client's own
/// stall flag stands, a metadata wait does not.
InFlightReading _stuckOnceIdle(
  DateTime? since,
  DateTime now, {
  required bool unknownIsStuck,
}) {
  final stuck = since == null
      ? unknownIsStuck
      : now.difference(since) >= stuckAfter;
  return stuck
      ? const InFlightReading.fault(InFlightFault.stalled)
      : const InFlightReading.moving();
}

/// What a `missingFiles` torrent's decision says: its data is not where
/// qBittorrent left it.
const String qbittorrentMissingFiles = 'Files missing';
