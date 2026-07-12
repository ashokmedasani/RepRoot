import { Routes } from '@angular/router';

/**
 * Navigation map (see Documentation/MOBILE_APP_DESIGN.md):
 * - Role chooser -> trainer or client login -> role tab shell.
 * - Trainer shell: 5 tabs (Dashboard, Clients, Forms & Groups, Templates, More).
 * - Client shell: 4 tabs (My Templates, Trainer, Chat, My Details).
 * Screens marked "stub" are Phase 2/3 placeholders reachable through real navigation.
 */
export const routes: Routes = [
  {
    path: '',
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
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'Forms & Groups', phase: 'Phase 2', note: 'Lead form, requests, and groups management.' }
      },
      {
        path: 'templates',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'Templates', phase: 'Phase 2', note: 'Template library and builder.' }
      },
      {
        path: 'more',
        loadComponent: () => import('./pages/trainer/more/trainer-more.page').then((m) => m.TrainerMorePage)
      },
      {
        path: 'more/profile',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'Profile', phase: 'Phase 2', note: 'Read-only portfolio with visibility controls and client preview.' }
      },
      {
        path: 'more/references',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'References', phase: 'Phase 2', note: 'Category accordion with inline reference details.' }
      },
      {
        path: 'more/settings',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'Settings', phase: 'Phase 2', note: 'Account, My Account, and Change Password.' }
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
        path: 'templates',
        loadComponent: () => import('./pages/client/templates/client-templates.page').then((m) => m.ClientTemplatesPage)
      },
      {
        path: 'trainer',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'My Trainer', phase: 'Phase 3', note: 'Your trainer’s public profile.' }
      },
      {
        path: 'chat',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'Trainer Chat', phase: 'Phase 3', note: 'Direct messages with your trainer.' }
      },
      {
        path: 'details',
        loadComponent: () => import('./pages/shared/stub.page').then((m) => m.StubPage),
        data: { title: 'My Details', phase: 'Phase 3', note: 'Account, registration details, edit requests, shared info.' }
      },
      { path: '', redirectTo: 'templates', pathMatch: 'full' }
    ]
  },
  { path: '**', redirectTo: '' }
];
