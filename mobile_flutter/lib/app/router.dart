import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/client_login_page.dart';
import '../features/auth/role_chooser_page.dart';
import '../features/auth/trainer_login_page.dart';
import '../features/auth/trainer_profile_setup_page.dart';
import '../features/auth/trainer_signup_page.dart';
import '../features/client/client_change_password_page.dart';
import '../features/client/client_chat_page.dart';
import '../features/client/client_dashboard_page.dart';
import '../features/client/client_more_page.dart';
import '../features/client/client_programs_page.dart';
import '../features/client/client_progress_page.dart';
import '../features/client/client_settings_page.dart';
import '../features/client/client_tabs_shell.dart';
import '../features/client/client_trainer_page.dart';
import '../features/placeholder_page.dart';
import '../features/trainer/trainer_client_create_page.dart';
import '../features/trainer/trainer_client_detail_page.dart';
import '../features/trainer/trainer_client_template_page.dart';
import '../features/trainer/trainer_clients_page.dart';
import '../features/trainer/trainer_dashboard_page.dart';
import '../features/trainer/trainer_forms_groups_page.dart';
import '../features/trainer/trainer_group_detail_page.dart';
import '../features/trainer/trainer_manage_page.dart';
import '../features/trainer/trainer_more_page.dart';
import '../features/trainer/trainer_profile_page.dart';
import '../features/trainer/trainer_references_page.dart';
import '../features/trainer/trainer_schedule_page.dart';
import '../features/trainer/trainer_settings_page.dart';
import '../features/trainer/trainer_tabs_shell.dart';
import '../features/trainer/trainer_templates_page.dart';

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
  static const clientChangePassword = '/client/change-password';
  static const clientDashboard = '/client/tabs/dashboard';
  static const clientPrograms = '/client/tabs/programs';
  static const clientProgress = '/client/tabs/progress';
  static const clientMore = '/client/tabs/more';

  // Sub-pages that stack inside the client More tab.
  static const clientSettings = '/client/tabs/more/profile';
  static const clientTrainer = '/client/tabs/more/trainer';
  static const clientChat = '/client/tabs/more/chat';
  static const clientSupport = '/client/tabs/more/support';
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
      GoRoute(
        path: Routes.clientChangePassword,
        builder: (context, state) => const ClientChangePasswordPage(),
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
                    builder: (context, state) => const TrainerClientCreatePage(),
                  ),
                  GoRoute(
                    path: ':clientId',
                    builder: (context, state) => TrainerClientDetailPage(
                      clientId:
                          int.tryParse(state.pathParameters['clientId'] ?? '') ?? 0,
                    ),
                    routes: [
                      GoRoute(
                        path: 'templates/:assignmentId',
                        builder: (context, state) => TrainerClientTemplatePage(
                          clientId:
                              int.tryParse(state.pathParameters['clientId'] ?? '') ?? 0,
                          assignmentId: int.tryParse(
                                  state.pathParameters['assignmentId'] ?? '') ??
                              0,
                        ),
                      ),
                    ],
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
                    builder: (context, state) => TrainerFormsGroupsPage(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'groups/:groupId',
                    builder: (context, state) => TrainerGroupDetailPage(
                      groupId:
                          int.tryParse(state.pathParameters['groupId'] ?? '') ?? 0,
                    ),
                  ),
                  GoRoute(
                    path: 'templates',
                    builder: (context, state) => const TrainerTemplatesPage(),
                  ),
                  GoRoute(
                    path: 'references',
                    builder: (context, state) => const TrainerReferencesPage(),
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
                    builder: (context, state) => const TrainerProfilePage(),
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
                builder: (context, state) => const ClientDashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientPrograms,
                builder: (context, state) => const ClientProgramsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientProgress,
                builder: (context, state) => const ClientProgressPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientMore,
                builder: (context, state) => const ClientMorePage(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) => const ClientSettingsPage(),
                  ),
                  GoRoute(
                    path: 'trainer',
                    builder: (context, state) => const ClientTrainerPage(),
                  ),
                  GoRoute(
                    path: 'chat',
                    builder: (context, state) => const ClientChatPage(),
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
    ],
    errorBuilder: (context, state) => const RoleChooserPage(),
  );
});
