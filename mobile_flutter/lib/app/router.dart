import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/client_api.dart';
import '../core/session/session_store.dart';
import '../features/auth/client_login_page.dart';
import '../features/auth/role_chooser_page.dart';
import '../features/auth/professional_forgot_password_page.dart';
import '../features/auth/professional_legal_consent_page.dart';
import '../features/auth/professional_login_page.dart';
import '../features/auth/professional_profile_setup_page.dart';
import '../features/auth/professional_signup_page.dart';
import '../features/client/client_change_password_page.dart';
import '../features/client/client_dashboard_page.dart';
import '../features/client/client_legal_consent_page.dart';
import '../features/client/client_more_page.dart';
import '../features/client/client_meetings_page.dart';
import '../features/client/client_payments_page.dart';
import '../features/client/client_programs_page.dart';
import '../features/client/client_settings_page.dart';
import '../features/client/client_tabs_shell.dart';
import '../features/client/client_template_resources_page.dart';
import '../features/client/client_professional_page.dart';
import '../features/support/support_incidents_page.dart';
import '../features/shared/notification_preferences_page.dart';
import '../features/shared/notifications_page.dart';
import '../features/professional/professional_client_create_page.dart';
import '../features/professional/professional_client_detail_page.dart';
import '../features/professional/professional_client_chat_page.dart';
import '../features/professional/professional_client_payments_page.dart';
import '../features/professional/professional_client_template_page.dart';
import '../features/professional/professional_clients_page.dart';
import '../features/professional/professional_dashboard_page.dart';
import '../features/professional/professional_forms_groups_page.dart';
import '../features/professional/professional_group_detail_page.dart';
import '../features/professional/professional_manage_page.dart';
import '../features/professional/professional_more_page.dart';
import '../features/professional/professional_payments_page.dart';
import '../features/professional/professional_profile_page.dart';
import '../features/professional/professional_resources_page.dart';
import '../features/professional/professional_schedule_page.dart';
import '../features/professional/professional_settings_billing_page.dart';
import '../features/professional/professional_settings_legal_acceptance_page.dart';
import '../features/professional/professional_settings_page.dart';
import '../features/professional/professional_settings_payment_page.dart';
import '../features/professional/professional_settings_plan_storage_page.dart';
import '../features/professional/professional_settings_recycle_bin_page.dart';
import '../features/professional/professional_settings_security_page.dart';
import '../features/professional/professional_support_legal_page.dart';
import '../features/professional/professional_tabs_shell.dart';
import '../features/professional/professional_templates_page.dart';

/// Route paths mirror mobile/src/app/app.routes.ts exactly so the two apps
/// navigate identically and deep links stay portable.
class Routes {
  const Routes._();

  static const roleChooser = '/';
  static const professionalLogin = '/professional/login';
  static const professionalSignup = '/professional/signup';
  static const professionalForgotPassword = '/professional/forgot-password';
  static const professionalLegalConsent = '/professional/legal-consent';
  static const professionalProfileSetup = '/professional/profile-setup';
  static const professionalDashboard = '/professional/tabs/dashboard';
  static const professionalClients = '/professional/tabs/clients';
  static const professionalManage = '/professional/tabs/manage';
  // Promoted to its own top-level tab (was nested under Manage) so the
  // bottom nav can show Dashboard | Manage | Clients | Schedule | More,
  // matching the 5-tab reference design.
  static const professionalSchedule = '/professional/tabs/schedule';
  static const professionalMore = '/professional/tabs/more';

  static const professionalClientCreate = '/professional/tabs/clients/new';

