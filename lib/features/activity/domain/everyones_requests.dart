/// Everyone's requests on Activity: the latest few that move or arrived, who
/// asked, and how the rest stand.
library;

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/requests/domain/my_requests.dart';

/// One request's state and when, as one line: `Ready to watch since 18:40`,
/// `Downloading 62% · ready around 21:10`, `On the server since Sat 12 Sep`,
/// `Declined yesterday`.
///
/// The operator's words: an answer says when it was given, never the
/// requester's `Declined by the server's owner`, since the one reading is
/// the owner.
String everyonesLine(MyRequest mine, DateTime now) {
  switch (mine.stage) {
    case MyRequestStage.declined || MyRequestStage.didNotGoThrough:
      final at = mine.answeredAt;
      return at == null
          ? mine.state
          : '${mine.state} ${dayWords(at, now: now)}';
    case MyRequestStage.removed || MyRequestStage.blocked:
      return mine.state;
    default:
      break;
  }
  final detail = mine.detail(now);
  if (detail.isEmpty || detail == mine.state) return mine.state;
  final lower = '${detail[0].toLowerCase()}${detail.substring(1)}';
  return detail.startsWith('Since ')
      ? '${mine.state} $lower'
      : '${mine.state}\u00A0· $lower';
}

/// The tone of [stage] on the operator's rows: a request that did not go
/// through is a fault on the stack, theirs to mend, so amber; every other
/// stage keeps the household's tone.
StatusTone everyonesTone(MyRequestStage stage) =>
    stage == MyRequestStage.didNotGoThrough ? StatusTone.warning : stage.tone;
