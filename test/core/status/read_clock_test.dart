import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

void main() {
  group('ReadClock', () {
    test('has no read for a key nothing has noted', () {
      expect(ReadClock().at('sabnzbd:home'), isNull);
    });

    test('keeps the time a key was noted at', () {
      final clock = ReadClock();
      final at = DateTime(2026, 10, 12, 9, 30);

      clock.note('sabnzbd:home', at);

      expect(clock.at('sabnzbd:home'), at);
    });

    test(
      'notes now, by its own reading of the time, when no time is given',
      () {
        var now = DateTime(2026, 10, 12, 9, 30);
        final clock = ReadClock(now: () => now);

        clock.note('sabnzbd:home');
        expect(clock.at('sabnzbd:home'), DateTime(2026, 10, 12, 9, 30));

        now = DateTime(2026, 10, 12, 9, 45);
        clock.note('sabnzbd:home');
        expect(
          clock.at('sabnzbd:home'),
          DateTime(2026, 10, 12, 9, 45),
          reason: 'a later read replaces the earlier one',
        );
        expect(clock.now(), DateTime(2026, 10, 12, 9, 45));
      },
    );

    test('keeps each key apart', () {
      final clock = ReadClock();
      final home = DateTime(2026, 10, 12, 9);
      final seedbox = DateTime(2026, 10, 12, 10);

      clock.note('sabnzbd:home', home);
      clock.note('sabnzbd:seedbox', seedbox);

      expect(clock.at('sabnzbd:home'), home);
      expect(clock.at('sabnzbd:seedbox'), seedbox);
      expect(clock.at('nzbget:home'), isNull);
    });
  });

  group('queueReadKey', () {
  });

  group('Ref.queueReadNoter', () {
    final settings = SettingsModel(
      instances: [
      ],
    );

    ProviderContainer containerOn(String lens, ReadClock clock) {
      final container = ProviderContainer(
        overrides: [
          currentSettingsProvider.overrideWith((ref) => settings),
          initialActiveInstancesProvider.overrideWithValue({
          }),
          readClockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }



  });
}
