import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app_providers.dart';
import '../../../core/domain/dates.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../domain/readiness.dart';

/// Home card: today's score and band, the three metrics vs. baseline, and a plain-English reason.
class ReadinessCard extends ConsumerWidget {
  const ReadinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(todayReadinessProvider);
    final sync = ref.watch(healthSyncProvider);
    final source = ref.watch(healthSourceProvider);
    final overloaded = ref.watch(overloadedGroupsProvider);
    final energy = _energyYesterday(ref);

    if (r == null) {
      return const Skeleton(height: 210, radius: Radii.card);
    }
    final color = r.calibrating ? AppColors.accent : bandColor(r.band);
    final scoreText = r.score?.toString() ?? '—';
    final label = r.calibrating
        ? 'Calibrating (${r.baselineDays}/${ReadinessCalculator.calibrationDays} days)'
        : r.score == null
            ? 'No data · neutral'
            : r.band.label;

    return GameCard(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProgressRing(
                value: (r.score ?? ReadinessCalculator.neutralScore) / 100,
                color: color,
                size: 88,
                stroke: 8,
                child: Text(scoreText, style: AppType.displayL.copyWith(fontSize: 30)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('READINESS', style: AppType.label.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text(label, style: AppType.title.copyWith(color: color, fontSize: 22)),
                    const SizedBox(height: 4),
                    Text(r.reason, style: const TextStyle(height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Metric(label: 'HRV', reading: r.hrv, format: (v) => '${v.round()} ms', higherIsBetter: true)),
              Expanded(child: _Metric(label: 'Resting HR', reading: r.restingHr, format: (v) => '${v.round()} bpm', higherIsBetter: false)),
              Expanded(child: _Metric(label: 'Sleep', reading: r.sleep, format: formatSleep, higherIsBetter: true)),
            ],
          ),
          if (r.calibrating)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Suggestions treat today as Green until 14 days of baseline exist.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ),
          if (r.missing.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      r.missing.length == 3
                          ? 'No HRV, resting HR or sleep from ${source.name} for last night. '
                              'Wear your Apple Watch to sleep, or check Health permissions in Settings.'
                          : 'Missing ${r.missing.join(' and ')} — readiness re-weighted over the other metrics.',
                      style: const TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          if (overloaded.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.trending_up_rounded, size: 16, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'High load: ${overloaded.map((g) => g.label).join(', ')} volume is above 1.5× your 4-week average. '
                      'Readiness −10 for exercises training ${overloaded.length == 1 ? 'it' : 'them'}.',
                      style: const TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    source.name,
                    if (sync.lastSync != null) 'synced ${DateFormat('HH:mm').format(sync.lastSync!)}',
                    if (energy != null) 'active energy yesterday ${energy.round()} kcal',
                    if (sync.error != null) 'sync failed',
                  ].join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              IconButton(
                tooltip: 'Refresh from Health',
                onPressed: sync.syncing ? null : () => ref.read(healthSyncProvider.notifier).sync(),
                icon: sync.syncing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double? _energyYesterday(WidgetRef ref) {
    final rows = ref.watch(dailyMetricsProvider).value;
    if (rows == null || rows.length < 2) return null;
    final now = ref.watch(clockProvider)();
    final key = dayKey(addDays(dateOnly(now), -1));
    return rows.where((r) => r.date == key).firstOrNull?.activeEnergyKcal;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.reading, required this.format, required this.higherIsBetter});
  final String label;
  final MetricReading reading;
  final String Function(double) format;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final v = reading.value;
    final b = reading.baseline;
    final z = reading.z;
    final color = z == null
        ? AppColors.textPrimary
        : z <= -0.5
            ? AppColors.red
            : z >= 0.5
                ? AppColors.green
                : AppColors.textPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(v == null ? 'missing' : format(v),
            style: AppType.number.copyWith(fontSize: 18, color: v == null ? AppColors.textSecondary : color)),
        Text(
          b == null ? 'no baseline' : 'base ${format(b.mean)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
