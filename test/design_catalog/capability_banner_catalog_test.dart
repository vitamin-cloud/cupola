@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/widgets/capability_banner.dart';
import 'package:cupola/features/truenas/presentation/truenas_capability.dart';
import 'package:cupola/features/unraid/presentation/unraid_capability.dart';

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
        'CapabilityBannerSlot · the service answered: Unraid key can read, '
        'not write VMs · "Update the key"',
        (_) => const CapabilityBannerSlot(
          connectionId: 'unraid-vms',
          copy: unraidVmsCopy,
        ),
        width: 640,
      ),
      CatalogScene(
        'CapabilityBannerSlot · a write was refused this session · the '
        'newer-evidence sentence',
        (_) => const CapabilityBannerSlot(
          connectionId: 'unraid-refused',
          copy: unraidVmsCopy,
        ),
        width: 640,
      ),
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
        'CapabilityBanner · bare, at 2x text scale · past stackThreshold '
        'the verb drops to its own line',
        (_) => CapabilityBanner(message: unraidVmsCopy.answered, onFix: () {}),
        width: 420,
        textScale: catalogTextScale,
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
