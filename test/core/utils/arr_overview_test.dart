import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/arr_overview.dart';

void main() {
  group('isStalledRecord', () {});

  group('isImportFaultRecord', () {});

  group('historyRecordBytes', () {
    test('a size that is not one is none', () {
      expect(historyRecordBytes({'size': 0}), isNull);
      expect(
        historyRecordBytes({
          'data': {'size': 2048},
        }),
        2048,
      );
    });
  });

  group('overviewHistoryToday', () {
    final now = DateTime(2026, 9, 16, 12);
  });
}
