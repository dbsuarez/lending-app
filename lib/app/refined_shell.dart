import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/dashboard/live_dashboard_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/config/app_config.dart';
import '../features/settings/business_profile_provider.dart';
import 'theme/app_theme.dart';

const _nav = [
  ('Dashboard', Icons.home_outlined, '/dashboard'),
  ('Borrowers', Icons.people_outline, '/borrowers'),
  ('Loans', Icons.handshake_outlined, '/loans'),
  ('Personal Loans', Icons.person_outline, '/personal-loans'),
  ('Collections', Icons.event_available_outlined, '/collections'),
  ('Payments', Icons.credit_card_outlined, '/payments'),
  ('Reports', Icons.bar_chart_outlined, '/reports'),
  ('Documents', Icons.description_outlined, '/documents'),
  ('Settings', Icons.settings_outlined, '/settings'),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool collapsed = false;

  int get selected {
    final index = _nav.indexWhere(
      (item) => widget.location.startsWith(item.$3),
    );
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 1024) return _mobile(context);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(width: collapsed ? 76 : 232, child: _sidebar(context)),
          Expanded(
            child: Column(
              children: [
                _topBar(context),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    final mobileNav = [_nav[0], _nav[1], _nav[2], _nav[4]];
    final mobileSelected = mobileNav.indexWhere(
      (item) => widget.location.startsWith(item.$3),
    );
    return Scaffold(
      appBar: AppBar(
        title: _Brand(
          dark: Theme.of(context).brightness == Brightness.dark,
          name: _businessName,
        ),
        actions: [
          if (selected == 0)
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: () => ref.invalidate(liveDashboardProvider),
              icon: const Icon(Icons.refresh),
            ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: SafeArea(child: widget.child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: mobileSelected < 0 ? 4 : mobileSelected,
        onDestinationSelected: (index) {
          if (index == 4) {
            _openMore(context);
          } else {
            context.go(mobileNav[index].$3);
          }
        },
        destinations: [
          for (final item in mobileNav)
            NavigationDestination(icon: Icon(item.$2), label: item.$1),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }

  void _openMore(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'More',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final item in _nav.where(
                (item) => !const {
                  '/dashboard',
                  '/borrowers',
                  '/loans',
                  '/collections',
                }.contains(item.$3),
              ))
                ListTile(
                  selected: widget.location.startsWith(item.$3),
                  selectedTileColor: Theme.of(
                    context,
                  ).colorScheme.secondaryContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(item.$2),
                  title: Text(item.$1),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.go(item.$3);
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'v1.0.0 · build ${AppConfig.buildId}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                    AppColors.navy900,
                    Theme.of(context).colorScheme.primary,
                    .18,
                  ) ??
                  AppColors.navy900,
              Color.lerp(
                    AppColors.navy800,
                    Theme.of(context).colorScheme.primary,
                    .34,
                  ) ??
                  AppColors.navy800,
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 65,
        height: 155,
        child: CustomPaint(
          painter: _WavePainter(Theme.of(context).colorScheme.primary),
        ),
      ),
      SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(22, 22, 22, 17),
              child: collapsed
                  ? IconButton(
                      tooltip: 'Expand navigation',
                      onPressed: () => setState(() => collapsed = false),
                      icon: const Icon(
                        Icons.chevron_right,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _Brand(dark: true, name: _businessName),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Collapse navigation',
                          onPressed: () => setState(() => collapsed = true),
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
            for (var i = 0; i < _nav.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                child: SizedBox(
                  height: 43,
                  child: Tooltip(
                    message: collapsed ? _nav[i].$1 : '',
                    child: collapsed
                        ? Material(
                            color: i == selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => context.go(_nav[i].$3),
                              child: Center(
                                child: Icon(
                                  _nav[i].$2,
                                  color: Colors.white,
                                  size: 21,
                                ),
                              ),
                            ),
                          )
                        : ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            selected: i == selected,
                            selectedTileColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Icon(
                              _nav[i].$2,
                              color: Colors.white,
                              size: 21,
                            ),
                            title: Text(
                              _nav[i].$1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => context.go(_nav[i].$3),
                          ),
                  ),
                ),
              ),
            const Spacer(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: EdgeInsets.all(collapsed ? 9 : 11),
              decoration: BoxDecoration(
                color: const Color(0x221463F3),
                border: Border.all(color: const Color(0x553D74D8)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Color(0xFF43E68B),
                    size: 27,
                  ),
                  if (!collapsed) const SizedBox(width: 9),
                  if (!collapsed)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppConfig.hasSupabase
                                ? 'Cloud connected'
                                : 'Local demo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            AppConfig.hasSupabase
                                ? 'Synchronized'
                                : 'Not synchronized',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  children: [
                    const Text(
                      'v1.0.0',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                    Text(
                      'build ${AppConfig.buildId}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _topBar(BuildContext context) => Container(
    height: 68,
    color: Theme.of(context).colorScheme.surface,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SearchBar(
                elevation: const WidgetStatePropertyAll(0),
                backgroundColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                hintText: 'Search borrower, loan, payment, or reference...',
                leading: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        IconButton(
          onPressed: () {},
          icon: const Icon(Icons.notifications_none),
        ),
        CircleAvatar(
          radius: 18,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            _userInitials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _userLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              _roleLabel,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  User? get _currentUser =>
      AppConfig.hasSupabase ? Supabase.instance.client.auth.currentUser : null;

  String get _businessName =>
      ref.watch(businessProfileProvider).value?.name ??
      BusinessProfile.fallback.name;

  String get _roleLabel {
    final role = ref.watch(businessProfileProvider).value?.role ?? 'viewer';
    return '${role[0].toUpperCase()}${role.substring(1)}';
  }

  String get _userLabel {
    final user = _currentUser;
    final displayName = user?.userMetadata?['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return user?.email ?? 'Local demo';
  }

  String get _userInitials {
    final parts = _userLabel
        .split(RegExp(r'[^A-Za-z0-9]+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'LD';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.dark, required this.name});
  final bool dark;
  final String name;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 38,
        height: 38,
        child: CustomPaint(painter: _CoinPainter()),
      ),
      const SizedBox(width: 9),
      SizedBox(
        width: 125,
        child: Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: dark ? Colors.white : AppColors.navy900,
            fontSize: 18,
            height: 1.02,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
  );
}

class _CoinPainter extends CustomPainter {
  const _CoinPainter();
  @override
  void paint(Canvas c, Size s) {
    for (var i = 0; i < 3; i++) {
      final y = 27.0 - i * 8;
      c.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(3, y, 27, 7),
          const Radius.circular(4),
        ),
        Paint()..color = const Color(0xFFFFC400),
      );
      c.drawOval(
        Rect.fromLTWH(3, y - 2, 27, 5),
        Paint()..color = const Color(0xFFFFDA45),
      );
    }
    c.drawCircle(
      const Offset(30, 8),
      6,
      Paint()..color = const Color(0xFFFFC400),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.accent);
  final Color accent;
  @override
  void paint(Canvas c, Size s) {
    final a = Path()
      ..moveTo(0, s.height * .56)
      ..cubicTo(
        s.width * .28,
        s.height * .28,
        s.width * .50,
        s.height * .92,
        s.width,
        s.height * .14,
      )
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(a, Paint()..color = accent.withValues(alpha: .22));
    final b = Path()
      ..moveTo(0, s.height * .75)
      ..cubicTo(
        s.width * .32,
        s.height * .98,
        s.width * .63,
        s.height * .22,
        s.width,
        s.height * .44,
      )
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    c.drawPath(b, Paint()..color = accent.withValues(alpha: .14));
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      accent != oldDelegate.accent;
}
