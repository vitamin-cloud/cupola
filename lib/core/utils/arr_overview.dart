/// What the four \*arr Overviews (Radarr, Sonarr, Lidarr, Readarr) read the
/// same way, said once: the shape of a Needs attention row, of a History today
/// row, and the readings of an \*arr record they are made from.
///
/// Per service stay the enum of faults (its members differ), what a record's
/// subject is (`arrPrimaryMediaTitle`, `sonarrRecordSubject`, `readarrRecordTitle`
/// read different fields), and `*QueueFaults`, which are not one function:
/// Sonarr folds by download and names a pack, Lidarr by album.
library;

import 'package:flutter/material.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// Parses an \*arr ISO timestamp into local time, or null when it is absent or
/// unreadable.
///
/// Local, always: every window on an Overview is a run of local calendar days,
/// and an \*arr answers in UTC. For a real instant only (`added`, a history
/// `date`): a release date is a day, and reads through `arrCalendarDate`.
DateTime? parseLocalInstant(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toLocal();
}

/// The size a history record states, in bytes, or null when it states none or
/// a size that is not one.
int? historyRecordBytes(Map<String, dynamic> record) {
  final bytes =
      intOrNull(record['size']) ??
      intOrNull(mapOrNull(record['data'])?['size']);
  if (bytes == null || bytes <= 0) return null;
  return bytes;
}

/// What a kind of fault says about itself: its tone and its mark.
///
/// Each \*arr has its own enum of them, because their members differ
/// (Sonarr's missing episodes, Readarr's missing books), and each member
/// carries its tone: two of the faults are amber and the backlog is neutral,
/// and collapsing them into one "attention" colour is how a library with a
/// normal wishlist ends up wearing the same amber as a broken import.
abstract interface class ArrAttentionKind {
  StatusTone get tone;
  IconData get icon;
}

/// One row of Needs attention: what happened, to what, and when.
///
/// Every row leads somewhere: a download's own page for one stuck or failed
/// download, the Queue tab for the several a folded row stands for, the
/// Wanted tab for the backlog. What the \*arr can do about a download it
/// cannot import (a retry, a manual import) is not a call this client makes,
/// so no row carries a verb: the page it opens does.
@immutable
class ArrAttentionItem<K extends ArrAttentionKind> {
  const ArrAttentionItem({
    required this.kind,
    required this.headline,
    required this.detail,
    this.door,
    this.subject,
    this.count = 1,
    String? spokenHeadline,
  }) : _spokenHeadline = spokenHeadline;

  final K kind;

  /// The fault and its subject: `Import failed · Nickel Boys`.
  final String headline;

  /// The evidence: the service's own message, the client, the timestamp.
  /// Empty when the record carried none.
  final String detail;

  /// Where the row leads, or null where the app has no place that shows it.
  final AttentionDoor? door;

  /// What the fault is about, bare (`Nickel Boys`), for a folded row to name.
  final String? subject;

  /// How many faults the row stands for: one, or the downloads a folded row
  /// folds. The section's own count adds these, so folding never changes how
  /// many things need attention.
  final int count;

  /// [headline] as the ear should hear it, where it differs (`at least 3`
  /// for a floor).
  final String? _spokenHeadline;

  StatusTone get tone => kind.tone;
  IconData get icon => kind.icon;

  /// The row as a sentence, with the dots the layout uses turned back into
  /// commas. `·` is decoration, and a screen reader either names it or drops
  /// it depending on the user's punctuation setting.
  String get spoken => joinSpokenParts([
    spokenFromDotted(_spokenHeadline ?? headline),
    spokenFromDotted(detail),
  ]);
}

/// One history record, resolved into the two lines the row draws.
@immutable
class OverviewHistoryEntry {
  const OverviewHistoryEntry({
    required this.subject,
    required this.event,
    required this.tone,
    required this.detail,
    required this.date,
    String? spokenSubject,
  }) : _spokenSubject = spokenSubject;

  /// What it happened to: the film, the series and its slot, the album, the
  /// book.
  final String subject;

  /// What happened to it, in the shared history vocabulary: `Imported`,
  /// `Grabbed`, `Failed`.
  final String event;

  final StatusTone tone;

  /// Quality, size and how long ago, as far as the record carried them.
  final String detail;

  /// The newest record behind the row: what it sorts and dates by.
  final DateTime date;

  /// [subject] with its dots spoken as pauses, where it differs.
  final String? _spokenSubject;

  String get spoken => joinSpokenParts([
    _spokenSubject ?? subject,
    event,
    spokenFromDotted(detail),
  ]);
}
