import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/find_match.dart';

void main() {
  group('foldForFind', () {
    test('lower cases and takes the marks off', () {
      expect(foldForFind('Björk'), 'bjork');
      expect(foldForFind('Mötley Crüe'), 'motley crue');
      expect(foldForFind('Sigur Rós'), 'sigur ros');
      expect(foldForFind('Dvořák'), 'dvorak');
      expect(foldForFind('Beyoncé'), 'beyonce');
    });

    test('reads a stroke and a ligature as the letters they stand for', () {
      expect(foldForFind('Mø'), 'mo');
      expect(foldForFind('Æon'), 'aeon');
      expect(foldForFind('Straße'), 'strasse');
    });

    test('leaves what is not a Latin letter with a mark as it is', () {
      expect(foldForFind('坂本龍一 2'), '坂本龍一 2');
    });
  });

  group('matchesFindQuery', () {});
}
