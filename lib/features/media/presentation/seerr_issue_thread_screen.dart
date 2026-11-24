import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/media_detail_body_metrics.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/data/seerr_session.dart';
import 'package:cupola/features/discover/domain/models/seerr_issue.dart';
import 'package:cupola/features/discover/domain/seerr_issue_words.dart';
import 'package:cupola/features/discover/domain/seerr_refusal.dart';
import 'package:cupola/core/network/write_outcome.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_report.dart';
import 'package:cupola/features/media/presentation/issue_files_provider.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_manage_parts.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_report_provider.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/media/presentation/seerr_issue_thread_parts.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// `Delete this reply?`: [who] is the person who will no longer see it, as the
/// page says it (`Luca`, or `Whoever runs the server`).
Future<AppConfirmResult> showDeleteReplyConfirm(
  BuildContext context, {
  required String who,
  bool useRootNavigator = true,
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: useRootNavigator,
  title: 'Delete this reply?',
  message: "$who won't see it any more. This cannot be undone.",
  confirmLabel: 'Delete reply',
  cancelLabel: 'Keep it',
);

/// `Delete this issue?`, the operator's: Seerr removes the issue and every
/// reply, for [reporter] too (null when Seerr did not name them).
Future<AppConfirmResult> showDeleteIssueConfirm(
  BuildContext context, {
  String? reporter,
  bool useRootNavigator = true,
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: useRootNavigator,
  title: 'Delete this issue?',
  message:
      'Seerr removes it and its replies, for '
      '${reporter ?? 'whoever reported it'} too. This cannot be undone.',
  confirmLabel: 'Delete issue',
  cancelLabel: 'Keep it',
);

/// `Delete this report?`, the requester's. Only offered while nobody has
/// replied, so nobody but whoever runs the server has seen it.
Future<AppConfirmResult> showDeleteReportConfirm(
  BuildContext context, {
  bool useRootNavigator = true,
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: useRootNavigator,
  title: 'Delete this report?',
  message:
      "Whoever runs the server won't see it any more. This cannot be undone.",
  confirmLabel: 'Delete report',
  cancelLabel: 'Keep it',
);

/// One problem somebody reported, and its conversation: the report, the
/// replies, where to answer, and what the reader may do about it.
///
/// Two audiences read it. The operator sees an open issue as a fault (amber,
/// `Open`), the files that could be at fault and a way to search a new
/// release, and resolves, deletes or opens it in Seerr. The requester sees
/// her own report (blue, `Reported`), answers, marks it resolved or reopens
/// it, and deletes it only while nobody has replied; the server is never
/// named to her.
///
/// [connectionId] is the Seerr connection the issue was read from: an issue
/// number is per instance. Empty reads the lens. Every verdict comes from the
/// connection's [RoleGate], and every write reads the issue again.
class SeerrIssueThreadScreen extends ConsumerStatefulWidget {
  const SeerrIssueThreadScreen({
    super.key,
    required this.issueId,
    this.connectionId = '',
  });

  final int issueId;
  final String connectionId;

  @override
  ConsumerState<SeerrIssueThreadScreen> createState() =>
      _SeerrIssueThreadScreenState();
}

class _SeerrIssueThreadScreenState
    extends ConsumerState<SeerrIssueThreadScreen> {
  final _reply = TextEditingController();
  final _edit = TextEditingController();
  bool _sending = false;
  int? _editing;
  bool _saving = false;

  /// The write a button is waiting on (`resolve`, `reopen`, `delete`): its
  /// glyph is a spinner and every other button ignores a tap.
  String? _busy;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _reply.dispose();
    _edit.dispose();
    super.dispose();
  }

  /// The connection the issue lives on: the route's, else the lens's.
  String get _id {
    if (widget.connectionId.isNotEmpty) return widget.connectionId;
    return ref.read(activeInstanceProvider(ServiceKey.seerr))?.id ?? '';
  }

  MediaReportIssueSource get _source =>
      (connectionId: _id, issueId: widget.issueId);

  bool get _operator => ref.read(audienceProvider) == Audience.operator;

  @override
  Widget build(BuildContext context) {
    // The connection's own state, before anything is asked of it: a failed
    // provider is retried for a condition no waiting changes.
    final lens = ref.watch(
      activeInstanceProvider(ServiceKey.seerr).select((i) => i?.id),
    );
    final id = widget.connectionId.isNotEmpty ? widget.connectionId : lens;
    final configured =
        id != null &&
        ref.watch(
          currentSettingsProvider.select(
            (s) => s.instanceById(id)?.isConfigured ?? false,
          ),
        );
    if (!configured) return const SeerrDetailNotSetUpView();

    final operator = ref.watch(audienceProvider) == Audience.operator;
    final read = ref.watch(
      mediaReportIssueProvider((connectionId: id, issueId: widget.issueId)),
    );
    final gone =
        read.hasError && seerrRefusalOf(read.error) == SeerrRefusal.issueGone;
    if (gone) {
      return _Page(
        child: _Gone(operator: operator, onBack: _leave),
      );
    }
    final issue = read.value;
    if (issue == null) {
      return _Page(
        child: read.hasError
            ? AppErrorState(
                error: read.error!,
                serviceName: 'Seerr',
                service: ServiceKey.seerr,
                instanceId: id,
                onRetry: () => ref.invalidate(mediaReportIssueProvider),
              )
            : const _Skeleton(),
      );
    }
    return _thread(context, issue, id: id, operator: operator);
  }

  Widget _thread(
    BuildContext context,
    SeerrIssue issue, {
    required String id,
    required bool operator,
  }) {
    final room = CupolaRoom.of(context);
    final gate = ref.watch(roleGateProvider(id));
    final userId = ref.watch(seerrActingUserIdProvider(id));
    final own = issue.isReportedBy(userId);
    final key = mediaKeyOfIssue(issue);
    final reporter = issue.createdBy?.displayName;
    final others = [
      for (final reply in issue.replies)
        if (!reply.isBy(userId)) reply,
    ];
    final other = others.lastOrNull?.authorName;
    final media = issue.media;
    final poster = ImageUtils.buildTmdbPosterUrl(media?.posterPath);
    final title = media?.title ?? 'Unknown media';
    final light = poster.isEmpty
        ? null
        : ref.watch(titleLightProvider(poster)).value;
    final now = DateTime.now();

    final created = DateTime.tryParse(issue.createdAt ?? '');
    final state = issueState(issue, operator: operator);
    final resolvedBy = issue.modifiedBy;
    final resolvedAt = DateTime.tryParse(issue.updatedAt ?? '');
    final stateLine = [
      ?issue.type?.label,
      if (operator) ?reporter,
      if (issue.isResolved)
        [
              'resolved',
              if (resolvedBy != null)
                'by ${resolvedBy.id == userId ? 'you' : resolvedBy.displayName}',
            ].join(' ') +
            (resolvedAt == null ? '' : ', ${issueMoment(resolvedAt, now: now)}')
      else if (created != null)
        issueMoment(created, now: now),
    ].join(dotSeparator);

    final heading = issue.message?.trim().isNotEmpty ?? false
        ? issue.message!
        : '${issue.type?.label ?? 'Reported'} problem';

    final commentVerdict = gate.commentOnIssueAction(own: own);
    final resolveVerdict = gate.resolveIssueAction(own: own);
    final deleteVerdict = gate.deleteIssueAction(
      own: own,
      commentCount: issue.commentCount,
    );
    // The reporter deletes only while nobody has answered, as the server
    // allows: past that the control is not hers, never a dimmed promise.
    final mayDeleteReport =
        !operator && issue.commentCount == 1 && deleteVerdict is! Absent;
    final files = operator && issue.isOpen && key != null
        ? ref.watch(
            issueFilesProvider((
              key: key,
              season: issue.problemSeason,
              episode: issue.problemEpisode,
              title: title,
            )),
          )
        : const <IssueFile>[];

    final readers = operator
        ? '${reporter ?? 'The reporter'} reads replies in Seerr, or in Stack.'
        : others.isEmpty
        ? 'Whoever runs the server sees what you add.'
        : '${other ?? 'Whoever runs the server'} sees your reply.';
    final composerLabel = operator
        ? (reporter == null ? 'Reply' : 'Reply to $reporter')
        : others.isEmpty
        ? 'Add a detail'
        : (other == null ? 'Reply' : 'Reply to $other');
    final tag = 'seerr_issue_thread_${id}_${issue.id}';

    return _Page(
      light: light,
      body: (gutter) => [
        IssueTitleCard(
          title: title,
          sub: _subOf(issue, key, operator: operator, id: id),
          posterUrl: poster.isEmpty ? null : poster,
          heroTag: tag,
          onTap: key == null
              ? null
              : () => context.openMedia(
                  key,
                  focus: id,
                  heroTag: tag,
                  posterUrl: poster.isEmpty ? null : poster,
                ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          header: true,
          child: Text(heading, style: AppType.room.copyWith(color: room.ink)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            MediaStateWord(state.word, tone: state.tone, hollow: false),
            if (stateLine.isNotEmpty)
              Text(
                stateLine,
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.inkSecondary),
              ),
          ],
        ),
        if (issue.replies.isEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            'No replies yet.',
            style: AppType.meta
                .weight(FontWeight.w400)
                .copyWith(color: room.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          MediaHeading('Replies', trailing: '${issue.replies.length}'),
          for (final (index, reply) in issue.replies.indexed) ...[
            if (index > 0) const SizedBox(height: AppSpacing.row),
            _replyTile(reply, userId: userId, gate: gate, now: now, who: other),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
        if (commentVerdict is! Absent) ...[
          IssueComposer(
            label: composerLabel,
            controller: _reply,
            verdict: commentVerdict,
            sending: _sending,
            onSend: _send,
          ),
          IssueCaption(readers),
        ],
        if (files.isNotEmpty) ...[
          MediaHeading('Files it could be', trailing: '${files.length}'),
          MediaGroup(
            children: [
              for (final file in files)
                IssueFileRow(
                  file: file,
                  now: now,
                  onTap: () => context.openMedia(key!, focus: id),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            style: _secondary,
            onPressed: () => _search(files),
            icon: const Icon(Icons.search_rounded, size: 20),
            label: const Text('Search a new release'),
          ),
          const IssueCaption(
            'Replacing a file keeps the issue open until you resolve it.',
          ),
        ],
        SizedBox(height: operator ? AppSpacing.section : AppSpacing.xl + 4),
        ..._actions(
          issue,
          operator: operator,
          resolve: resolveVerdict,
          delete: deleteVerdict,
          mayDeleteReport: mayDeleteReport,
          reporter: reporter,
          other: other,
        ),
      ],
    );
  }

  ButtonStyle get _secondary => OutlinedButton.styleFrom(
    visualDensity: VisualDensity.standard,
    minimumSize: Size.fromHeight(
      TextScaleMetrics.boxHeight(context, base: 48, textHeight: 20),
    ),
  );

  /// One reply: the words, or the field when it is being edited.
  Widget _replyTile(
    SeerrIssueComment reply, {
    required int? userId,
    required RoleGate gate,
    required DateTime now,
    required String? who,
  }) {
    final mine = reply.isBy(userId);
    if (_editing == reply.id) {
      return IssueReplyEditor(
        controller: _edit,
        saving: _saving,
        onCancel: () => setState(() => _editing = null),
        onSave: () => _saveEdit(reply),
      );
    }
    final at = DateTime.tryParse(reply.createdAt ?? '');
    return IssueReplyBubble(
      author: mine ? 'You' : (reply.authorName ?? 'Someone'),
      when: at == null ? '' : issueMoment(at, now: now),
      text: reply.message,
      own: mine,
      menu: mine
          ? IssueReplyMenu(
              edit: gate.editReplyAction(own: true),
              delete: gate.deleteReplyAction(own: true),
              onSelected: (action) => switch (action) {
                IssueReplyAction.edit => _startEdit(reply),
                IssueReplyAction.delete => _deleteReply(reply, who: who),
              },
            )
          : null,
    );
  }

  /// Resolve or reopen, delete, and open in Seerr, as the audience has them.
  List<Widget> _actions(
    SeerrIssue issue, {
    required bool operator,
    required GateVerdict resolve,
    required GateVerdict delete,
    required bool mayDeleteReport,
    required String? reporter,
    required String? other,
  }) {
    final resolved = issue.isResolved;
    // The requester says "mark it as resolved", never "resolve the issue".
    final primary = resolved
        ? _gated(
            resolve,
            () => _setStatus(issue, SeerrIssueStatus.open),
            busy: 'reopen',
            icon: Icons.undo_rounded,
            label: 'Reopen',
            style: _secondary,
            filled: false,
          )
        : _gated(
            resolve,
            () => _setStatus(issue, SeerrIssueStatus.resolved),
            busy: 'resolve',
            icon: Icons.check_rounded,
            label: operator ? 'Resolve' : 'Mark as resolved',
            style: operator ? AppTheme.primaryButtonStyle(context) : _secondary,
            filled: operator,
          );
    if (!operator) {
      return [
        primary,
        if (mayDeleteReport) ...[
          const SizedBox(height: AppSpacing.sm),
          _gated(
            delete,
            () => _deleteIssue(issue),
            busy: 'delete',
            icon: Icons.delete_outline_rounded,
            label: 'Delete report',
            style: _ghost,
            filled: null,
          ),
          const IssueCaption(
            'Only while nobody has replied, as on the server.',
          ),
        ] else
          IssueCaption(
            resolved
                ? 'If it still plays wrong.'
                : 'When it plays right again. '
                      '${other ?? 'Whoever runs the server'} can reopen it, '
                      'and so can you.',
          ),
      ];
    }
    return [
      primary,
      const SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: _gated(
              delete,
              () => _deleteIssue(issue, reporter: reporter),
              busy: 'delete',
              icon: Icons.delete_outline_rounded,
              label: 'Delete issue',
              style: _ghost,
              filled: null,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextButton.icon(
              style: _ghost,
              onPressed: () => _openInSeerr(issue),
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: const Text('Open in Seerr'),
            ),
          ),
        ],
      ),
    ];
  }

  ButtonStyle get _ghost => TextButton.styleFrom(
    visualDensity: VisualDensity.standard,
    minimumSize: const Size.fromHeight(44),
  );

  /// A button as the gate says: [filled] true the primary, false the
  /// secondary, null the ghost. A dimmed one keeps its target and answers a
  /// tap with its reason; sending keeps the look and ignores a second tap.
  Widget _gated(
    GateVerdict verdict,
    VoidCallback onTap, {
    required String busy,
    required IconData icon,
    required String label,
    required ButtonStyle style,
    required bool? filled,
  }) => RoleGatedAction.builder(
    verdict: verdict,
    onTap: onTap,
    builder: (context, onPressed, annotate) {
      final working = _busy == busy;
      final glyph = working
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 20);
      void press() {
        if (_busy != null) return;
        onPressed();
      }

      final text = annotate(Text(label));
      return switch (filled) {
        true => FilledButton.icon(
          style: style,
          onPressed: press,
          icon: glyph,
          label: text,
        ),
        false => OutlinedButton.icon(
          style: style,
          onPressed: press,
          icon: glyph,
          label: text,
        ),
        null => TextButton.icon(
          style: style,
          onPressed: press,
          icon: glyph,
          label: text,
        ),
      };
    },
  );

  /// `Movie · 2012 · on your server`, `S2 E3 · The Second Cycle`.
  String _subOf(
    SeerrIssue issue,
    MediaKey? key, {
    required bool operator,
    required String id,
  }) {
    final media = issue.media;
    final onServer = operator && (media?.isOnServer ?? false);
    final year = media?.year;
    final season = issue.problemSeason;
    final episode = issue.problemEpisode;
    if (key != null && !key.isMovie && season > 0) {
      if (episode <= 0) {
        return ['Season $season', 'All episodes'].join(dotSeparator);
      }
      final name = ref
          .watch(
            mediaSeasonFactsProvider((
              connectionId: id,
              tvId: key.tmdbId!,
              season: season,
            )),
          )
          .value
          ?.where((fact) => fact.number == episode)
          .firstOrNull
          ?.name;
      return [
        formatEpisodeCode(season, episode),
        if (name != null && name.isNotEmpty) name,
      ].join(dotSeparator);
    }
    return [
      key == null || key.isMovie ? 'Movie' : 'Series',
      ?year,
      if (onServer) 'on your server',
    ].join(dotSeparator);
  }

  // ── writes ───────────────────────────────────────────────────────────────

  /// Reads the issue, the Issues list and the title's report rows again.
  void _readAgain(SeerrIssue? issue) {
    final key = issue == null ? null : mediaKeyOfIssue(issue);
    if (key != null) {
      readReportsAgain(ref.container, key: key, connectionId: _id);
    } else {
      readIssuesAgain(ref.container);
    }
  }

  /// Runs one write. True when it went through. A failure keeps what the
  /// person wrote and says so with `Retry` where the same request can still
  /// succeed; an issue or reply that is gone is read again, not reported as a
  /// fault.
  ///
  /// [alreadyThere] is for a write that adds something and cannot be repeated
  /// safely (Seerr takes no key for it): when the failure may have reached the
  /// server, it reads what the server holds and says whether the write is
  /// already in. If it is, the write counts as done. If reading fails too,
  /// [unsure] is the failure's line, which does not say nothing was sent.
  Future<bool> _write(
    Future<void> Function(SeerrService service) call, {
    required String failure,
    required VoidCallback retry,
    Future<bool> Function(SeerrService service)? alreadyThere,
    String? unsure,
  }) async {
    final issue = ref.read(mediaReportIssueProvider(_source)).value;
    try {
      await call(ref.read(seerrServiceForProvider(_id)));
      _readAgain(issue);
      return true;
    } catch (error) {
      if (!mounted) return false;
      var line = failure;
      if (alreadyThere != null && writeMayHaveLanded(error)) {
        try {
          if (await alreadyThere(ref.read(seerrServiceForProvider(_id)))) {
            if (mounted) _readAgain(issue);
            return true;
          }
        } catch (_) {
          line = unsure ?? failure;
        }
        if (!mounted) return false;
      }
      switch (seerrRefusalOf(error)) {
        case SeerrRefusal.issueGone || SeerrRefusal.replyGone:
          _readAgain(issue);
          setState(() => _editing = null);
        case _:
          SnackBarHelper.error(context, line, cause: error, onRetry: retry);
      }
      return false;
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final before =
        ref.read(mediaReportIssueProvider(_source)).value?.comments.length ?? 0;
    final sent = await _write(
      (service) => service.commentOnIssue(widget.issueId, text),
      failure: 'Could not send the reply. Nothing was sent.',
      unsure: 'Could not send the reply. We can’t tell if it arrived.',
      alreadyThere: (service) => service.hasSentReply(
        widget.issueId,
        text,
        userId: ref.read(seerrActingUserIdProvider(_id)),
        before: before,
      ),
      retry: _send,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) _reply.clear();
  }

  void _startEdit(SeerrIssueComment reply) => setState(() {
    _editing = reply.id;
    _edit.text = reply.message;
  });

  Future<void> _saveEdit(SeerrIssueComment reply) async {
    final text = _edit.text.trim();
    if (text.isEmpty || _saving) return;
    if (text == reply.message.trim()) {
      setState(() => _editing = null);
      return;
    }
    setState(() => _saving = true);
    final saved = await _write(
      (service) => service.editComment(reply.id, text),
      failure: 'Could not save the reply. Nothing changed.',
      retry: () => _saveEdit(reply),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _editing = null;
    });
  }

  Future<void> _deleteReply(SeerrIssueComment reply, {String? who}) async {
    final confirmed = await showDeleteReplyConfirm(
      context,
      who: who ?? (_operator ? 'The reporter' : 'Whoever runs the server'),
    );
    if (!confirmed.confirmed || !mounted) return;
    await _write(
      (service) => service.deleteComment(reply.id),
      failure: 'Could not delete the reply. Nothing changed.',
      retry: () => _removeReply(reply),
    );
  }

  /// Deletes without asking again: what `Retry` on a failed delete does.
  Future<void> _removeReply(SeerrIssueComment reply) => _write(
    (service) => service.deleteComment(reply.id),
    failure: 'Could not delete the reply. Nothing changed.',
    retry: () => _removeReply(reply),
  );

  Future<void> _setStatus(SeerrIssue issue, SeerrIssueStatus status) async {
    if (_busy != null) return;
    final operator = _operator;
    final resolving = status == SeerrIssueStatus.resolved;
    final busy = resolving ? 'resolve' : 'reopen';
    setState(() => _busy = busy);
    await _write(
      (service) => service.setIssueStatus(issue.id, status),
      failure: operator
          ? 'Could not ${resolving ? 'resolve' : 'reopen'} the issue. '
                'Nothing changed.'
          : resolving
          ? 'Could not mark it as resolved. Nothing changed.'
          : 'Could not reopen it. Nothing changed.',
      retry: () => _setStatus(issue, status),
    );
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _deleteIssue(SeerrIssue issue, {String? reporter}) async {
    if (_busy != null) return;
    final operator = _operator;
    final confirmed = operator
        ? await showDeleteIssueConfirm(context, reporter: reporter)
        : await showDeleteReportConfirm(context);
    if (!confirmed.confirmed || !mounted) return;
    setState(() => _busy = 'delete');
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final key = mediaKeyOfIssue(issue);
    final container = ref.container;
    final id = _id;
    try {
      await ref.read(seerrServiceForProvider(id)).deleteIssue(issue.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = null);
      if (seerrRefusalOf(error) == SeerrRefusal.issueGone) {
        _readAgain(issue);
        return;
      }
      SnackBarHelper.error(
        context,
        operator
            ? 'Could not delete the issue. Nothing changed.'
            : 'Could not delete the report. Nothing changed.',
        cause: error,
        onRetry: () => _deleteIssue(issue, reporter: reporter),
      );
      return;
    }
    // Leave before the lists are read: the page would otherwise read the
    // issue it just deleted and say it is gone.
    if (mounted) {
      setState(() => _busy = null);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        _leave();
      }
    }
    if (key != null) {
      readReportsAgain(container, key: key, connectionId: id);
    } else {
      readIssuesAgain(container);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(operator ? 'Issue deleted' : 'Report deleted')),
    );
  }

  /// Back to where the issue was opened from; with nowhere to go back to (a
  /// link that opened it cold), to the list it belongs in.
  void _leave() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go(_operator ? ServiceRoutes.seerrIssues : ServiceRoutes.requests);
  }

  Future<void> _search(List<IssueFile> files) async {
    if (files.length == 1) {
      await showReleaseSearch(context, ref, files.single.target);
      return;
    }
    // Several copies: the same choice the title page asks.
    await AppBottomSheet.show<void>(
      context: context,
      title: 'Search a new release',
      builder: (sheet) => MediaCopyChoices(
        verb: 'Search releases on',
        copies: [
          for (final file in files)
            (name: file.connectionName, target: file.target),
        ],
        onChoose: (target) {
          Navigator.of(sheet).pop();
          showReleaseSearch(context, ref, target);
        },
      ),
    );
  }

  /// Seerr's own page of the issue, at the address the connection is reached
  /// at now: away from home, the one at home would not open.
  Future<void> _openInSeerr(SeerrIssue issue) async {
    final base = ref.read(connectionReachProvider(_id))?.url ?? '';
    final target = Uri.tryParse(UrlUtils.buildUrl(base, '/issues/${issue.id}'));
    final opened =
        UrlUtils.isLaunchableWebUri(target) &&
        await launchUrl(target!, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      SnackBarHelper.error(context, 'Could not open Seerr');
    }
  }
}

/// The room the page stands in, lit by the title, with the back plate pinned.
class _Page extends StatelessWidget {
  const _Page({this.light, this.body, this.child});

  final TitleLight? light;

  /// The page's own blocks, given the gutter of its column.
  final List<Widget> Function(double gutter)? body;

  /// A state that fills the page (loading, failed, gone).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return MediaRoom(
      light: light,
      child: LayoutBuilder(
        builder: (context, box) {
          final gutter = MediaDetailMetrics.gutterOf(box.maxWidth);
          final bottom = math.max(
            AppSpacing.xxxl,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          );
          return MediaPinnedPlates(
            inset: gutter,
            child: body == null
                ? Padding(
                    padding: EdgeInsets.only(
                      top: top + MediaPinnedPlates.reserve + AppSpacing.md,
                    ),
                    child: child,
                  )
                : CustomScrollView(
                    primary: true,
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          gutter,
                          top + AppSpacing.md,
                          gutter,
                          bottom,
                        ),
                        sliver: SliverList.list(
                          children: [
                            const SizedBox(height: MediaPinnedPlates.reserve),
                            const SizedBox(height: AppSpacing.md),
                            ...body!(gutter),
                          ],
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// The page while the issue is first read: the shape of what will be there.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShimmerPlaceholder.card(height: 80),
          const SizedBox(height: AppSpacing.xl),
          ShimmerPlaceholder.text(width: 260, height: 24),
          const SizedBox(height: AppSpacing.md),
          ShimmerPlaceholder.text(width: 180, height: 14),
          const SizedBox(height: AppSpacing.section),
          ShimmerPlaceholder.card(height: 72),
          const SizedBox(height: AppSpacing.md),
          ShimmerPlaceholder.card(height: 72),
        ],
      ),
    ),
  );
}

/// An issue somebody deleted meanwhile. The operator is told where and sent
/// back to the list; the requester reads that her report was deleted. Each has
/// the way back to its own list.
class _Gone extends StatelessWidget {
  const _Gone({required this.operator, required this.onBack});

  final bool operator;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: AppEmptyState(
      icon: Icons.flag_outlined,
      title: operator ? 'This issue is gone' : 'This report was deleted.',
      message: operator ? 'Someone deleted it in Seerr.' : null,
      action: OutlinedButton(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(220, 48),
        ),
        onPressed: onBack,
        child: Text(operator ? 'Back to Issues' : 'Back to Requests'),
      ),
    ),
  );
}
