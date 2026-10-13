import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_providers.dart';
import '../../../core/theme/app_theme.dart';

/// Three steps: bodyweight, Apple Health permissions, how the streak works.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  final _bw = TextEditingController();
  int _page = 0;
  bool _healthAsked = false;
  bool _healthBusy = false;
  String? _healthStatus;

  @override
  void dispose() {
    _pages.dispose();
    _bw.dispose();
    super.dispose();
  }

  double? get _bodyweight {
    final v = double.tryParse(_bw.text.replaceAll(',', '.'));
    return v != null && v >= 30 && v <= 300 ? v : null;
  }

  void _next() {
    FocusScope.of(context).unfocus();
    _pages.nextPage(duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  Future<void> _connectHealth() async {
    setState(() => _healthBusy = true);
    final source = ref.read(healthSourceProvider);
    final ok = await source.requestPermissions();
    await ref.read(settingsControllerProvider).setHealthRequested(true);
    await ref.read(notificationServiceProvider).requestPermission();
    await ref.read(healthSyncProvider.notifier).sync();
    final sync = ref.read(healthSyncProvider);
    final days = sync.lastResult?.daysWithData ?? 0;
    final mass = sync.lastResult?.bodyMass;
    if (!mounted) return;
    setState(() {
      _healthBusy = false;
      _healthAsked = true;
      _healthStatus = !ok
          ? 'Apple Health isn\'t available. Spotter will work without it and readiness stays neutral.'
          : days == 0
              ? 'Connected. No recovery data found yet — wear your Apple Watch to sleep. You can change access in the Health app.'
              : 'Connected. Found recovery data for $days of the last ${sync.lastResult?.days ?? 0} days.';
      if (mass != null && _bw.text.isEmpty) _bw.text = mass.kg.toStringAsFixed(1);
    });
  }

  Future<void> _finish() async {
    final bw = _bodyweight;
    final hasHealthWeight = ref.read(healthSyncProvider).lastResult?.bodyMass != null;
    if (bw != null && !hasHealthWeight) await ref.read(bodyWeightRepositoryProvider).addManual(bw);
    await ref.read(settingsControllerProvider).setOnboarded(true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSettingsProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: i <= _page ? AppColors.primary : AppColors.surfaceHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (p) => setState(() => _page = p),
                children: [_welcome(), _health(), _streakPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame({required IconData icon, required String title, required String body, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Icon(icon, size: 64, color: AppColors.primary),
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 16, height: 1.4)),
        const SizedBox(height: 28),
        ...children,
      ],
    );
  }

  Widget _welcome() {
    return _frame(
      icon: Icons.shield_moon_rounded,
      title: 'Spotter',
      body: 'Your coach suggests weight, reps and sets for every exercise from your history and last night\'s recovery, '
          'and calls you out when ego takes over. Everything stays on this iPhone.',
      children: [
        TextField(
          controller: _bw,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(labelText: 'Bodyweight', suffixText: 'kg', helperText: 'Used to rank your lifts. Apple Health\'s latest weight wins if available.'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _next, child: Text(_bodyweight == null ? 'Skip for now' : 'Next')),
      ],
    );
  }

  Widget _health() {
    final fake = ref.watch(healthSourceProvider).isFake;
    return _frame(
      icon: Icons.favorite_rounded,
      title: 'Connect Apple Health',
      body: 'Spotter reads HRV, resting heart rate and sleep from your Apple Watch to score your readiness each morning, '
          'plus active energy and body weight. It saves each finished session as a strength workout.\n\n'
          'If you deny access or data is missing, the app keeps working with a neutral readiness and tells you what\'s missing. '
          'It also asks to send rest-timer alerts.',
      children: [
        FilledButton.icon(
          onPressed: _healthBusy ? null : _connectHealth,
          icon: _healthBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link_rounded),
          label: Text(_healthAsked ? 'Ask again' : (fake ? 'Connect fake data (debug)' : 'Connect Apple Health')),
        ),
        if (_healthStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_healthStatus!, style: const TextStyle(height: 1.4)),
          ),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _next, child: Text(_healthAsked ? 'Next' : 'Not now')),
      ],
    );
  }

  Widget _streakPage() {
    return _frame(
      icon: Icons.local_fire_department_rounded,
      title: 'Your streak',
      body: 'Every day counts, rest days too. Take up to two rest days in a row; if a third one ends without a '
          'workout, the streak starts over. No weekly goal, no fixed training days.',
      children: [
        const SizedBox(height: 12),
        FilledButton(onPressed: _finish, child: const Text('Let\'s lift')),
      ],
    );
  }
}
