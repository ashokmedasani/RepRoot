import { Routes } from '@angular/router';

/**
 * Android navigation map (reference design):
 * - Role chooser -> trainer or client login -> role tab shell.
 * - Trainer shell (5-tab design, Shop deferred): Dashboard, Clients, Manage, More.
 * - Client shell: Dashboard, Programs, Progress, More.
 */
export const routes: Routes = [
  {
    path: '',
    pathMatch: 'full',
    loadComponent: () => import('./pages/role-chooser/role-chooser.page').then((m) => m.RoleChooserPage)
  },
  {
    path: 'trainer/login',
    loadComponent: () => import('./pages/trainer/login/trainer-login.page').then((m) => m.TrainerLoginPage)
  },
  {
    path: 'trainer/tabs',
    loadComponent: () => import('./pages/trainer/tabs/trainer-tabs.page').then((m) => m.TrainerTabsPage),
    children: [
      {
        path: 'dashboard',
        loadComponent: () => import('./pages/trainer/dashboard/trainer-dashboard.page').then((m) => m.TrainerDashboardPage)
      },
      {
        path: 'clients',
        loadComponent: () => import('./pages/trainer/clients/trainer-clients.page').then((m) => m.TrainerClientsPage)
      },
      {
        path: 'clients/new',
        loadComponent: () => import('./pages/trainer/client-create/client-create.page').then((m) => m.ClientCreatePage)
      },
      {
        path: 'clients/:clientId',
        loadComponent: () => import('./pages/trainer/client-detail/client-detail.page').then((m) => m.ClientDetailPage)
      },
      {
        path: 'clients/:clientId/templates/:assignmentId',
        loadComponent: () => import('./pages/trainer/client-template/client-template.page').then((m) => m.ClientTemplatePage)
      },
      {
        path: 'manage',
        loadComponent: () => import('./pages/trainer/manage/trainer-manage.page').then((m) => m.TrainerManagePage)
      },
      {
        path: 'manage/forms-groups',
        loadComponent: () => import('./pages/trainer/forms-groups/trainer-forms-groups.page').then((m) => m.TrainerFormsGroupsPage)
      },
      {
        path: 'manage/groups/:groupId',
        loadComponent: () => import('./pages/trainer/group-detail/group-detail.page').then((m) => m.GroupDetailPage)
      },
      {
        path: 'manage/templates',
        loadComponent: () => import('./pages/trainer/templates/trainer-templates.page').then((m) => m.TrainerTemplatesPage)
      },
      {
        path: 'manage/references',
        loadComponent: () => import('./pages/trainer/references/trainer-references.page').then((m) => m.TrainerReferencesPage)
      },
      {
        path: 'manage/schedule',
        loadComponent: () => import('./pages/trainer/schedule/trainer-schedule.page').then((m) => m.TrainerSchedulePage)
      },
      {
        path: 'more',
        loadComponent: () => import('./pages/trainer/more/trainer-more.page').then((m) => m.TrainerMorePage)
      },
      {
        path: 'more/profile',
        loadComponent: () => import('./pages/trainer/profile/trainer-profile.page').then((m) => m.TrainerProfilePage)
      },
      {
        path: 'more/settings',
        loadComponent: () => import('./pages/trainer/settings/trainer-settings.page').then((m) => m.TrainerSettingsPage)
      },
      {
        path: 'more/support',
        loadComponent: () => import('./pages/shared/support-incidents.page').then((m) => m.SupportIncidentsPage),
        data: { role: 'trainer' }
      },
      // Back-compat redirects for pre-redesign links.
      { path: 'forms-groups', redirectTo: 'manage/forms-groups' },
      { path: 'templates', redirectTo: 'manage/templates' },
      { path: 'more/references', redirectTo: 'manage/references' },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
    ]
  },
  {
    path: 'client/login',
    loadComponent: () => import('./pages/client/login/client-login.page').then((m) => m.ClientLoginPage)
  },
  {
    path: 'client/tabs',
    loadComponent: () => import('./pages/client/tabs/client-tabs.page').then((m) => m.ClientTabsPage),
    children: [
      {
        path: 'dashboard',
        loadComponent: () => import('./pages/client/dashboard/client-dashboard.page').then((m) => m.ClientDashboardPage)
      },
      {
        path: 'programs',
        loadComponent: () => import('./pages/client/programs/client-programs.page').then((m) => m.ClientProgramsPage)
      },
      {
        path: 'progress',
        loadComponent: () => import('./pages/client/progress/client-progress.page').then((m) => m.ClientProgressPage)
      },
      {
        path: 'more',
        loadComponent: () => import('./pages/client/more/client-more.page').then((m) => m.ClientMorePage)
      },
      {
        path: 'more/profile',
        loadComponent: () => import('./pages/client/settings/client-settings.page').then((m) => m.ClientSettingsPage)
      },
      {
        path: 'more/trainer',
        loadComponent: () => import('./pages/client/trainer/client-trainer.page').then((m) => m.ClientTrainerPage)
      },
      {
        path: 'more/chat',
        loadComponent: () => import('./pages/client/chat/client-chat.page').then((m) => m.ClientChatPage)
      },
      {
        path: 'more/support',
        loadComponent: () => import('./pages/shared/support-incidents.page').then((m) => m.SupportIncidentsPage),
        data: { role: 'client' }
      },
      // Back-compat redirects for pre-redesign links.
      { path: 'templates', redirectTo: 'programs' },
      { path: 'trainer', redirectTo: 'more/trainer' },
      { path: 'chat', redirectTo: 'more/chat' },
      { path: 'settings', redirectTo: 'more/profile' },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
    ]
  },
  { path: '**', redirectTo: '' }
];
