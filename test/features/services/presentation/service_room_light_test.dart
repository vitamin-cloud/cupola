import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/presentation/service_room_light.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_session_poster.dart';

const _sintel = 'https://image.tmdb.org/t/p/original/sintel.jpg';

const _settings = SettingsModel(
  instances: [
    ServiceInstance(
      id: 'jf',
      service: ServiceKey.jellyfin,
      label: '',
      url: 'http://jellyfin.lan:8096',
      credential: 'k',
    ),
  ],
);

StreamSession _playing(String? titleId) => StreamSession(
  id: 's1',
  userName: 'Anna',
  title: 'Sintel',
  subtitle: null,
  deviceLabel: 'Living room TV',
  posterPath: '/Items/jf-sintel/Images/Primary',
  playMethod: StreamPlayMethod.directPlay,
  transcodeReasons: const [],
  bitrate: null,
  bitrateIsNominal: true,
  progress: 0.4,
  isPaused: false,
  titleId: titleId,
);

ProviderContainer _container({List<StreamSession> sessions = const []}) {
  final container = ProviderContainer(
    overrides: [
      currentSettingsProvider.overrideWith((ref) => _settings),
      streamSessionsForProvider.overrideWith((ref, key) async => sessions),
      streamSessionPosterProvider.overrideWith(
        (ref, title) async => title.titleId == 'jf-sintel' ? _sintel : null,
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<String?> _source(ProviderContainer container, ServiceKey service) async {
  final sub = container.listen(serviceRoomSourceProvider(service), (_, _) {});
  addTearDown(sub.close);
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return sub.read();
}

void main() {
  test('a media server\'s room is lit by what it plays, through the arrs\' '
      'public poster', () async {
    expect(
      await _source(
        _container(sessions: [_playing('jf-sintel')]),
        ServiceKey.jellyfin,
      ),
      _sintel,
    );
  });

  test('nothing playing, or a title no arr holds, is the lamp', () async {
    expect(await _source(_container(), ServiceKey.jellyfin), isNull);
    expect(
      await _source(
        _container(sessions: [_playing('jf-other')]),
        ServiceKey.jellyfin,
      ),
      isNull,
    );
  });
}
