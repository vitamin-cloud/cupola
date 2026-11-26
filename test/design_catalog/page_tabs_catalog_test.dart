@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/page_tabs.dart';
import 'package:cupola/features/activity/domain/activity_tab.dart';

import 'catalog.dart';

/// The four views of Activity at the head of the page, on the page's gutter.
Widget _tabs(ActivityTab selected) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: PageTabs<ActivityTab>(
    values: ActivityTab.values,
    selected: selected,
    labelBuilder: (tab) => tab.label,
    onSelected: (_) {},
    semanticLabel: 'Activity views',
  ),
);

void main() {
  catalogCard(
    'PageTabs',
    scenes: [
      CatalogScene(
        'PageTabs<ActivityTab>() · Downloads selected: the thumb is the '
        'page\'s, never a service\'s colour',
        (_) => _tabs(ActivityTab.downloads),
        width: 390,
      ),
      CatalogScene(
        'PageTabs<String>() · a long label no longer fits its share, so the '
        'track lays the four two by two at the default reading size',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: PageTabs<String>(
            values: const ['All', 'Downloads', 'Needs approval', 'History'],
            selected: 'Needs approval',
            labelBuilder: (label) => label,
            onSelected: (_) {},
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · on a 430pt phone, Downloads selected',
        (_) => _tabs(ActivityTab.downloads),
        width: 430,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'PageTabs<String>(countOf:) · the Review\'s jump: a count after each '
        'label, the second in amber, each selected in turn',
        (_) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final selected in const ['Clear', 'Need you']) ...[
              PageTabs<String>(
                values: const ['Clear', 'Need you'],
                selected: selected,
                labelBuilder: (label) => label,
                countOf: (label) => label == 'Clear'
                    ? (count: 12, tone: null)
                    : (count: 6, tone: StatusTone.warning),
                semanticLabel: 'Jump to',
                onSelected: (_) {},
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
        width: 390,
      ),
    ],
  );
}
