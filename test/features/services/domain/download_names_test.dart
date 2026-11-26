import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/features/services/domain/download_names.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('arrForClientCategory', () {
    test('no category, or one that names no arr, points at none', () {
      expect(arrForClientCategory(null), isNull);
      expect(arrForClientCategory(' '), isNull);
      expect(arrForClientCategory('linux-isos'), isNull);
    });
  });

  group('namesFromParse', () {
    const release = 'Tears.of.Steel.2012.2160p.WEB';

    test('Radarr: a film it holds is the library\'s title', () {
      expect(
        namesFromParse(ServiceKey.radarr, release, {
          'title': release,
          'parsedMovieInfo': {
            'movieTitles': ['Tears of Steel'],
            'year': 2012,
          },
          'movie': {'id': 5, 'title': 'Tears of Steel', 'year': 2012},
        }),
        const MediaNames(
          title: 'Tears of Steel',
          machineName: release,
          machineKind: MachineNameKind.release,
        ),
      );
    });

    test('Radarr: a film it does not hold is its parser\'s reading', () {
      final names = namesFromParse(ServiceKey.radarr, release, {
        'title': release,
        'parsedMovieInfo': {
          'movieTitles': ['Tears of Steel'],
        },
      });
      expect(names?.title, 'Tears of Steel');
      expect(names?.source, MediaTitleSource.parser);
      expect(names?.machineName, release);
    });

    test('Sonarr: the series it holds, with the parsed episode', () {
      final names = namesFromParse(
        ServiceKey.sonarr,
        'Night.Shift.S02E07.1080p.WEB',
        {
          'parsedEpisodeInfo': {
            'seriesTitle': 'Night Shift',
            'seasonNumber': 2,
            'episodeNumbers': [7],
          },
          'series': {'id': 2, 'title': 'Night Shift'},
        },
      );
      expect(names?.title, startsWith('Night Shift\u00A0· S'));
      expect(names?.source, MediaTitleSource.library);

      final parsedOnly = namesFromParse(
        ServiceKey.sonarr,
        'Night.Shift.S02.1080p.WEB',
        {
          'parsedEpisodeInfo': {
            'seriesTitle': 'Night Shift',
            'seasonNumber': 2,
            'episodeNumbers': <int>[],
          },
        },
      );
      expect(parsedOnly?.title, 'Night Shift');
      expect(parsedOnly?.source, MediaTitleSource.parser);
    });
  });
}
