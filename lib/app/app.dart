import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/app_config.dart';
import '../features/auth/login_screen.dart';
import '../features/borrowers/borrowers_screen.dart';
import '../features/borrowers/borrower_detail_screen.dart';
import '../features/dashboard/live_dashboard_screen.dart';
import '../features/loans/loan_form_screen.dart';
import '../features/loans/loan_detail_screen.dart';
import '../features/loans/shared_loan_status_screen.dart';
import '../features/loans/loans_screen.dart';
import '../features/payments/payments_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/documents/documents_screen.dart';
import '../features/collections/collections_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/audit_events_screen.dart';
import 'refined_shell.dart';
import '../core/undo/undo_controller.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';
import '../core/theme/palette_provider.dart';
import '../features/settings/business_profile_provider.dart';

final _router = GoRouter(
  initialLocation:
      AppConfig.hasSupabase &&
          Supabase.instance.client.auth.currentSession != null
      ? '/dashboard'
      : '/login',
  redirect: (context, state) {
    final signedIn =
        AppConfig.hasSupabase &&
        Supabase.instance.client.auth.currentSession != null;
    if (signedIn && state.uri.path == '/login') return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(
      path: '/s/:token',
      builder: (c, s) =>
          SharedLoanStatusScreen(token: s.pathParameters['token']!),
    ),
    ShellRoute(
      builder: (c, s, child) => AppShell(location: s.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (c, s) => const LiveDashboardScreen(),
        ),
        GoRoute(path: '/borrowers', builder: (c, s) => const BorrowersScreen()),
        GoRoute(
          path: '/borrowers/:borrowerId',
          builder: (c, s) =>
              BorrowerDetailScreen(borrowerId: s.pathParameters['borrowerId']!),
        ),
        GoRoute(path: '/loans/new', builder: (c, s) => const LoanFormScreen()),
        GoRoute(
          path: '/loans/:loanId',
          builder: (c, s) => LoanDetailScreen(
            loanId: s.pathParameters['loanId']!,
            origin: s.uri.queryParameters['from'],
            borrowerId: s.uri.queryParameters['borrowerId'],
          ),
        ),
        GoRoute(path: '/loans', builder: (c, s) => const LoansScreen()),
        GoRoute(
          path: '/personal-loans',
          builder: (c, s) => const LoansScreen(personalOnly: true),
        ),
        GoRoute(
          path: '/collections',
          builder: (c, s) => const CollectionsScreen(),
        ),
        GoRoute(path: '/payments', builder: (c, s) => const PaymentsScreen()),
        GoRoute(path: '/reports', builder: (c, s) => const ReportsScreen()),
        GoRoute(path: '/documents', builder: (c, s) => const DocumentsScreen()),
        GoRoute(
          path: '/settings/audit',
          builder: (c, s) => const AuditEventsScreen(),
        ),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      ],
    ),
  ],
);

class LendingManagerApp extends ConsumerWidget {
  const LendingManagerApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);
    final businessName =
        ref.watch(businessProfileProvider).value?.name ?? 'Lending Manager';
    return MaterialApp.router(
      title: businessName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFor(palette.seed),
      darkTheme: AppTheme.darkFor(palette.seed),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: _router,
      // App-wide so transaction/undo messages persist across navigation.
      scaffoldMessengerKey: rootScaffoldMessengerKey,
    );
  }
}
