import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/widgets/glass_panel.dart';
import 'package:cupola/features/shell/domain/screen_search.dart';

/// A reusable, always-visible search bar widget for the top of screens.
///
/// Provides debounced text input, clear button, and Material Design 3 styling.
/// Uses the M3 SearchBar widget with proper color tokens.
class SearchBarHeader extends StatefulWidget {
  /// Callback when the search query changes (debounced).
  final ValueChanged<String> onQueryChanged;

  /// Told of every change to the text, at once and trimmed, ahead of the
  /// debounce that holds [onQueryChanged]: for a screen that answers from
  /// what it already holds, where waiting would only be slower. Null for a
  /// screen that asks a server and has no use for the keystroke.
  final ValueChanged<String>? onTextChanged;

  /// Placeholder text for the search bar.
  final String hintText;

  /// Initial query value.
  final String? initialQuery;

  /// Debounce duration for search input.
  final Duration debounceDuration;

  /// Whether to autofocus the search field
  final bool autofocus;

  /// The field's focus, when the screen needs to know where the keyboard is
  /// (the Discover tab shows recent searches while the field is focused and
  /// empty). The field makes its own otherwise.
  final FocusNode? focusNode;

  /// Shows `Cancel` beside the field while it is focused or holds a query:
  /// it clears the query, lets go of the keyboard and then calls this. Null
  /// for no `Cancel`, as on a library, where the field is part of the page.
  final VoidCallback? onCancel;

  /// What the button that calls [onCancel] says: `Cancel` for a search that
  /// is abandoned, `Done` for a field that was opened to find one thing and
  /// closes.
  final String cancelLabel;

  /// The field's name to a screen reader, before its hint: `Search`, or what
  /// it finds when that is narrower (`Find a track by Jan Morgenstern`).
  final String label;

  /// The room around the field. The default is a screen's: the gutter at
  /// both sides. A field inside a page's own column takes none at the sides.
  final EdgeInsetsGeometry padding;

  const SearchBarHeader({
    super.key,
    required this.onQueryChanged,
    this.onTextChanged,
    this.hintText = 'Search',
    this.initialQuery,
    this.debounceDuration = const Duration(milliseconds: 400),
    this.autofocus = false,
    this.focusNode,
    this.onCancel,
    this.cancelLabel = 'Cancel',
    this.label = 'Search',
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
  });

  @override
  State<SearchBarHeader> createState() => _SearchBarHeaderState();
}

class _SearchBarHeaderState extends State<SearchBarHeader> {
  late final TextEditingController _controller;

  /// Held by the field so the window's `⌘F` has something to focus.
  ///
  /// Owned here rather than passed in by every caller: "search this screen"
  /// means this field, and there are twenty-odd screens whose only search field
  /// is this widget. See [ScreenSearchTarget] for why the registry is explicit
  /// rather than a walk of the tree.
  FocusNode? _ownFocusNode;
  Timer? _debounceTimer;
  bool _hasText = false;

  FocusNode get _focusNode => widget.focusNode ?? _ownFocusNode!;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.focusNode == null) {
      _ownFocusNode = FocusNode(debugLabel: 'screen search');
    }
    _focusNode.addListener(_onFocusChanged);
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  /// A query set from outside while the field is not in use (a link that
  /// opens this screen on a word) reaches the field; while the user types,
  /// the field is theirs.
  @override
  void didUpdateWidget(SearchBarHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.initialQuery ?? '';
    if (query != (oldWidget.initialQuery ?? '') &&
        !_focusNode.hasFocus &&
        _controller.text.trim() != query) {
      _controller.removeListener(_onTextChanged);
      _controller.text = query;
      _hasText = query.isNotEmpty;
      _controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.removeListener(_onFocusChanged);
    _ownFocusNode?.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (widget.onCancel != null && mounted) setState(() {});
  }

  void _cancel() {
    if (_controller.text.isNotEmpty) _controller.clear();
    // Clearing schedules a debounced empty query; this reports it now.
    _debounceTimer?.cancel();
    widget.onQueryChanged('');
    _focusNode.unfocus();
    widget.onCancel?.call();
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    widget.onTextChanged?.call(_controller.text.trim());

    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceDuration, () {
      widget.onQueryChanged(_controller.text.trim());
    });
  }

  void _clearQuery() {
    _controller.clear();
    widget.onQueryChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // The magnifier is the secondary ink, on every screen: the field is the
    // same field whichever service it searches, and a service's colour here
    // once put seven hues under 3:1 on paper. The room's secondary ink is
    // spaced for the field's own fill in both themes.
    final glyph = colorScheme.onSurfaceVariant;

    final field = Semantics(
      label: widget.label,
      hint: 'Type ${widget.hintText}',
      child: Padding(
        padding: widget.padding,
        child: _withCancel(
          SearchBar(
            controller: _controller,
            focusNode: _focusNode,
            hintText: widget.hintText,
            autoFocus: widget.autofocus,
            leading: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.sm),
              child: Icon(Icons.search_rounded, color: glyph),
            ),
            trailing: [
              if (_hasText)
                Semantics(
                  button: true,
                  label: 'Clear search',
                  hint: 'Remove the current search query',
                  onTap: _clearQuery,
                  child: ExcludeSemantics(
                    child: IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: _clearQuery,
                      tooltip: 'Clear search',
                    ),
                  ),
                ),
            ],
            elevation: WidgetStateProperty.all(0),
            // This fork: the remote's glass, as every card.
            backgroundColor: WidgetStateProperty.all(GlassPanel.tint),
            // A focused field's edge is `line.focus`, as every focused field's
            // is (`inputDecorationTheme`): the keyboard's place is never only a
            // caret.
            shape: WidgetStateProperty.resolveWith(
              (states) => RoundedRectangleBorder(
                borderRadius: AppRadius.borderRadiusMd,
                side: states.contains(WidgetState.focused)
                    ? BorderSide(
                        color: CupolaRoom.of(context).focus,
                        width: 1.5,
                      )
                    : const BorderSide(color: GlassPanel.rim, width: 1.5),
              ),
            ),
            constraints: const BoxConstraints(minHeight: 52),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            ),
          ),
        ),
      ),
    );

    // Only a desktop window has a `⌘F`, so only a desktop window pays for the
    // registration, and a phone build keeps this widget free of any provider
    // dependency at all.
    if (!AppBreakpoints.isDesktopShell(context)) return field;
    return ScreenSearchTarget(focusNode: _focusNode, child: field);
  }

  /// The field, and `Cancel` after it while the search is engaged.
  ///
  /// One shape whether `Cancel` shows or not: a field that moved into a row
  /// as it took the focus would be built again there, and the new one would
  /// hold the focus without the keyboard the first had just opened.
  Widget _withCancel(Widget field) {
    if (widget.onCancel == null) return field;
    final engaged = _focusNode.hasFocus || _hasText;
    return Row(
      children: [
        Expanded(child: field),
        if (engaged) ...[
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: _cancel,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              visualDensity: VisualDensity.standard,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              textStyle: AppType.button,
            ),
            child: Text(widget.cancelLabel),
          ),
        ],
      ],
    );
  }
}
