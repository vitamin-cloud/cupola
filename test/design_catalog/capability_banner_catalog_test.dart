@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';

import '../test_helpers/capability_overrides.dart';
import 'catalog.dart';

const _grants = {
  'unraid-vms': CapabilityGrant.readOnly(),
  'unraid-refused': CapabilityGrant.refused(),
  'npm-view-only': CapabilityGrant.readOnly(),
  'npm-partial': CapabilityGrant.partial({'certificates'}),
  'truenas-unanswered': CapabilityGrant.unanswered(),
};

void main() {
  catalogCard(
    'CapabilityBanner',
    overrides: () async => [capabilityOverride(_grants)],
    scenes: [
      CatalogScene(
        'CapabilityBannerSlot · Cupola could not ask (TrueNAS) · "Check '
        'again", not a new key',
        (_) => const CapabilityBannerSlot(
          connectionId: 'truenas-unanswered',
          copy: trueNasCapabilityCopy,
        ),
        width: 640,
      ),
      CatalogScene(
        'Text at 200% · CapabilityBannerSlot, Cupola could not ask (TrueNAS): '
        'Check again on a 390pt phone',
        (_) => const CapabilityBannerSlot(
          connectionId: 'truenas-unanswered',
          copy: trueNasCapabilityCopy,
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
