import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// What a title's row offers at its end, beside the row itself.
sealed class SearchRowAction {
  const SearchRowAction({required this.label});

  /// What it says to a screen reader: `Add Arrival to Radarr`.
  final String label;
}

/// The plus: adds the title to its arr (or does what [label] says: the plus
/// is the row's one verb).
final class SearchRowAdd extends SearchRowAction {
  const SearchRowAdd({
    required super.label,
    required this.onTap,
    this.busy = false,
  });

  final VoidCallback onTap;

  /// The write is out: the plus gives way to a spinner and the control does
  /// nothing until it is back.
  final bool busy;
}

/// `Request`: asks Seerr for the title, as far as the account may, so
/// [verdict] is the gate's for a request of its kind.
final class SearchRowRequest extends SearchRowAction {
  const SearchRowRequest({
    required super.label,
    required this.verdict,
    required this.onTap,
  });

  final GateVerdict verdict;
  final VoidCallback onTap;
}

/// The plus where nothing set up can add the title: dimmed but tappable,
/// its hint names [service], and a tap answers with [blockedMessage] and
/// the way to set [service] up.
final class SearchRowSetUp extends SearchRowAction {
  const SearchRowSetUp({
    required super.label,
    required this.service,
    required this.blockedMessage,
  });

  final ServiceKey service;
  final String blockedMessage;
}

/// One row of a search by kind, and of the atrium's people: a
/// title with its poster, what it is and where it stands, or a person with
/// their face and what they are known for. A library's own results are the
/// same row in two more shapes: an album with its square cover and an artist
/// or an author with their disc, both of which, unlike a person, say where
/// they stand and carry a control.
///
/// Flat on the page, no card: the section heading above groups the rows.
/// The row is one control that speaks one sentence; a title that can be
/// added or asked for carries a second control at its end ([SearchRowAction]),
/// which names what it does and where.
class SearchRow extends StatelessWidget {
  /// A movie or a series: [poster] (empty for none, drawn as the title's
  /// initials), [meta] (`Movie · 1996 · TMDB 8.0`), and where it stands,
  /// when there is something to say.
  const SearchRow.title({
    super.key,
    required this.title,
    required this.meta,
    this.status,
    this.statusHollow = false,
    String poster = '',
    this.posterHeaders,
    this.heroTag,
    required this.onTap,
    this.action,
    this.selected = false,
    this.padding = EdgeInsets.zero,
  }) : imageUrl = poster,
       hint = null,
       titleMarks = const [],
       spoken = null,
       coverName = null,
       _kind = _Kind.title;

  /// An album: its [cover] in a 44 square (the album's initials without one),
  /// [meta] (`The White Stripes · 2003 · Album`), and where it stands under
  /// that, [statusHollow] for the backlog's ring as the state words draw it.
  const SearchRow.album({
    super.key,
    required this.title,
    required this.meta,
    this.status,
    this.statusHollow = false,
    String cover = '',
    Map<String, String>? coverHeaders,
    required this.onTap,
    this.action,
    this.hint,
    this.titleMarks = const [],
    this.spoken,
    this.coverName,
    this.padding = EdgeInsets.zero,
  }) : imageUrl = cover,
       posterHeaders = coverHeaders,
       heroTag = null,
       selected = false,
       _kind = _Kind.album;

  /// Someone in a list of what a library holds or a catalog found (an artist,
  /// an author): their [photo] in a 44 disc (their initials without one), what
  /// they are under the name, where they stand, and a control at the end when
  /// there is one. Unlike [SearchRow.person], the atrium's, it has no chevron:
  /// what it opens, or does, is its own. [spoken], where the parts the default
  /// joins do not make the sentence: `Elbow, group, not in your library`.
  const SearchRow.disc({
    super.key,
    required String name,
    required String line,
    this.status,
    this.statusHollow = false,
    String photo = '',
    Map<String, String>? photoHeaders,
    required this.onTap,
    this.action,
    this.hint,
    this.spoken,
    this.padding = EdgeInsets.zero,
  }) : title = name,
       meta = line,
       imageUrl = photo,
       posterHeaders = photoHeaders,
       heroTag = null,
       selected = false,
       titleMarks = const [],
       coverName = null,
       _kind = _Kind.artist;

  /// A person: their [face] (empty for none, drawn as their initials) and
  /// one line under the name.
  const SearchRow.person({
    super.key,
    required String name,
    required String line,
    String face = '',
    required this.onTap,
    this.selected = false,
    this.padding = EdgeInsets.zero,
  }) : title = name,
       meta = line,
       imageUrl = face,
       status = null,
       statusHollow = false,
       hint = null,
       posterHeaders = null,
       heroTag = null,
       action = null,
       titleMarks = const [],
       spoken = null,
       coverName = null,
       _kind = _Kind.person;

