import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../router.dart';
import 'exercise_demo.dart';

/// Compact form check during a workout: the 3D loop and the first cues, without leaving the session.
Future<void> showFormCheckSheet(BuildContext context, String exerciseId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final info = ref.watch(catalogProvider).value?[exerciseId];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(info?.name ?? exerciseId, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: ExerciseDemo(exerciseId: exerciseId, fallbackImages: info?.imageUrls ?? const [], compact: true),
                ),
              ),
              if (info != null && info.instructions.isNotEmpty) ...[
                const SizedBox(height: 14),
                for (final step in info.instructions.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('•  ', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900)),
                      Expanded(child: Text(step, style: const TextStyle(height: 1.35))),
                    ]),
                  ),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push(Routes.exercise(exerciseId));
                },
                icon: const Icon(Icons.smart_display_rounded),
                label: const Text('Full tutorial & video'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
