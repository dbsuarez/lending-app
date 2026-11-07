import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lending_manager/core/security/app_lock.dart';

class _FakeAuth implements BiometricAuthenticator {
  bool available = true, pass = true;
  int prompts = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return pass;
  }
}

class _MemoryPrefs implements LockPreferences {
  final enabled = <String, bool>{}, offered = <String>{};
  @override
  Future<bool> isEnabled(String userId) async => enabled[userId] ?? false;
  @override
  Future<void> setEnabled(String userId, bool value) async =>
      enabled[userId] = value;
  @override
  Future<bool> wasOffered(String userId) async => offered.contains(userId);
  @override
  Future<void> markOffered(String userId) async => offered.add(userId);
}

({ProviderContainer container, _FakeAuth auth, _MemoryPrefs prefs}) _setup({
  String? userId = 'u1',
}) {
  final auth = _FakeAuth(), prefs = _MemoryPrefs();
  final container = ProviderContainer(
    overrides: [
      biometricAuthenticatorProvider.overrideWithValue(auth),
      lockPreferencesProvider.overrideWithValue(prefs),
      currentUserIdProvider.overrideWithValue(() => userId),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, auth: auth, prefs: prefs);
}

void main() {
  test('locks on start only when the user turned it on', () async {
    final t = _setup();
    final lock = t.container.read(appLockProvider.notifier);
    await lock.initialize();
    expect(t.container.read(appLockProvider).locked, isFalse);

    t.prefs.enabled['u1'] = true;
    await lock.initialize();
    expect(t.container.read(appLockProvider).locked, isTrue);
  });

  test('re-locks after a minute in the background, not before', () async {
    final t = _setup();
    t.prefs.enabled['u1'] = true;
    final lock = t.container.read(appLockProvider.notifier);
    await lock.initialize();
    await lock.unlock();
    var clock = DateTime(2026, 11, 7, 9);
    lock.now = () => clock;

    lock.onBackgrounded();
    clock = clock.add(const Duration(seconds: 30));
    lock.onResumed();
    expect(t.container.read(appLockProvider).locked, isFalse);

    lock.onBackgrounded();
    clock = clock.add(const Duration(minutes: 2));
    lock.onResumed();
    expect(t.container.read(appLockProvider).locked, isTrue);
  });

  test('a failed scan keeps it locked', () async {
    final t = _setup();
    t.prefs.enabled['u1'] = true;
    final lock = t.container.read(appLockProvider.notifier);
    await lock.initialize();
    t.auth.pass = false;
    expect(await lock.unlock(), isFalse);
    expect(t.container.read(appLockProvider).locked, isTrue);
    t.auth.pass = true;
    expect(await lock.unlock(), isTrue);
    expect(t.container.read(appLockProvider).locked, isFalse);
  });

  test('turning on needs a successful scan; nothing saved otherwise', () async {
    final t = _setup();
    final lock = t.container.read(appLockProvider.notifier);
    t.auth.pass = false;
    expect(await lock.setEnabled(true), isFalse);
    expect(t.prefs.enabled['u1'], isNull);
    t.auth.pass = true;
    expect(await lock.setEnabled(true), isTrue);
    expect(t.prefs.enabled['u1'], isTrue);
    expect(t.container.read(appLockProvider).enabled, isTrue);
  });

  test('offers once, only when available and signed in', () async {
    final t = _setup();
    final lock = t.container.read(appLockProvider.notifier);
    expect(await lock.shouldOffer(), isTrue);
    await lock.declineOffer();
    expect(await lock.shouldOffer(), isFalse);

    final noBio = _setup(userId: 'u2');
    noBio.auth.available = false;
    expect(
      await noBio.container.read(appLockProvider.notifier).shouldOffer(),
      isFalse,
    );

    final signedOut = _setup(userId: null);
    expect(
      await signedOut.container.read(appLockProvider.notifier).shouldOffer(),
      isFalse,
    );
  });

  testWidgets('lock screen covers the app and prompts immediately', (
    tester,
  ) async {
    final t = _setup();
    t.prefs.enabled['u1'] = true;
    t.auth.pass = false; // first automatic prompt fails
    var usedPassword = false;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: t.container,
        child: MaterialApp(
          builder: (context, child) => AppLockGate(
            onUsePassword: () => usedPassword = true,
            child: child!,
          ),
          home: const Scaffold(body: Text('Loans')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Locked'), findsOneWidget);
    expect(t.auth.prompts, 1);
    expect(find.textContaining('Not recognized'), findsOneWidget);

    t.auth.pass = true;
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Locked'), findsNothing);
    expect(find.text('Loans'), findsOneWidget);
    expect(usedPassword, isFalse);
  });
}
