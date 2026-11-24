import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';

/// The next episode to air, in one slab: the day, which episode and when,
/// what will happen, and `Not aired`.
///
/// [operator] reads what Sonarr will do (`Sonarr looks for it once it airs`);
/// the requester reads no service's name.
class MediaNextAiringCard extends StatelessWidget {
  const MediaNextAiringCard({
    super.key,
    required this.next,
    required this.now,
    required this.operator,
  });

  final MediaNextAiring next;
  final DateTime now;
  final bool operator;

  String get _day => mediaAiringDay(next, now);

  /// `S3 E1 · premiere at 21:00`, `S2 E7 · at 21:00`, `S3 E1 · premiere`.
  String get _what {
    final when = [
      if (next.premiere) 'premiere',
      if (next.timed) 'at ${formatClockTime(next.at)}',
    ].join(' ');
    return [
      formatEpisodeCode(next.season, next.number),
      if (when.isNotEmpty) when,
    ].join(dotSeparator);
  }

  /// What will happen: Sonarr's part for the operator, else the season TMDB
  /// announces.
  String? get _then {
    if (operator && next.timed) {
      return next.sonarrMonitors
          ? 'Sonarr looks for it once it airs'
          : 'Sonarr is not set to look for it';
    }
    final count = next.seasonEpisodes;
    if (next.premiere && count != null) {
      return 'Season ${next.season}\u00A0· ${countLabel(count, 'episode')} announced';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final then = _then;
    return Semantics(
      container: true,
      label: [_day, _what, ?then, StateWord.notAired.label].join('. '),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.slabY,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: room.door,
          borderRadius: BorderRadius.circular(AppRadius.door),
          border: Border.all(color: room.hair),
        ),
        child: Row(
          children: [
            Text(_day, style: AppType.section.copyWith(color: room.ink)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_what, style: AppType.row.copyWith(color: room.ink)),
                  if (then != null)
                    Text(
                      then,
                      style: AppType.meta
                          .weight(FontWeight.w400)
                          .copyWith(color: room.inkSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            MediaStateWord(
              StateWord.notAired.label,
              tone: StatusTone.neutral,
              hollow: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// A series' episodes, a season at a time: the seasons as a segmented track,
/// then one row per episode (its number, its title, one word for where it
/// stands, a bar while it plays or downloads), then `Search the N missing`
/// where [onSearchMissing] can ask for them.
class MediaEpisodes extends StatefulWidget {
  const MediaEpisodes({
    super.key,
    required this.seasons,
    required this.initialSeason,
    this.onSearchMissing,
    this.onOpen,
    this.qualityOf,
  });

  final List<MediaSeason> seasons;

  /// Sonarr's quality for an episode on disk (`HDTV-1080p`), for the Status
  /// column; null when there is no file or it has not been read.
  final String? Function(MediaEpisode episode)? qualityOf;

  /// The season shown first: where the viewer is, else the latest aired.
  final int initialSeason;

  /// Asks Sonarr for a season's missing episodes; null where nothing can.
  final Future<void> Function(MediaSeason season)? onSearchMissing;

  /// Opens an episode's sheet.
  final void Function(MediaEpisode episode)? onOpen;

  @override
  State<MediaEpisodes> createState() => _MediaEpisodesState();
}

class _MediaEpisodesState extends State<MediaEpisodes> {
  late int _season = widget.initialSeason;

  /// A search asked for the season, until the season changes.
  final Set<int> _asked = {};
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    final seasons = widget.seasons;
    final season =
        seasons.where((s) => s.number == _season).firstOrNull ?? seasons.first;
    final missing = season.missing;
    final onSearch = widget.onSearchMissing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (seasons.length > 1) ...[
          _SeasonTrack(
            seasons: seasons,
            selected: season.number,
            onSelected: (number) => setState(() => _season = number),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        // This fork: Sonarr's own arrangement. Newest first; the number,
        // the title, the air date and the status (the file's quality, or
        // where it stands) in columns under a header.
        MediaGroup(
          children: [
            const _EpisodeHeader(),
            for (final episode in season.episodes.reversed)
              _EpisodeRow(
                episode,
                quality: widget.qualityOf?.call(episode),
                onTap: widget.onOpen == null
                    ? null
                    : () => widget.onOpen!(episode),
              ),
          ],
        ),
        if (onSearch != null && missing.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _asking || _asked.contains(season.number)
                ? null
                : () async {
                    setState(() => _asking = true);
                    try {
                      await onSearch(season);
                      if (mounted) setState(() => _asked.add(season.number));
                    } finally {
                      if (mounted) setState(() => _asking = false);
                    }
                  },
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              missing.length == 1
                  ? 'Search the missing one'
                  : 'Search the ${missing.length} missing',
            ),
          ),
        ],
      ],
    );
  }
}

/// The seasons as one track: a segment each, the chosen one in the ink. The
/// segments share the width when they fit and scroll when they do not; a
/// track that scrolls brings the chosen one into view, on opening (the latest
/// season sits at the far end) and whenever the choice changes.
class _SeasonTrack extends StatefulWidget {
  const _SeasonTrack({
    required this.seasons,
    required this.selected,
    required this.onSelected,
  });

  final List<MediaSeason> seasons;
  final int selected;
  final ValueChanged<int> onSelected;

  /// The narrowest a segment gets before the track scrolls.
  static const double _segment = 104;

  @override
  State<_SeasonTrack> createState() => _SeasonTrackState();
}

class _SeasonTrackState extends State<_SeasonTrack> {
  final _chosenKey = GlobalKey();

  /// The track's own scroll, so revealing a season never moves the page.
  final _track = ScrollController();

  @override
  void dispose() {
    _track.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _revealChosen(animate: false);
  }

  @override
  void didUpdateWidget(_SeasonTrack old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _revealChosen(animate: true);
  }

  void _revealChosen({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chosen = _chosenKey.currentContext?.findRenderObject();
      // A track that fits has nothing to scroll.
      if (!mounted || chosen is! RenderBox || !_track.hasClients) return;
      final position = _track.position;
      final target = RenderAbstractViewport.of(chosen)
          .getOffsetToReveal(chosen, 0.5)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (animate) {
        _track.animateTo(
          target,
          duration: AppAnimation.emphasized,
          curve: AppAnimation.standardCurve,
        );
      } else {
        _track.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final seasons = widget.seasons;
    final selected = widget.selected;
    final onSelected = widget.onSelected;
    const segmentWidth = _SeasonTrack._segment;
    Widget segment(MediaSeason season) {
      final chosen = season.number == selected;
      return Semantics(
        key: chosen ? _chosenKey : null,
        container: true,
        button: true,
        selected: chosen,
        label: season.label,
        onTap: () => onSelected(season.number),
        child: ExcludeSemantics(
          child: PressableScale(
            onTap: () => onSelected(season.number),
            child: AnimatedContainer(
              duration: AppAnimation.emphasized,
              curve: AppAnimation.standardCurve,
              constraints: const BoxConstraints(minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: chosen ? room.ink : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                season.label,
                maxLines: 1,
                style: AppType.label.copyWith(
                  color: chosen ? room.onInk : room.inkSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.door),
        border: Border.all(color: room.hair),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth / seasons.length >= segmentWidth) {
            return Row(
              children: [
                for (final season in seasons) Expanded(child: segment(season)),
              ],
            );
          }
          return SingleChildScrollView(
            controller: _track,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final season in seasons)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: segmentWidth),
                    child: segment(season),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The widths of the episode table's columns.
abstract final class _Cols {
  static const double number = 30;
  static const double date = 82;
  static const double status = 88;
}

/// `#  Title  Air Date  Status`, as Sonarr heads its season.
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader();

  @override
  Widget build(BuildContext context) {
    final style = AppType.meta.copyWith(
      color: CupolaRoom.of(context).inkTertiary,
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xs,
        ),
        child: Row(
          children: [
            SizedBox(
              width: _Cols.number,
              child: Text('#', style: style),
            ),
            Expanded(child: Text('Title', style: style)),
            SizedBox(
              width: _Cols.date,
              child: Text('Air Date', style: style),
            ),
            SizedBox(
              width: _Cols.status,
              child: Text('Status', style: style),
            ),
          ],
        ),
      ),
    );
  }
}

/// One episode as a row of Sonarr's table: its number, its title, the day it
/// airs, and its status: the file's quality when it is on disk, how far a
/// download is, `Missing` when it aired and nothing came, else the bookmark
/// that says whether Sonarr watches for it. A bar while it downloads or plays.
class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow(this.episode, {this.quality, this.onTap});

  final MediaEpisode episode;
  final String? quality;

  /// Opens the episode's sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final progress = episode.progress;
    final record = episode.fromSonarr;
    final now = DateTime.now();
    // Small enough that a date (`Dec 16 2026`) and a status always fit.
    final meta = AppType.meta.weight(FontWeight.w400).copyWith(fontSize: 11);

    Widget status() {
      if (episode.downloading) {
        return Text(
          episode.state,
          maxLines: 2,
          style: meta.copyWith(
            color: statusToneColor(
              scheme,
              StatusTone.info,
              surface: room.ground,
            ),
          ),
        );
      }
      if (quality case final q? when q.isNotEmpty) {
        return Align(
          alignment: Alignment.centerLeft,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: room.fillStrong,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                q,
                maxLines: 1,
                style: AppType.meta
                    .weight(FontWeight.w600)
                    .copyWith(color: room.ink, fontSize: 11),
              ),
            ),
          ),
        );
      }
      if (record == null) {
        // No Sonarr: the media server's word.
        return MediaStateWord(
          episode.state,
          tone: episode.tone,
          hollow: episode.tone == StatusTone.neutral,
        );
      }
      if (record.hasFile) {
        return Text(
          'Downloaded',
          style: meta.copyWith(color: room.inkSecondary),
        );
      }
      if (episode.missing) {
        return Text(
          'Missing',
          style: meta
              .weight(FontWeight.w600)
              .copyWith(
                color: statusToneColor(
                  scheme,
                  StatusTone.error,
                  surface: room.ground,
                ),
              ),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          record.monitored
              ? Icons.bookmark_border_rounded
              : Icons.bookmark_remove_outlined,
          size: 20,
          color: record.monitored ? room.inkSecondary : room.inkTertiary,
        ),
      );
    }

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: _Cols.number,
                child: Text(
                  '${episode.number}',
                  style: AppType.row
                      .weight(FontWeight.w400)
                      .copyWith(color: room.inkSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  episode.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.row.copyWith(color: room.ink),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: _Cols.date,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    episodeAirDay(episode.airsAt, now),
                    maxLines: 1,
                    softWrap: false,
                    style: meta.copyWith(color: room.inkSecondary),
                  ),
                ),
              ),
              SizedBox(width: _Cols.status, child: status()),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: room.fillTrack,
                color: episode.downloading
                    ? statusToneColor(
                        scheme,
                        StatusTone.info,
                        surface: room.ground,
                      )
                    : room.inkSecondary,
              ),
            ),
          ],
        ],
      ),
    );
    final onTap = this.onTap;
    if (onTap == null) {
      return Semantics(
        container: true,
        label: episode.spoken,
        excludeSemantics: true,
        child: row,
      );
    }
    return PressableScale(
      onTap: onTap,
      semanticLabel: episode.spoken,
      excludeChildSemantics: true,
      child: row,
    );
  }
}

/// The day an episode airs, as Sonarr's table says it: `Today`, `Tomorrow`,
/// `Yesterday`, else `Dec 16 2026`; `TBA` with no date.
String episodeAirDay(DateTime? airsAt, DateTime now) {
  if (airsAt == null) return 'TBA';
  final at = airsAt.toLocal();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[at.month - 1]} ${at.day} ${at.year}';
}

/// The day [next] airs, as a card or a graph row says it: `Today`,
/// `Tomorrow`, `Fri` within the week, else `9 Oct`.
String mediaAiringDay(MediaNextAiring next, DateTime now) {
  final at = next.timed ? next.at.toLocal() : next.at;
  final days = calendarDaysBetween(now, at);
  if (days <= 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  // `Fri` within the week, `9 Oct` beyond it (`9 Oct 2027` in another year).
  return days < 7 ? shortWeekdayName(at) : formatDayMonth(at, now: now);
}
