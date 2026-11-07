import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import '../features/settings/business_profile_provider.dart';

const _destinations = [
  ('Dashboard', Icons.dashboard_outlined, '/dashboard'),
  ('Borrowers', Icons.people_outline, '/borrowers'),
  ('Loans', Icons.handshake_outlined, '/loans'),
  ('Collections', Icons.calendar_month_outlined, '/collections'),
  ('Payments', Icons.payments_outlined, '/payments'),
  ('Settings', Icons.settings_outlined, '/settings'),
];

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  int get selected {
    final index = _destinations.indexWhere((d) => location.startsWith(d.$3));
    return index < 0 ? 0 : index;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businessName =
        ref.watch(businessProfileProvider).value?.name ?? 'Lending Manager';
    final desktop = MediaQuery.sizeOf(context).width >= 1024;
    if (!desktop) {
      return Scaffold(
        appBar: AppBar(
          title: _Logo(dark: false, name: businessName),
          actions: [
            IconButton(
              tooltip: 'Notifications',
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
        body: SafeArea(child: child),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selected.clamp(0, 4),
          onDestinationSelected: (i) => context.go(_destinations[i].$3),
          destinations: [
            for (final d in _destinations.take(4))
              NavigationDestination(icon: Icon(d.$2), label: d.$1),
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              label: 'More',
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 232,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.navy900, AppColors.navy800],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: _Logo(dark: true, name: businessName),
                  ),
                  for (var i = 0; i < _destinations.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      child: ListTile(
                        selected: i == selected,
                        selectedTileColor: AppColors.blue600,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(_destinations[i].$2, color: Colors.white),
                        title: Text(
                          _destinations[i].$1,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => context.go(_destinations[i].$3),
                      ),
                    ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: ListTile(
                      leading: Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF46E98C),
                      ),
                      title: Text(
                        'Local demo',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        'Not synchronized',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 70,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: const SearchBar(
                            hintText:
                                'Search borrower, loan, payment, or reference…',
                            leading: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      const CircleAvatar(child: Text('O')),
                      const SizedBox(width: 8),
                      const Text(
                        'Owner',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.dark, required this.name});
  final bool dark;
  final String name;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.monetization_on, color: Color(0xFFFFC400), size: 34),
      const SizedBox(width: 8),
      Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: dark ? Colors.white : AppColors.navy900,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          height: 1.05,
        ),
      ),
    ],
  );
}
