import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/media_value_sheet.dart';

void main() {
  group('qualityProfileOptions', () {});

  group('the quality profile sheet (showMediaValueSheet)', () {});
  group('mediaValueMatches', () {
    test('ignores case, and finds words anywhere in the label', () {
      expect(mediaValueMatches('E4 · The Second Cycle', 'second'), isTrue);
      expect(mediaValueMatches('E4 · The Second Cycle', 'SECOND C'), isTrue);
      expect(mediaValueMatches('E4 · The Second Cycle', 'third'), isFalse);
      expect(mediaValueMatches('anything', '  '), isTrue);
    });

    test('a number is a whole number', () {
      expect(mediaValueMatches('E4 · Pilot', '4'), isTrue);
      expect(mediaValueMatches('E14 · Pilot', '4'), isFalse);
      expect(mediaValueMatches('E40 · Pilot', '4'), isFalse);
      expect(mediaValueMatches('E14 · Pilot', '14'), isTrue);
      expect(mediaValueMatches('E14 · Pilot', 'e1'), isFalse);
      expect(mediaValueMatches('4. Intro', '4'), isTrue);
    });
  });

  group('a long list (showMediaValueSheet)', () {});
}
