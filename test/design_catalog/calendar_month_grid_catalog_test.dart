@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/discover/domain/library_calendar.dart';

import 'calendar_world.dart';
import 'catalog.dart';

void main() {
  // Wednesday's evening, four episodes deep.
  final busy = [
    ...CalendarWorld.events,
    for (final (title, hour) in [
      ('Harbour Lights', 20),
      ('The Long Field', 21),
      ('Cosmos Laundromat', 23),
    ])
      CalendarWorld.episode(title, 30, hour, 1, 2),
  ]..sort(compareCalendarEvents);
  catalogCard('CalendarMonthGrid', width: 860, scenes: []);
}