  final String title;
  final String meta;

  /// Where the title stands, as a dot in its tone and a word.
  final ({String label, StatusTone tone})? status;

  /// The dot is the backlog's ring rather than a filled dot: what is wanted
  /// and not here, which no tone paints.
  final bool statusHollow;

  /// What a tap does, spoken after the sentence: `Adds it to Lidarr`.
  final String? hint;

  /// The stretches of [title] a search matched, marked as the words typed
  /// (underlined, in the primary ink). Ranges into [title]; none by default.
  final List<TextRange> titleMarks;

  /// The sentence a screen reader hears for the row, when the parts the
  /// default joins (title, meta, state) do not make it: `The Dragon, track 3
  /// on Sintel, 5:36, on disk`.
  final String? spoken;

  /// Whose initials the cover shows without a picture, when that is not the
  /// row's [title]: a found track's row wears its album's. Null for [title].
  final String? coverName;

  final String imageUrl;
  final Map<String, String>? posterHeaders;

  /// The poster flies into the title's page under this tag; null for none.
  final String? heroTag;

  /// What a tap does; null for a row that opens nothing, which is then no
  /// button to a screen reader and takes no press feedback.
  final VoidCallback? onTap;

  /// What the row offers at its end. Null where there is nothing to add or
  /// ask for, and then there is no control at all.
  final SearchRowAction? action;

  /// Whether the pane beside the list shows this row's page, on a tablet: the
  /// row sits on the room's strong fill, the mark of what is selected in the
  /// settings' list and the tab bar, and says so to a screen reader.
  final bool selected;

  /// Around the row, beside the list's own gutter: none in a search, the
  /// slab's inset among the atrium's people.
  final EdgeInsetsGeometry padding;

  final _Kind _kind;

  bool get _person => _kind == _Kind.person;

  /// The kinds of row whose text may take two lines: a title is one, for the
  /// rows of a list read at a glance.
  bool get _roomy => _kind != _Kind.title;

  /// The row's floor: a 2:3 poster 66 tall and 8 above and below it.
  static const double minHeight = 76;

  static const Size _poster = Size(44, 66);
  static const double _face = 44;
  static const Size _square = Size(44, 44);
  static const double _dot = 7;

  /// Up to two initials, for a title or a person with no picture: the first
  /// letter or digit of each of the first two words that have one, so a
  /// bracket or a dash never stands for a word (`SA` for *Sintel
  /// (Anniversary Edition)*).
  static String initialsOf(String name) {
    final initials = <String>[];
    for (final word in name.split(RegExp(r'\s+'))) {
      final match = _letterOrDigit.firstMatch(word);
      if (match == null) continue;
      initials.add(match.group(0)!.toUpperCase());
      if (initials.length == 2) break;
    }
    return initials.join();
  }

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final status = this.status;
    // The dots of an album's or a disc's meta are commas to the ear.
    final said = _roomy ? splitParts(meta).join(', ') : meta;
    final statusSaid = status == null
        ? null
        : (_roomy ? splitParts(status.label).join(', ') : status.label);
    final heard = [said, ?statusSaid].where((s) => s.isNotEmpty).join(', ');

