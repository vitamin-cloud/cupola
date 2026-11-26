import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/service_routes.dart';

/// The Home's two ways in while no service is set up: Set up a service opens
/// the Stack, where every service has its own set-up; Copy from another
/// device opens pairing.
class SetUpButtons extends StatelessWidget {
  const SetUpButtons({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FilledButton(
        onPressed: () => context.go(ServiceRoutes.stack),
        child: const Text('Set up a service'),
      ),
      const SizedBox(height: AppSpacing.md),
      OutlinedButton(
        onPressed: () => context.push(ServiceRoutes.welcomePair),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(64, 44),
        ),
        child: const Text('Copy from another device'),
      ),
    ],
  );
}
