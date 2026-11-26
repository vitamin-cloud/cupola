import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  const silent = SocketException('Connection refused');
  const refused = ClassifiedFailure(ServiceFailureReason.unauthorized);

  group('merge', () {
    test('two connections of one service each keep their own answer', () {
      // The 4K Radarr did not answer. The HD one did, and its share of the
      // figure stands: keyed on the service alone, the 4K's silence took the
      // HD's answer out with it and a Radarr-only region read a dash.
      final merged = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, instanceId: 'radarr'),
        SourceCoverage.failure(
          ServiceKey.radarr,
          silent,
          instanceId: 'radarr-4k',
          name: '4K',
        ),
      ]);

      expect(merged.everySourceFailed, isFalse);
      expect(merged.isPartial, isTrue);
      expect(coveredFigure(3, merged), '3');
      expect(coverageNote(merged), 'Not in the total: Radarr 4K');
      expect(merged.failedServices, {ServiceKey.radarr});
    });

    test('nothing configured is whole, and is not a failure', () {
      final merged = SourceCoverage.merge([
        SourceCoverage.none,
        SourceCoverage.none,
      ]);
      expect(merged.isWhole, isTrue);
      expect(merged.everySourceFailed, isFalse);
    });
  });

  group('the figure', () {
    test('every source failed reads an em dash, never 0', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.failure(ServiceKey.qbittorrent, refused),
      ]);
      expect(coveredFigure(0, coverage), '—');
    });

    test('a source still out is not a failure yet', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.pendingOf([ServiceKey.sonarr]),
      ]);
      expect(coverage.everySourceFailed, isFalse);
      expect(coveredFigure(0, coverage), '0');
    });

    test('a dash is spoken as a missing count', () {
      expect(
        spokenCountPhrase('— downloading'),
        'downloading, count unavailable',
      );
      expect(spokenCountPhrase('3 downloading'), '3 downloading');
    });

    test('a source that answered with part of itself makes the figure a '
        'floor, with nobody to name', () {
      // Radarr's queue walk stopped on a full page with no total: its rows
      // are what arrived, not the queue.
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
        SourceCoverage.answeredBy(ServiceKey.qbittorrent),
      ]);

      expect(coverage.isFloor, isTrue);
      expect(coverage.isWhole, isFalse);
      expect(coveredFigure(200, coverage), '200+');
      expect(coverageNote(coverage), isNull);
    });

    test('a source that failed is not a floor of itself', () {
      // Answered short in one read and failed in another: the failure wins,
      // and the source is named under the figure instead.
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr, cutShort: true),
        SourceCoverage.failure(ServiceKey.radarr, silent),
        SourceCoverage.answeredBy(ServiceKey.sonarr),
      ]);

      expect(coverage.cutShort, isEmpty);
      expect(coverage.isFloor, isFalse);
      expect(coveredFigure(3, coverage), '3');
    });

    test('a floor is spoken as the least there is', () {
      expect(
        spokenCountPhrase('200+ downloading, 2.0 MB/\u2060s across 1 client'),
        'at least 200 downloading, 2.0 MB/\u2060s across 1 client',
      );
      expect(spokenCountPhrase('3+'), 'at least 3');
    });
  });

  group('the note under a partial total', () {
    test('is absent when the total is whole, or when there is no total', () {
      expect(
        coverageNote(SourceCoverage.answeredBy(ServiceKey.radarr)),
        isNull,
      );
      expect(
        coverageNote(SourceCoverage.failure(ServiceKey.radarr, silent)),
        isNull,
      );
    });

    test('a refusal alone is amber', () {
      final coverage = SourceCoverage.merge([
        SourceCoverage.answeredBy(ServiceKey.radarr),
        SourceCoverage.failure(ServiceKey.sonarr, refused),
      ]);
      expect(coverage.anyDidNotAnswer, isFalse);
      expect(coverageNote(coverage), 'Not in the total: Sonarr');
    });
  });

  test('every source failed says each in its own words', () {
    final coverage = SourceCoverage.merge([
      SourceCoverage.failure(ServiceKey.radarr, silent),
      SourceCoverage.failure(ServiceKey.sonarr, silent),
      SourceCoverage.failure(ServiceKey.qbittorrent, refused),
    ]);

    expect(
      coverageFailureSentence(coverage),
      'Radarr and Sonarr did not answer. qBittorrent answered but refused '
      'the sign-in.',
    );
  });

  group('equal faults are grouped', () {
    const slow = ClassifiedFailure(ServiceFailureReason.timeout);

    test('a fault that cannot be said of many says each', () {
      const gateway = ClassifiedFailure(ServiceFailureReason.accessGateway);
      final coverage = SourceCoverage.merge([
        SourceCoverage.failure(ServiceKey.radarr, gateway),
        SourceCoverage.failure(ServiceKey.sonarr, gateway),
      ]);
      expect(
        coverageFailureSentence(coverage),
        'Something in front of Radarr answered instead of it. Something in '
        'front of Sonarr answered instead of it.',
      );
    });
  });
}