  // Sub-pages that stack inside the Manage / More tabs.
  static const professionalGroups = '/professional/tabs/manage/groups';
  static const professionalFormsGroups =
      '/professional/tabs/manage/forms-groups';
  static const professionalTemplates = '/professional/tabs/manage/templates';
  static const professionalResources = '/professional/tabs/manage/resource';
  static const professionalPayments = '/professional/tabs/manage/payments';
  static const professionalProfile = '/professional/tabs/more/profile';
  static const professionalSettings = '/professional/tabs/more/settings';
  static const professionalSettingsPlanStorage =
      '$professionalSettings/plan-storage';
  static const professionalSettingsBilling = '$professionalSettings/billing';
  static const professionalSettingsSecurity = '$professionalSettings/security';
  static const professionalSettingsRecycleBin =
      '$professionalSettings/recycle-bin';
  static const professionalSettingsLegalAcceptance =
      '$professionalSettings/legal-acceptance';
  static const professionalSettingsPayment = '$professionalSettings/payment';
  static const professionalSupport = '/professional/tabs/more/support';
  static const professionalSupportLegal = '$professionalMore/support-legal';
  static const professionalNotifications =
      '/professional/tabs/more/notifications';

  static const clientLogin = '/client/login';
  static const clientChangePassword = '/client/change-password';
  static const clientLegalConsent = '/client/legal-consent';
  static const clientDashboard = '/client/tabs/dashboard';
  static const clientPrograms = '/client/tabs/programs';
  static const clientProfessional = '/client/tabs/professional';
  static const clientMore = '/client/tabs/more';

