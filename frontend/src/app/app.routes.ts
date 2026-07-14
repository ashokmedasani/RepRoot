import { Routes } from '@angular/router';

import { clientAuthGuard, trainerAuthGuard } from './core/guards/portal-auth.guards';
import { adminAuthGuard } from './core/guards/admin-auth.guard';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./pages/landing/landing.component').then((module) => module.LandingComponent),
    title: 'Trainer Management Platform'
  },
  {
    path: 'terms',
    loadComponent: () => import('./pages/legal/legal.component').then((module) => module.LegalPageComponent),
    data: { doc: 'terms' },
    title: 'Terms & Conditions'
  },
  {
    path: 'privacy',
    loadComponent: () => import('./pages/legal/legal.component').then((module) => module.LegalPageComponent),
    data: { doc: 'privacy' },
    title: 'Privacy Policy'
  },
  {
    path: 'portal',
    loadComponent: () =>
      import('./pages/access-entry-placeholder/access-entry-placeholder.component').then(
        (module) => module.AccessEntryPlaceholderComponent
      ),
    title: 'Portal'
  },
  {
    path: 'trainer-client-login',
    redirectTo: 'client/login',
    pathMatch: 'full'
  },
  {
    path: 'client/login',
    loadComponent: () =>
      import('./pages/clients/client-login/client-login.component').then((module) => module.ClientLoginComponent),
    title: 'Client Login'
  },
  {
    path: 'client/profile',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/clients/client-profile/client-profile.component').then((module) => module.ClientProfileComponent),
    title: 'Client Portal'
  },
  {
    path: 'client/settings',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/clients/client-profile/client-profile.component').then((module) => module.ClientProfileComponent),
    title: 'Client Settings'
  },
  {
    path: 'client/change-password',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/clients/client-change-password/client-change-password.component').then(
        (module) => module.ClientChangePasswordComponent
      ),
    title: 'Change Password'
  },
  {
    path: 'trainer-access',
    loadComponent: () =>
      import('./pages/trainer/trainer-access/trainer-access.component').then((module) => module.TrainerAccessComponent),
    title: 'Trainer Access'
  },
  {
    path: 'trainer-login',
    redirectTo: 'trainer/login',
    pathMatch: 'full'
  },
  {
    path: 'trainer-signup',
    redirectTo: 'trainer/signup',
    pathMatch: 'full'
  },
  {
    path: 'trainer/login',
    loadComponent: () =>
      import('./pages/trainer/trainer-login/trainer-login.component').then((module) => module.TrainerLoginComponent),
    title: 'Trainer Login'
  },
  {
    path: 'trainer/signup',
    loadComponent: () =>
      import('./pages/trainer/trainer-signup/trainer-signup.component').then((module) => module.TrainerSignupComponent),
    title: 'Trainer Signup'
  },
  {
    path: 'trainer/forgot-password',
    loadComponent: () =>
      import('./pages/trainer/trainer-forgot-password/trainer-forgot-password.component').then(
        (module) => module.TrainerForgotPasswordComponent
      ),
    title: 'Forgot Password'
  },
  {
    path: 'trainer/dashboard',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-dashboard/trainer-dashboard.component').then(
        (module) => module.TrainerDashboardComponent
      ),
    title: 'Dashboard'
  },
  {
    path: 'trainer/profile-setup',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-profile-setup/trainer-profile-setup.component').then(
        (module) => module.TrainerProfileSetupComponent
      ),
    title: 'Trainer Profile Setup'
  },
  {
    path: 'trainer/profile',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-profile/trainer-profile.component').then((module) => module.TrainerProfileComponent),
    title: 'Trainer Profile'
  },
  {
    path: 'trainer/forms-groups',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-forms-groups/trainer-forms-groups.component').then(
        (module) => module.TrainerFormsGroupsComponent
      ),
    title: 'Forms & Groups'
  },
  {
    path: 'trainer/forms-groups/requests/:submissionId',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-form-request-detail/trainer-form-request-detail.component').then(
        (module) => module.TrainerFormRequestDetailComponent
      ),
    title: 'Form Request'
  },
  {
    path: 'trainer/forms/create',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-lead-form-create/trainer-lead-form-create.component').then(
        (module) => module.TrainerLeadFormCreateComponent
      ),
    title: 'Create Lead Form'
  },
  {
    path: 'trainer/groups/create',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-group-create/trainer-group-create.component').then(
        (module) => module.TrainerGroupCreateComponent
      ),
    title: 'Create Group'
  },
  {
    path: 'trainer/groups/:groupId',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-group-users/trainer-group-users.component').then(
        (module) => module.TrainerGroupUsersComponent
      ),
    title: 'Group Details'
  },
  {
    path: 'trainer/clients',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-clients/trainer-clients.component').then(
        (module) => module.TrainerClientsComponent
      ),
    title: 'Clients'
  },
  {
    path: 'admin-portal/login',
    loadComponent: () => import('./pages/admin/admin-login/admin-login.component').then((module) => module.AdminLoginComponent),
    title: 'Admin Login | CoachFlow'
  },
  {
    path: 'admin-portal/dashboard',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-dashboard/admin-dashboard.component').then((module) => module.AdminDashboardComponent),
    title: 'Admin Dashboard | CoachFlow'
  },
  {
    path: 'admin-portal/finance',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-finance/admin-finance.component').then((module) => module.AdminFinanceComponent),
    title: 'Finance | CoachFlow'
  },
  {
    path: 'admin-portal/audit-logs',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-audit-logs/admin-audit-logs.component').then((module) => module.AdminAuditLogsComponent),
    title: 'Audit Logs | CoachFlow'
  },
  {
    path: 'client/dashboard',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/clients/client-dashboard/client-dashboard.component').then(
        (module) => module.ClientDashboardComponent
      ),
    title: 'Client Dashboard'
  },
  {
    path: 'trainer/clients/add',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-manual-client-create/trainer-manual-client-create.component').then(
        (module) => module.TrainerManualClientCreateComponent
      ),
    title: 'Add Client'
  },
  {
    path: 'trainer/groups/:groupId/clients/add',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-manual-client-create/trainer-manual-client-create.component').then(
        (module) => module.TrainerManualClientCreateComponent
      ),
    title: 'Add Client'
  },
  {
    path: 'trainer/clients/:clientId',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-client-profile/trainer-client-profile.component').then(
        (module) => module.TrainerClientProfileComponent
      ),
    title: 'Client Profile'
  },
  {
    path: 'trainer/clients/:clientId/templates/:assignmentId',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-client-template/trainer-client-template.component').then(
        (module) => module.TrainerClientTemplateComponent
      ),
    title: 'Client Template'
  },
  {
    path: 'trainer/groups/:groupId/client-form/create',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-client-form-create/trainer-client-form-create.component').then(
        (module) => module.TrainerClientFormCreateComponent
      ),
    title: 'Create Client Form'
  },
  {
    path: 'trainer/templates',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-templates/trainer-templates.component').then(
        (module) => module.TrainerTemplatesComponent
      ),
    title: 'Tracking Templates'
  },
  {
    path: 'trainer/templates/create',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component').then(
        (module) => module.TrainerTrackingTemplateCreateComponent
      ),
    title: 'Create Tracking Template'
  },
  {
    path: 'trainer/templates/:templateId/edit',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component').then(
        (module) => module.TrainerTrackingTemplateCreateComponent
      ),
    title: 'Edit Tracking Template'
  },
  {
    path: 'trainer/groups/:groupId/tracking-template/create',
    redirectTo: 'trainer/templates',
    pathMatch: 'full'
  },
  {
    path: 'trainer/groups/:groupId/users',
    redirectTo: 'trainer/groups/:groupId',
    pathMatch: 'full'
  },
  {
    path: 'trainer/account-settings',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-account-settings/trainer-account-settings.component').then(
        (module) => module.TrainerAccountSettingsComponent
      ),
    title: 'Settings'
  },
  {
    path: 'trainer/references',
    canActivate: [trainerAuthGuard],
    loadComponent: () =>
      import('./pages/trainer/trainer-references/trainer-references.component').then(
        (module) => module.TrainerReferencesComponent
      ),
    title: 'References Library'
  },
  {
    path: 'public/forms/:publicSlug',
    loadComponent: () =>
      import('./pages/clients/public-lead-form/public-lead-form.component').then((module) => module.PublicLeadFormComponent),
    title: 'Trainer Lead Form'
  },
  {
    path: 'public/group-registration/:publicSlug',
    loadComponent: () =>
      import('./pages/clients/public-group-registration/public-group-registration.component').then(
        (module) => module.PublicGroupRegistrationComponent
    ),
    title: 'Group Client Registration'
  },
  {
    path: 'error',
    loadComponent: () =>
      import('./pages/error-page/error-page.component').then((module) => module.ErrorPageComponent),
    title: 'Error | CoachFlow'
  },
  {
    path: '**',
    loadComponent: () =>
      import('./pages/error-page/error-page.component').then((module) => module.ErrorPageComponent),
    data: {
      error: {
        status: 404,
        eyebrow: 'Page not found',
        title: 'We could not find that page',
        message: 'The address may be incorrect, or the page may have moved.',
        canRetry: false,
        sourceUrl: '/'
      }
    },
    title: 'Page Not Found | CoachFlow'
  }
];
