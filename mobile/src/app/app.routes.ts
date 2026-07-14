import { Routes } from '@angular/router';

/**
 * Android navigation map:
 * - Role chooser -> trainer or client login -> role tab shell.
 * - Trainer shell: Dashboard, Clients, Forms & Groups, Templates, More.
 * - Client shell: Dashboard, Templates, Trainer, Chat, Settings.
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
        path: 'clients/:clientId',
        loadComponent: () => import('./pages/trainer/client-detail/client-detail.page').then((m) => m.ClientDetailPage)
      },
      {
        path: 'forms-groups',
        loadComponent: () => import('./pages/trainer/forms-groups/trainer-forms-groups.page').then((m) => m.TrainerFormsGroupsPage)
      },
      {
        path: 'manage',
        loadComponent: () => import('./pages/trainer/manage/trainer-manage.page').then((m) => m.TrainerManagePage)
      },
      {
        path: 'templates',
        loadComponent: () => import('./pages/trainer/templates/trainer-templates.page').then((m) => m.TrainerTemplatesPage)
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
        path: 'more/references',
        loadComponent: () => import('./pages/trainer/references/trainer-references.page').then((m) => m.TrainerReferencesPage)
      },
      {
        path: 'more/settings',
        loadComponent: () => import('./pages/trainer/settings/trainer-settings.page').then((m) => m.TrainerSettingsPage)
      },
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
        path: 'templates',
        loadComponent: () => import('./pages/client/templates/client-templates.page').then((m) => m.ClientTemplatesPage)
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
        path: 'trainer',
        loadComponent: () => import('./pages/client/trainer/client-trainer.page').then((m) => m.ClientTrainerPage),
        data: { title: 'My Trainer', note: 'Your trainer’s public profile.' }
      },
      {
        path: 'chat',
        loadComponent: () => import('./pages/client/chat/client-chat.page').then((m) => m.ClientChatPage),
        data: { title: 'Trainer Chat', note: 'Direct messages with your trainer.' }
      },
      {
        path: 'settings',
        loadComponent: () => import('./pages/client/settings/client-settings.page').then((m) => m.ClientSettingsPage),
        data: { title: 'My Details', note: 'Account, registration details, edit requests, shared info.' }
      },
      { path: '', redirectTo: 'dashboard', pathMatch: 'full' }
    ]
  },
  { path: '**', redirectTo: '' }
];
