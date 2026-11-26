@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/presentation/widgets/calendar_agenda.dart';

import 'catalog.dart';

void main() {
  final friday = DateTime(2026, 10, 2);
  catalogCard(
    'CalendarAgenda',
    scenes: [
      CatalogScene(
        'CalendarQuietLine · three empty days or more, and the end of the '
        'thirty days',
        (_) => Column(
          children: [
            CalendarQuietLine.until(DateTime(2026, 10, 21)),
            const CalendarQuietLine.end(),
          ],
        ),
        width: 390,
      ),
    ],
  );
}