    final row = PressableScale(
      onTap: onTap,
      semanticLabel: spoken ?? title,
      semanticValue: spoken == null ? heard : null,
      // A row that opens nothing has nothing to say of what a tap does.
      semanticHint: onTap == null ? null : hint,
      semanticSelected: selected ? true : null,
      excludeChildSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              switch (_kind) {
                _Kind.person || _Kind.artist => _faceOf(room),
                _Kind.album => _coverOf(room),
                _Kind.title => _posterOf(room),
              },
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _titleOf(room),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        meta,
                        maxLines: _roomy ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.meta.copyWith(color: room.inkSecondary),
                      ),
                    ],
                    if (status != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        // The dot stays level with the first line of a word
                        // that wraps.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // One line of the word's own style under the dot:
                          // the cell is as tall as the first line, whatever
                          // the reading size, and the dot sits in its middle.
                          ExcludeSemantics(
                            child: SizedBox(
                              width: _dot,
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  Opacity(
                                    opacity: 0,
                                    child: Text(
                                      ' ',
                                      maxLines: 1,
                                      softWrap: false,
                                      style: AppType.caption.weight(
                                        FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: _dot,
                                    height: _dot,
                                    decoration: BoxDecoration(
                                      color: statusHollow
                                          ? null
                                          : statusToneColor(
                                              colorScheme,
                                              status.tone,
                                            ),
                                      border: statusHollow
                                          ? Border.all(
                                              color: room.inkSecondary,
                                              width: 1.5,
                                            )
                                          : null,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s),
                          Flexible(
                            // Two lines: a state word never loses words to an
                            // ellipsis at a large reading size.
                            child: Text(
                              status.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption
                                  .weight(FontWeight.w600)
                                  .copyWith(color: room.inkSecondary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (_person) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.chevron_right_rounded, color: room.inkSecondary),
              ],
            ],
          ),
        ),
      ),
    );

    final action = this.action;
    final trailing = switch (action) {
      null => null,
      SearchRowAdd(:final label, :final onTap, :final busy) => PressableScale(
        // A write in flight takes no second tap.
        onTap: busy ? null : onTap,
        semanticLabel: label,
        excludeChildSemantics: true,
        child: _Plus(busy: busy),
      ),
      SearchRowSetUp(:final label, :final service, :final blockedMessage) =>
        CrossServiceAction(
          target: service,
          label: label,
          blockedMessage: blockedMessage,
          // Never reached: once the service is set up the row offers its add.
          onTap: () {},
          child: const _Plus(),
        ),
      SearchRowRequest(:final label, :final verdict, :final onTap) =>
        RoleGatedAction.builder(
          verdict: verdict,
          onTap: onTap,
          builder: (context, onPressed, annotate) => OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              visualDensity: VisualDensity.standard,
              backgroundColor: room.fillQuiet,
              foregroundColor: room.ink,
              side: BorderSide(color: room.hair),
              textStyle: AppType.button,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            ),
            child: annotate(
              Semantics(
                label: label,
                excludeSemantics: true,
                child: const Text('Request'),
              ),
            ),
          ),
        ),
    };
    // A worded control at a large reading size takes the line under the
    // row, at its end: beside it, it left the title three letters.
    final under =
        action is SearchRowRequest &&
        MediaQuery.textScalerOf(context).scale(14) > 14 * 1.4;
    return Padding(
      padding: padding,
      // One shape selected or not, so the row under it keeps its state; the
      // fill reaches into the gutter, so nothing in the row moves.
      child: CustomPaint(
        painter: selected ? _Selected(room.fillStrong) : null,
        child: switch (trailing) {
          null => row,
          final trailing when under => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row,
              Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
          final trailing => Row(
            children: [
              Expanded(child: row),
              const SizedBox(width: AppSpacing.sm),
              trailing,
            ],
          ),
        },
      ),
    );
  }

  /// The title, with what a search matched marked: underlined, in the primary
  /// ink (the row's own ink, so the mark is the line, not a colour).
  Widget _titleOf(CupolaRoom room) {
    final style = AppType.row.copyWith(color: room.ink);
    if (titleMarks.isEmpty) {
      return Text(
        title,
        // A long title takes a second line, so titles that share a long
        // beginning can still be told apart; a person's name keeps one.
        maxLines: _person ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final marked = TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: room.ink,
    );
    var from = 0;
    final spans = <TextSpan>[];
    for (final mark in titleMarks) {
      if (mark.start > from) {
        spans.add(TextSpan(text: title.substring(from, mark.start)));
      }
      spans.add(
        TextSpan(text: title.substring(mark.start, mark.end), style: marked),
      );
      from = mark.end;
    }
    if (from < title.length) spans.add(TextSpan(text: title.substring(from)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: _person ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }

  Widget _posterOf(CupolaRoom room) {
    final plate = Container(
      width: _poster.width,
      height: _poster.height,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: room.fillQuiet,
        borderRadius: BorderRadius.circular(AppRadius.thumb),
        border: imageUrl.isEmpty ? Border.all(color: room.hair) : null,
      ),
      child: imageUrl.isEmpty
          ? _initials(room)
          : ArtworkDecodeBox(
              box: _poster,
              builder: (context, decode) => CachedNetworkImage(
                imageUrl: imageUrl,
                httpHeaders: posterHeaders,
                cacheManager: pinnedImageCacheFor(imageUrl),
                memCacheWidth: decode.width,
                memCacheHeight: decode.height,
                width: _poster.width,
                height: _poster.height,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _initials(room),
              ),
            ),
    );
    final tag = heroTag;
    if (tag == null || imageUrl.isEmpty) return plate;
    return Hero(
      tag: tag,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: plate,
    );
  }

  Widget _coverOf(CupolaRoom room) => Container(
    width: _square.width,
    height: _square.height,
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: room.fillQuiet,
      borderRadius: BorderRadius.circular(AppRadius.thumb),
      border: Border.all(color: room.hair),
    ),
    child: imageUrl.isEmpty
        ? _initials(room)
        : ArtworkDecodeBox(
            box: _square,
            builder: (context, decode) => CachedNetworkImage(
              imageUrl: imageUrl,
              httpHeaders: posterHeaders,
              cacheManager: pinnedImageCacheFor(imageUrl),
              memCacheWidth: decode.width,
              memCacheHeight: decode.height,
              width: _square.width,
              height: _square.height,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _initials(room),
            ),
          ),
  );

  Widget _faceOf(CupolaRoom room) => Container(
    width: _face,
    height: _face,
    clipBehavior: Clip.antiAlias,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: room.fillQuiet,
      shape: BoxShape.circle,
      border: Border.all(color: room.hair),
    ),
    child: imageUrl.isEmpty
        ? _initials(room)
        : ArtworkDecodeBox(
            box: const Size.square(_face),
            builder: (context, decode) => CachedNetworkImage(
              imageUrl: imageUrl,
              httpHeaders: posterHeaders,
              cacheManager: pinnedImageCacheFor(imageUrl),
              memCacheWidth: decode.width,
              memCacheHeight: decode.height,
              width: _face,
              height: _face,
              fit: BoxFit.cover,
              errorWidget: (_, _, _) => _initials(room),
            ),
          ),
  );

  /// The initials stop at the compact tiles' ceiling: past it two letters
  /// fill a 44pt plate edge to edge.
  Widget _initials(CupolaRoom room) => Builder(
    builder: (context) => Text(
      initialsOf(coverName ?? title),
      textScaler: TextScaleMetrics.clampedScalerOf(context),
      style: AppType.label.copyWith(color: room.ink),
    ),
  );
}

