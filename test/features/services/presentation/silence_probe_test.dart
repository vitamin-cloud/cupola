/// The probe notes since when a connection has not answered.
///
/// Driven through the app's real clients on the profiles' fake network, as
/// the probe's classification is: a refused dial starts a silence, any answer
/// ends it (a refused key included), and the first time is the one that
/// stays across every probe that fails after it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/read_clock.dart';
import 'package:cupola/core/status/silence_clock.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/profiles/profiles.dart';

/// The settings a test edits mid-run.
final _editedSettings = NotifierProvider<_EditedSettings, SettingsModel>(
  () => _EditedSettings(const SettingsModel()),
);

class _EditedSettings extends Notifier<SettingsModel> {
  _EditedSettings(this._initial);

  final SettingsModel _initial;

  @override
  SettingsModel build() => _initial;

  void set(SettingsModel settings) => state = settings;
}

void main() {
  late DateTime now;
  late ProfileHarness harness;
  late ProviderContainer container;

  Future<void> start(ConfigProfile profile) async {
    now = DateTime(2026, 10, 12, 20, 41);
    harness = await ProfileHarness.start(
      profile,
      overrides: [
        readClockProvider.overrideWithValue(ReadClock(now: () => now)),
      ],
    );
    container = harness.container(retry: (_, _) => null);
  }


  /// Asks the probe again, as a Retry or a pull does.
  Future<ServiceSummary> probe(InstanceRef key) {
    container.invalidate(instanceSummaryProvider(key));
    return container.read(instanceSummaryProvider(key).future);
  }

  DateTime? silentSince(ServiceKey service, String id) =>
      container.read(silenceClockProvider).since(silenceKey(service, id));

  group('a probe that does not answer', () {


  });

  group('a connection that answers again', () {


  });

  group('a probe that is refused', () {
  });

  group('two connections of one service', () {
    test('are two silences', () async {
      await start(
        Profiles.p1.withBehaviour(
          WorldIds.radarr4k,
          ConnectionBehaviour.didNotAnswer,
        ),
      );

      await probe((service: ServiceKey.radarr, instanceId: WorldIds.radarr));
      await probe((service: ServiceKey.radarr, instanceId: WorldIds.radarr4k));

      expect(silentSince(ServiceKey.radarr, WorldIds.radarr4k), isNotNull);
      expect(silentSince(ServiceKey.radarr, WorldIds.radarr), isNull);
    });

    test('keep their own time, and each answer ends only its own', () async {
      await start(
        Profiles.p1
            .withBehaviour(WorldIds.radarr, ConnectionBehaviour.didNotAnswer)
            .withBehaviour(WorldIds.radarr4k, ConnectionBehaviour.didNotAnswer),
      );
      final radarr = (service: ServiceKey.radarr, instanceId: WorldIds.radarr);
      final radarr4k = (
        service: ServiceKey.radarr,
        instanceId: WorldIds.radarr4k,
      );
      await probe(radarr);
      now = DateTime(2026, 10, 12, 20, 55);
      await probe(radarr4k);

      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr),
        DateTime(2026, 10, 12, 20, 41),
      );
      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr4k),
        DateTime(2026, 10, 12, 20, 55),
      );

      harness.network.behave(WorldIds.radarr, ConnectionBehaviour.answers);
      await probe(radarr);

      expect(silentSince(ServiceKey.radarr, WorldIds.radarr), isNull);
      expect(
        silentSince(ServiceKey.radarr, WorldIds.radarr4k),
        DateTime(2026, 10, 12, 20, 55),
      );
    });
  });

  group('a connection that is not set up', () {
  });

}
