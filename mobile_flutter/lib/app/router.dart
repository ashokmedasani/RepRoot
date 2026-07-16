import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/client_login_page.dart';
import '../features/auth/role_chooser_page.dart';
import '../features/auth/trainer_login_page.dart';
import '../features/auth/trainer_profile_setup_page.dart';
import '../features/auth/trainer_signup_page.dart';
import '../features/client/client_tabs_shell.dart';
import '../features/placeholder_page.dart';
import '../features/trainer/trainer_clients_page.dart';
import '../features/trainer/trainer_dashboard_page.dart';
import '../features/trainer/trainer_manage_page.dart';
import '../features/trainer/trainer_more_page.dart';
import '../features/trainer/trainer_schedule_page.dart';
import '../features/trainer/trainer_settings_page.dart';
import '../features/trainer/trainer_tabs_shell.dart';

/// Route paths mirror mobile/src/app/app.routes.ts exactly so the two apps
/// navigate identically and deep links stay portable.
class Routes {
  const Routes._();

  static const roleChooser = '/';
  static const trainerLogin = '/trainer/login';
  static const trainerSignup = '/trainer/signup';
  static const trainerProfileSetup = '/trainer/profile-setup';
  static const trainerDashboard = '/trainer/tabs/dashboard';
  static const trainerClients = '/trainer/tabs/clients';
  static const trainerManage = '/trainer/tabs/manage';
  static const trainerMore = '/trainer/tabs/more';

  static const trainerClientCreate = '/trainer/tabs/clients/new';

  // Sub-pages that stack inside the Manage / More tabs.
  static const trainerGroups = '/trainer/tabs/manage/groups';
  static const trainerFormsGroups = '/trainer/tabs/manage/forms-groups';
  static const trainerTemplates = '/trainer/tabs/manage/templates';
  static const trainerReferences = '/trainer/tabs/manage/references';
  static const trainerSchedule = '/trainer/tabs/manage/schedule';
  static const trainerProfile = '/trainer/tabs/more/profile';
  static const trainerSettings = '/trainer/tabs/more/settings';
  static const trainerSupport = '/trainer/tabs/more/support';

  static const clientLogin = '/client/login';
  static const clientDashboard = '/client/tabs/dashboard';
  static const clientPrograms = '/client/tabs/programs';
  static const clientProgress = '/client/tabs/progress';
  static const clientMore = '/client/tabs/more';
}

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.roleChooser,
    routes: [
      GoRoute(
        path: Routes.roleChooser,
        builder: (context, state) => const RoleChooserPage(),
      ),
      GoRoute(
        path: Routes.trainerLogin,
        builder: (context, state) => const TrainerLoginPage(),
      ),
      GoRoute(
        path: Routes.trainerSignup,
        builder: (context, state) => const TrainerSignupPage(),
      ),
      GoRoute(
        path: Routes.trainerProfileSetup,
        builder: (context, state) => const TrainerProfileSetupPage(),
      ),
      GoRoute(
        path: Routes.clientLogin,
        builder: (context, state) => const ClientLoginPage(),
      ),

      // Trainer tab shell: Dashboard | Clients | Manage | More
      // (Shop deferred by design, as in the Ionic app.)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            TrainerTabsShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.trainerDashboard,
                builder: (context, state) => const TrainerDashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.trainerClients,
                builder: (context, state) => const TrainerClientsPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'New client',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: ':clientId',
                    builder: (context, state) => PlaceholderPage(
                      title: 'Client ${state.pathParameters['clientId']}',
                      phase: 'Phase 4',
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.trainerManage,
                builder: (context, state) => const TrainerManagePage(),
                routes: [
                  GoRoute(
                    path: 'forms-groups',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'Forms & Groups',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: 'groups/:groupId',
                    builder: (context, state) => PlaceholderPage(
                      title: 'Group ${state.pathParameters['groupId']}',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: 'templates',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'Templates',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: 'references',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'References',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: 'schedule',
                    builder: (context, state) => const TrainerSchedulePage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.trainerMore,
                builder: (context, state) => const TrainerMorePage(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'Trainer Profile',
                      phase: 'Phase 4',
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) => const TrainerSettingsPage(),
                  ),
                  GoRoute(
                    path: 'support',
                    builder: (context, state) => const PlaceholderPage(
                      title: 'Help & Support',
                      phase: 'Phase 6',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Client tab shell: Dashboard | Programs | Progress | More
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ClientTabsShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientDashboard,
                builder: (context, state) => const PlaceholderPage(
                  title: 'Dashboard',
                  phase: 'Phase 5',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientPrograms,
                builder: (context, state) => const PlaceholderPage(
                  title: 'Programs',
                  phase: 'Phase 5',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientProgress,
                builder: (context, state) => const PlaceholderPage(
                  title: 'Progress',
                  phase: 'Phase 5',
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientMore,
                builder: (context, state) => const PlaceholderPage(
                  title: 'More',
                  phase: 'Phase 5',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const RoleChooserPage(),
  );
});