/// What a row is a picture of, which is its shape.
enum _Kind { title, person, album, artist }

/// The plus at a row's end: a 44 disc in the room's quiet fill, a spinner in
/// it while the write is out.
class _Plus extends StatelessWidget {
  const _Plus({this.busy = false});

  final bool busy;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: room.fillQuiet,
        shape: BoxShape.circle,
        border: Border.all(color: room.hair),
      ),
      child: busy
          ? const Center(
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(Icons.add_rounded, size: 20, color: room.ink),
    );
  }
}

/// A section's name over a search's rows, in the secondary ink, with how many
/// it holds on the right where the search knows it.
class SearchHeading extends StatelessWidget {
  const SearchHeading(
    this.text, {
    super.key,
    this.top = AppSpacing.md,
    this.count,
  });

  final String text;
  final double top;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text,
                style: AppType.label.copyWith(color: room.inkSecondary),
              ),
            ),
          ),
          if (count != null)
            Text(
              '$count',
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
        ],
      ),
    );
  }
}

/// What a row's picture is while the rows are still on their way.
enum SearchRowsShape {
  poster(44, 66, AppRadius.thumb),
  square(44, 44, AppRadius.thumb),
  circle(44, 44, 22);

  const SearchRowsShape(this.width, this.height, this.radius);

  final double width;
  final double height;
  final double radius;
}

/// Rows still on their way: plates at a row's size, spoken as [label].
class SearchRowsPending extends StatelessWidget {
  const SearchRowsPending({
    super.key,
    required this.label,
    this.rows = 3,
    this.shape = SearchRowsShape.poster,
  });

  final String label;
  final int rows;
  final SearchRowsShape shape;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  ShimmerPlaceholder(
                    width: shape.width,
                    height: shape.height,
                    borderRadius: BorderRadius.circular(shape.radius),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerPlaceholder(
                          height: 14,
                          width: 160,
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ShimmerPlaceholder(
                          height: 12,
                          width: 100,
                          borderRadius: AppRadius.borderRadiusXs,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

/// A search with nothing to show: [title] in the section role, [message]
/// under it, and where there is a next step [action]; [icon] over it when the
/// absence wants a mark.
class SearchNothing extends StatelessWidget {
  const SearchNothing({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.action,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Semantics(
        container: true,
        liveRegion: true,
        explicitChildNodes: true,
        child: Column(
          children: [
            if (icon != null) ...[
              ExcludeSemantics(
                child: Icon(icon, size: 28, color: room.inkTertiary),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppType.section.copyWith(color: room.ink),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppType.meta.copyWith(color: room.inkSecondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The room's strong fill behind a selected row, reaching [_reach] into the
/// gutter on either side.
class _Selected extends CustomPainter {
  const _Selected(this.color);

  final Color color;

  static const double _reach = AppSpacing.sm;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(-_reach, 0, size.width + _reach, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(AppRadius.md)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Selected oldDelegate) => color != oldDelegate.color;
}
