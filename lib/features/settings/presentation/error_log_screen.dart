import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/diagnostics/error_log.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';

/// Every recorded error (newest first) with "Copy all" so bugs can be sent from the phone.
/// Reachable in release builds: Settings → long-press the version label.
class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  List<ErrorEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
    ErrorLog.instance.changes.listen((e) {
      if (mounted) setState(() => _entries = e.reversed.toList());
    });
  }

  Future<void> _load() async {
    final e = await ErrorLog.instance.entries();
    if (mounted) setState(() => _entries = e.reversed.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Error log'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _entries.isEmpty
                ? null
                : () async {
                    final ok = await confirm(context, title: 'Clear the error log?', message: 'All entries will be deleted.', action: 'Clear', destructive: true);
                    if (ok) await ErrorLog.instance.clear();
                  },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: BigButton(
            label: 'Copy all (${_entries.length})',
            icon: Icons.copy_all_rounded,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: await ErrorLog.instance.exportText()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Paste it into a message.')));
              }
            },
          ),
        ),
      ),
      body: _entries.isEmpty
          ? const EmptyState(icon: Icons.check_circle_outline, title: 'No errors', message: 'Nothing has gone wrong so far.')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final e = _entries[i];
                return GameCard(
                  accent: e.source == 'caught' ? AppColors.warning : AppColors.danger,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${DateFormat('d MMM HH:mm:ss').format(e.at)} · ${e.source} · ${e.route ?? '?'}',
                        style: AppType.label.copyWith(color: AppColors.textSecondary, letterSpacing: 0.3)),
                    const SizedBox(height: 6),
                    Text(e.error, style: AppType.bodyS.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(e.stack.split('\n').take(6).join('\n'),
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                );
              },
            ),
    );
  }
}