  // Sub-pages that stack inside the client More tab.
  static const clientSettings = '/client/tabs/more/profile';
  static const clientSupport = '/client/tabs/more/support';
  static const clientNotifications = '/client/tabs/more/notifications';
  static const clientMeetings = '/client/tabs/more/meetings';
  static const clientPayments = '/client/tabs/more/payments';
}

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(sessionStoreProvider);
  return GoRouter(
    initialLocation: Routes.roleChooser,
    refreshListenable: session,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final clientPublic =
          location == Routes.clientLogin || location == Routes.roleChooser;
      if (location.startsWith('/client/') && !clientPublic) {
        if (!session.hasClientSession) {
          return Routes.clientLogin;
        }

        // Consent gate — the mobile copy of clientAuthGuard in
        // frontend/src/app/core/guards/portal-auth.guards.ts. It reads the
        // cached access record exactly as the web guard reads sessionStorage
        // 'client-access'; ClientAccessSerializer already folds "accepted an
        // older version" into these two flags, so no request is needed here.
        // The forced password change keeps priority, as on the web, and an
        // unreadable cached record counts as "not accepted" (fail closed).
        final client = ref.read(clientApiProvider).storedClient();
        final legalAccepted = client?.legalAccepted ?? false;
        final mustChangePassword = client?.mustChangePassword ?? false;
        // pendingLegalConsent covers the mid-session case: the backend's
        // legal version was bumped while this session was live, a request
        // 403'd, and the dio interceptor flagged it (see api_client.dart).
        if (!mustChangePassword &&
            (!legalAccepted || session.pendingLegalConsent == 'client') &&
            location != Routes.clientLegalConsent &&
            location != Routes.clientChangePassword) {
          return Routes.clientLegalConsent;
        }
      }

      // No consent branch for professionals here, and none on the web either:
      // professionalAuthGuard only checks the token. Whether a professional
      // owes consent lives behind GET /professional/profile/status/, so it is
      // checked where an await is possible — at login and on session restore
      // (professional_login_page.dart / role_chooser_page.dart), which is the
      // same pair of moments the web checks it.
      final professionalPublic =
          location == Routes.professionalLogin ||
          location == Routes.professionalSignup ||
          location == Routes.professionalForgotPassword ||
          location == Routes.roleChooser;
      if (location.startsWith('/professional/') &&
          !professionalPublic &&
          !session.hasProfessionalSession) {
        return Routes.professionalLogin;
      }
      // Mid-session re-consent (flag set by the dio interceptor on the
      // legal-403) — the mobile copy of the web error.interceptor.ts
      // redirect. Login/restore-time consent stays where it is (see the
      // comment above); this only catches a version bump mid-session.
      if (session.pendingLegalConsent == 'professional' &&
          location.startsWith('/professional/') &&
          !professionalPublic &&
          location != Routes.professionalLegalConsent &&
          session.hasProfessionalSession) {
        return Routes.professionalLegalConsent;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.roleChooser,
        builder: (context, state) => const RoleChooserPage(),
      ),
      GoRoute(
        path: Routes.professionalLogin,
        builder: (context, state) => const ProfessionalLoginPage(),
      ),
      GoRoute(
        path: Routes.professionalSignup,
        builder: (context, state) => const ProfessionalSignupPage(),
      ),
      GoRoute(
        path: Routes.professionalForgotPassword,
        builder: (context, state) => const ProfessionalForgotPasswordPage(),
      ),
      // Not in professionalPublic on purpose: re-consent needs the signed-in
      // professional, and the login flow only routes here once a token exists.
      GoRoute(
        path: Routes.professionalLegalConsent,
        builder: (context, state) => const ProfessionalLegalConsentPage(),
      ),
      GoRoute(
        path: Routes.professionalProfileSetup,
        builder: (context, state) => const ProfessionalProfileSetupPage(),
      ),
      GoRoute(
        path: Routes.clientLogin,
        builder: (context, state) => const ClientLoginPage(),
      ),
      GoRoute(
        path: Routes.clientChangePassword,
        builder: (context, state) => const ClientChangePasswordPage(),
      ),
      GoRoute(
        path: Routes.clientLegalConsent,
        builder: (context, state) => const ClientLegalConsentPage(),
      ),

      // Professional tab shell: Dashboard | Manage | Clients | Schedule | More
      // (Shop deferred by design, as in the Ionic app.)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ProfessionalTabsShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.professionalDashboard,
                builder: (context, state) => const ProfessionalDashboardPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.professionalManage,
                builder: (context, state) => const ProfessionalManagePage(),
                routes: [
                  GoRoute(
                    path: 'forms-groups',
                    builder: (context, state) => ProfessionalFormsGroupsPage(
                      initialTab: state.uri.queryParameters['tab'],
                    ),
                  ),
                  GoRoute(
                    path: 'groups/:groupId',
                    builder: (context, state) => ProfessionalGroupDetailPage(
                      groupId:
                          int.tryParse(state.pathParameters['groupId'] ?? '') ??
                          0,
                    ),
                  ),
                  GoRoute(
                    path: 'templates',
                    builder: (context, state) =>
                        const ProfessionalTemplatesPage(),
                  ),
                  GoRoute(
                    path: 'resource',
                    builder: (context, state) =>
                        const ProfessionalResourcesPage(),
                  ),
                  GoRoute(
                    path: 'payments',
                    builder: (context, state) =>
                        const ProfessionalPaymentsPage(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.professionalClients,
                builder: (context, state) => const ProfessionalClientsPage(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (context, state) =>
                        const ProfessionalClientCreatePage(),
                  ),
                  GoRoute(
                    path: ':clientId',
                    builder: (context, state) => ProfessionalClientDetailPage(
                      clientId:
                          int.tryParse(
                            state.pathParameters['clientId'] ?? '',
                          ) ??
                          0,
                    ),
                    routes: [
                      GoRoute(
                        path: 'templates/:assignmentId',
                        builder: (context, state) =>
                            ProfessionalClientTemplatePage(
                              clientId:
                                  int.tryParse(
                                    state.pathParameters['clientId'] ?? '',
                                  ) ??
                                  0,
                              assignmentId:
                                  int.tryParse(
                                    state.pathParameters['assignmentId'] ?? '',
                                  ) ??
                                  0,
                            ),
                      ),
                      // Chat is a destination, not a facet of the client
                      // record: it needs the whole viewport, and the keyboard
                      // takes half of what's left. As a tab it was competing
                      // with a header and two tab bars for the same pixels.
                      GoRoute(
                        path: 'chat',
                        builder: (context, state) => ProfessionalClientChatPage(
                          clientId:
                              int.tryParse(
                                state.pathParameters['clientId'] ?? '',
                              ) ??
                              0,
                          clientName: state.uri.queryParameters['name'] ?? '',
                        ),
                      ),
                      GoRoute(
                        path: 'payments',
                        builder: (context, state) =>
                            ProfessionalClientPaymentsPage(
                              clientId:
                                  int.tryParse(
                                    state.pathParameters['clientId'] ?? '',
                                  ) ??
                                  0,
                              clientName:
                                  state.uri.queryParameters['name'] ?? 'Client',
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
                path: Routes.professionalSchedule,
                builder: (context, state) => const ProfessionalSchedulePage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.professionalMore,
                builder: (context, state) => const ProfessionalMorePage(),
                routes: [
                  GoRoute(
                    path: 'profile',
                    builder: (context, state) =>
                        const ProfessionalProfilePage(),
                  ),
                  GoRoute(
                    path: 'settings',
                    builder: (context, state) =>
                        const ProfessionalSettingsPage(),
                    routes: [
                      GoRoute(
                        path: 'plan-storage',
                        builder: (context, state) =>
                            const ProfessionalSettingsPlanStoragePage(),
                      ),
                      GoRoute(
                        path: 'billing',
                        builder: (context, state) =>
                            const ProfessionalSettingsBillingPage(),
                      ),
                      GoRoute(
                        path: 'security',
                        builder: (context, state) =>
                            const ProfessionalSettingsSecurityPage(),
                      ),
                      GoRoute(
                        path: 'recycle-bin',
                        builder: (context, state) =>
                            const ProfessionalSettingsRecycleBinPage(),
                      ),
                      GoRoute(
                        path: 'legal-acceptance',
                        builder: (context, state) =>
                            const ProfessionalSettingsLegalAcceptancePage(),
                      ),
                      GoRoute(
                        path: 'payment',
                        builder: (context, state) =>
                            const ProfessionalSettingsPaymentPage(),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'support',
                    builder: (context, state) => const SupportIncidentsPage(
                      role: SupportRole.professional,
                    ),
                  ),
                  GoRoute(
                    path: 'support-legal',
                    builder: (context, state) =>
                        const ProfessionalSupportLegalPage(),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) =>
                        const NotificationsPage(professional: true),
                    routes: [
                      GoRoute(
                        path: 'preferences',
                        builder: (context, state) =>
                            const NotificationPreferencesPage(
                              professional: true,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Client tab shell: Dashboard | Programs | Professional | More
      // Progress lives inside Programs (opens first there) rather than its
      // own bottom tab; the Dashboard keeps a short preview.
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
                routes: [
                  GoRoute(
                    path: ':templateId/resources',
                    builder: (context, state) => ClientTemplateResourcesPage(
                      templateId:
                          int.tryParse(
                            state.pathParameters['templateId'] ?? '',
                          ) ??
                          0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.clientProfessional,
                builder: (context, state) => const ClientProfessionalPage(),
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
                    path: 'support',
                    builder: (context, state) =>
                        const SupportIncidentsPage(role: SupportRole.client),
                  ),
                  GoRoute(
                    path: 'notifications',
                    builder: (context, state) =>
                        const NotificationsPage(professional: false),
                    routes: [
                      GoRoute(
                        path: 'preferences',
                        builder: (context, state) =>
                            const NotificationPreferencesPage(
                              professional: false,
                            ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'meetings',
                    builder: (context, state) => const ClientMeetingsPage(),
                  ),
                  GoRoute(
                    path: 'payments',
                    builder: (context, state) => const ClientPaymentsPage(),
                    routes: [
                      GoRoute(
                        path: ':requestId',
                        builder: (context, state) =>
                            ClientPaymentRequestDetailPage(
                              requestId:
                                  state.pathParameters['requestId'] ?? '',
                            ),
                      ),
                    ],
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
