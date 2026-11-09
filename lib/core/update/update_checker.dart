import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../undo/undo_controller.dart';
import 'page_reload.dart';

/// Web only: notices when a newer version has been published and offers to
/// update. The build writes app_build.json (never cached) next to the app;
/// it is checked every few minutes and whenever the tab becomes active.
class UpdateChecker extends StatefulWidget {
  const UpdateChecker({super.key, required this.child});
  final Widget child;

  /// Only real builds know their own build id.
  static bool get enabled => kIsWeb && const bool.hasEnvironment('BUILD_ID');

  @override
  State<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends State<UpdateChecker>
    with WidgetsBindingObserver {
  static const _every = Duration(minutes: 5);
  Timer? _timer;
  bool _shown = false;
  DateTime? _snoozedUntil;

  @override
  void initState() {
    super.initState();
    if (!UpdateChecker.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_every, (_) => _check());
    // First check 10 seconds after the page loads, then every 5 minutes.
    Future<void>.delayed(const Duration(seconds: 10), _check);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_shown || !mounted) return;
    if (_snoozedUntil != null && DateTime.now().isBefore(_snoozedUntil!)) {
      return;
    }
    try {
      final response = await http.get(
        Uri.base.resolve(
          '/app_build.json?t=${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      if (response.statusCode != 200) return;
      final latest =
          (jsonDecode(response.body) as Map<String, dynamic>)['build_id'];
      if (latest is String &&
          latest.isNotEmpty &&
          latest != AppConfig.buildId) {
        _show(latest);
      }
    } catch (_) {
      // Offline or not deployed yet: try again later.
    }
  }

  void _show(String latest) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    _shown = true;
    messenger.showMaterialBanner(
      MaterialBanner(
        leading: const Icon(Icons.system_update_alt),
        content: const Text(
          'A new version of the app is available. Update to get the latest '
          'fixes; it takes a few seconds.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              _shown = false;
              _snoozedUntil = DateTime.now().add(const Duration(minutes: 30));
            },
            child: const Text('Later'),
          ),
          FilledButton(onPressed: reloadPage, child: const Text('Update')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
