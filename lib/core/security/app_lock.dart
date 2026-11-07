import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

/// Fingerprint / face check. Abstracted so tests can fake it.
abstract class BiometricAuthenticator {
  /// True when the device has biometrics set up and usable.
  Future<bool> isAvailable();

  /// Shows the system biometric prompt. True when the user passed.
  Future<bool> authenticate(String reason);
}

class LocalBiometricAuthenticator implements BiometricAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics &&
          (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

/// Per-user "biometric unlock on" flag, kept in the device's secure storage.
/// No password or token is stored: Supabase keeps the session; this is only
/// a lock in front of it.
abstract class LockPreferences {
  Future<bool> isEnabled(String userId);
  Future<void> setEnabled(String userId, bool enabled);
  Future<bool> wasOffered(String userId);
  Future<void> markOffered(String userId);
}

class SecureLockPreferences implements LockPreferences {
  static const _storage = FlutterSecureStorage();

  @override
  Future<bool> isEnabled(String userId) async =>
      await _storage.read(key: 'biometric_unlock_$userId') == 'on';

  @override
  Future<void> setEnabled(String userId, bool enabled) => _storage.write(
    key: 'biometric_unlock_$userId',
    value: enabled ? 'on' : 'off',
  );

  @override
  Future<bool> wasOffered(String userId) async =>
      await _storage.read(key: 'biometric_offered_$userId') == 'yes';

  @override
  Future<void> markOffered(String userId) =>
      _storage.write(key: 'biometric_offered_$userId', value: 'yes');
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (_) => LocalBiometricAuthenticator(),
);
final lockPreferencesProvider = Provider<LockPreferences>(
  (_) => SecureLockPreferences(),
);

/// The signed-in user's id, or null. Overridable in tests.
final currentUserIdProvider = Provider<String? Function()>(
  (_) =>
      () => AppConfig.hasSupabase
      ? Supabase.instance.client.auth.currentUser?.id
      : null,
);

@immutable
class AppLockState {
  const AppLockState({this.enabled = false, this.locked = false});
  final bool enabled, locked;
}

final appLockProvider = NotifierProvider<AppLockController, AppLockState>(
  AppLockController.new,
);

/// Locks the app behind fingerprint/face on start and after it has been in
/// the background for longer than [relockAfter].
class AppLockController extends Notifier<AppLockState> {
  static const relockAfter = Duration(minutes: 1);
  DateTime? _backgroundedAt;

  /// Injected clock for tests.
  DateTime Function() now = DateTime.now;

  BiometricAuthenticator get _auth => ref.read(biometricAuthenticatorProvider);
  LockPreferences get _prefs => ref.read(lockPreferencesProvider);
  String? get _userId => ref.read(currentUserIdProvider)();

  @override
  AppLockState build() => const AppLockState();

  /// On app start: lock if this user turned biometric unlock on.
  Future<void> initialize() async {
    final userId = _userId;
    final enabled = userId != null && await _prefs.isEnabled(userId);
    state = AppLockState(enabled: enabled, locked: enabled);
  }

  void onBackgrounded() => _backgroundedAt = now();

  void onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (!state.enabled || since == null || _userId == null) return;
    if (now().difference(since) >= relockAfter) {
      state = AppLockState(enabled: state.enabled, locked: true);
    }
  }

  /// Shows the biometric prompt; unlocks on success.
  Future<bool> unlock() async {
    final passed = await _auth.authenticate('Unlock Lending Manager');
    if (passed) state = AppLockState(enabled: state.enabled);
    return passed;
  }

  Future<bool> isAvailable() => _auth.isAvailable();

  /// Turning on requires one successful scan so the user knows it works.
  Future<bool> setEnabled(bool enabled) async {
    final userId = _userId;
    if (userId == null) return false;
    if (enabled) {
      if (!await _auth.isAvailable()) return false;
      if (!await _auth.authenticate('Confirm to turn on fingerprint unlock')) {
        return false;
      }
    }
    await _prefs.setEnabled(userId, enabled);
    await _prefs.markOffered(userId);
    state = AppLockState(enabled: enabled);
    return true;
  }

  /// Whether to ask "Unlock with fingerprint next time?" after sign-in.
  Future<bool> shouldOffer() async {
    final userId = _userId;
    if (userId == null) return false;
    if (await _prefs.isEnabled(userId) || await _prefs.wasOffered(userId)) {
      return false;
    }
    return _auth.isAvailable();
  }

  Future<void> declineOffer() async {
    final userId = _userId;
    if (userId != null) await _prefs.markOffered(userId);
  }

  /// Signed in again with a password: no lock needed right now.
  Future<void> onSignedIn() async {
    final userId = _userId;
    final enabled = userId != null && await _prefs.isEnabled(userId);
    state = AppLockState(enabled: enabled);
  }

  void onSignedOut() => state = const AppLockState();
}

/// After a password sign-in on a phone with biometrics, asks once whether to
/// unlock with fingerprint/face next time.
Future<void> offerBiometricUnlock(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final lock = container.read(appLockProvider.notifier);
  await lock.onSignedIn();
  if (!await lock.shouldOffer() || !context.mounted) return;
  final accept = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.fingerprint, size: 36),
      title: const Text('Unlock with fingerprint next time?'),
      content: const Text(
        'Instead of typing your password, use your fingerprint or face to '
        'open the app. You can change this in Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  if (accept == true) {
    await lock.setEnabled(true);
  } else {
    await lock.declineOffer();
  }
}

/// Covers the app with a lock screen while [AppLockState.locked], and tracks
/// background/foreground to re-lock.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    required this.onUsePassword,
  });
  final Widget child;

  /// Called after signing out from the lock screen (go to the login page).
  final VoidCallback onUsePassword;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(appLockProvider.notifier).initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final lock = ref.read(appLockProvider.notifier);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      lock.onBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      lock.onResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(appLockProvider.select((s) => s.locked));
    return Stack(
      children: [
        // Keep the app mounted underneath but unreachable while locked.
        ExcludeSemantics(excluding: locked, child: widget.child),
        if (locked) _LockScreen(onUsePassword: widget.onUsePassword),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.onUsePassword});
  final VoidCallback onUsePassword;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool busy = false, failed = false;

  @override
  void initState() {
    super.initState();
    // Prompt right away, like most banking apps.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (busy) return;
    setState(() => busy = true);
    final ok = await ref.read(appLockProvider.notifier).unlock();
    if (mounted && !ok) setState(() => failed = true);
    if (mounted) setState(() => busy = false);
  }

  Future<void> _usePassword() async {
    if (AppConfig.hasSupabase) {
      await Supabase.instance.client.auth.signOut();
    }
    ref.read(appLockProvider.notifier).onSignedOut();
    widget.onUsePassword();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned.fill(
      child: Material(
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text('Locked', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(
                    failed
                        ? 'Not recognized. Try again, or sign in with your password.'
                        : 'Use your fingerprint or face to continue.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: busy ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : _usePassword,
                    child: const Text('Use password instead'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
