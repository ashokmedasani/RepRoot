import { Routes } from '@angular/router';

import { clientAuthGuard, professionalAuthGuard } from './core/guards/portal-auth.guards';
import { adminAuthGuard } from './core/guards/admin-auth.guard';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./pages/home/home.component').then((module) => module.HomeComponent),
    title: 'RepRoot'
  },
  {
    path: 'studio',
    loadComponent: () =>
      import('./pages/studio/studio.component').then((module) => module.StudioComponent),
    title: 'RepRoot Studio'
  },
  {
    path: 'about',
    redirectTo: '/',
    pathMatch: 'full'
  },
  {
    path: 'contact',
    redirectTo: '/',
    pathMatch: 'full'
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
      import('./pages/studio/portal/access-entry-placeholder.component').then(
        (module) => module.AccessEntryPlaceholderComponent
      ),
    title: 'Portal'
  },
  {
    path: 'professional-client-login',
    redirectTo: 'client/login',
    pathMatch: 'full'
  },
  {
    path: 'client/login',
    loadComponent: () =>
      import('./pages/studio/client/client-login/client-login.component').then((module) => module.ClientLoginComponent),
    title: 'Client Login'
  },
  {
    path: 'client/profile',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-profile/client-profile.component').then((module) => module.ClientProfileComponent),
    title: 'Client Portal'
  },
  {
    path: 'client/settings',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-profile/client-profile.component').then((module) => module.ClientProfileComponent),
    title: 'Client Settings'
  },
  {
    path: 'client/payments',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-payments/client-payments.component').then(
        (module) => module.ClientPaymentsComponent
      ),
    title: 'Payments'
  },
  {
    path: 'client/meetings',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-meetings/client-meetings.component').then(
        (module) => module.ClientMeetingsComponent
      ),
    title: 'Meetings'
  },
  {
    path: 'client/payments/requests/:requestId',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-payment-request-detail/client-payment-request-detail.component').then(
        (module) => module.ClientPaymentRequestDetailComponent
      ),
    title: 'Payment Request'
  },
  {
    path: 'client/payments/records/:recordId/confirmation',
    canActivate: [clientAuthGuard],
    data: { audience: 'client' },
    loadComponent: () =>
      import('./pages/studio/shared/payment-confirmation/payment-confirmation.component').then(
        (module) => module.PaymentConfirmationComponent
      ),
    title: 'Payment Confirmation'
  },
  {
    path: 'client/change-password',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-change-password/client-change-password.component').then(
        (module) => module.ClientChangePasswordComponent
      ),
    title: 'Change Password'
  },
  {
    path: 'professional-access',
    loadComponent: () =>
      import('./pages/studio/professional/professional-access/professional-access.component').then((module) => module.ProfessionalAccessComponent),
    title: 'Professional Access'
  },
  {
    path: 'professional-login',
    redirectTo: 'professional/login',
    pathMatch: 'full'
  },
  {
    path: 'professional-signup',
    redirectTo: 'professional/signup',
    pathMatch: 'full'
  },
  {
    path: 'professional/login',
    loadComponent: () =>
      import('./pages/studio/professional/professional-login/professional-login.component').then((module) => module.ProfessionalLoginComponent),
    title: 'Professional Login'
  },
  {
    path: 'professional/signup',
    loadComponent: () =>
      import('./pages/studio/professional/professional-signup/professional-signup.component').then((module) => module.ProfessionalSignupComponent),
    title: 'Professional Signup'
  },
  {
    path: 'professional/forgot-password',
    loadComponent: () =>
      import('./pages/studio/professional/professional-forgot-password/professional-forgot-password.component').then(
        (module) => module.ProfessionalForgotPasswordComponent
      ),
    title: 'Forgot Password'
  },
  {
    path: 'professional/payments/records/:recordId/confirmation',
    canActivate: [professionalAuthGuard],
    data: { audience: 'professional' },
    loadComponent: () =>
      import('./pages/studio/shared/payment-confirmation/payment-confirmation.component').then(
        (module) => module.PaymentConfirmationComponent
      ),
    title: 'Payment Confirmation'
  },
  {
    path: 'professional/dashboard',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-dashboard/professional-dashboard.component').then(
        (module) => module.ProfessionalDashboardComponent
      ),
    title: 'Dashboard'
  },
  {
    path: 'professional/profile-setup',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-profile-setup/professional-profile-setup.component').then(
        (module) => module.ProfessionalProfileSetupComponent
      ),
    title: 'Professional Profile Setup'
  },
  {
    path: 'professional/profile',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-profile/professional-profile.component').then((module) => module.ProfessionalProfileComponent),
    title: 'Professional Profile'
  },
  {
    path: 'professional/forms-groups',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-forms-groups/professional-forms-groups.component').then(
        (module) => module.ProfessionalFormsGroupsComponent
      ),
    title: 'Forms & Groups'
  },
  {
    path: 'professional/forms-groups/requests/:submissionId',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-form-request-detail/professional-form-request-detail.component').then(
        (module) => module.ProfessionalFormRequestDetailComponent
      ),
    title: 'Form Request'
  },
  {
    path: 'professional/forms/create',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-lead-form-create/professional-lead-form-create.component').then(
        (module) => module.ProfessionalLeadFormCreateComponent
      ),
    title: 'Create Lead Form'
  },
  {
    path: 'professional/subscription-payment',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-subscription-payment/professional-subscription-payment.component').then(
        (module) => module.ProfessionalSubscriptionPaymentComponent
      ),
    title: 'Subscription Payment'
  },
  {
    path: 'professional/groups/create',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-group-create/professional-group-create.component').then(
        (module) => module.ProfessionalGroupCreateComponent
      ),
    title: 'Create Group'
  },
  {
    path: 'professional/groups/:groupId',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-group-users/professional-group-users.component').then(
        (module) => module.ProfessionalGroupUsersComponent
      ),
    title: 'Group Details'
  },
  {
    path: 'professional/clients',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-clients/professional-clients.component').then(
        (module) => module.ProfessionalClientsComponent
      ),
    title: 'Clients'
  },
  {
    path: 'admin-portal/login',
    loadComponent: () => import('./pages/admin/admin-login/admin-login.component').then((module) => module.AdminLoginComponent),
    title: 'Admin Login | RepRoot'
  },
  {
    path: 'admin-portal/dashboard',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-dashboard/admin-dashboard.component').then((module) => module.AdminDashboardComponent),
    title: 'Admin Dashboard | RepRoot'
  },
  {
    path: 'admin-portal/change-password',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-change-password/admin-change-password.component').then((module) => module.AdminChangePasswordComponent),
    title: 'Secure Staff Account | RepRoot'
  },
  {
    path: 'admin-portal/finance',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-finance/admin-finance.component').then((module) => module.AdminFinanceComponent),
    title: 'Finance | RepRoot'
  },
  ...['operations','users','communications','health'].map((mode) => ({
    path: `admin-portal/${mode}`,
    canActivate: [adminAuthGuard],
    data: { mode },
    loadComponent: () => import('./pages/admin/admin-operations/admin-operations.component').then((module) => module.AdminOperationsComponent),
    title: `${mode[0].toUpperCase()}${mode.slice(1)} | RepRoot`
  })),
  {
    path: 'admin-portal/audit-logs',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-audit-logs/admin-audit-logs.component').then((module) => module.AdminAuditLogsComponent),
    title: 'Audit Logs | RepRoot'
  },
  {
    path: 'admin-portal/team',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-team/admin-team.component').then((module) => module.AdminTeamComponent),
    title: 'Team & Access | RepRoot'
  },
  {
    path: 'admin-portal/support',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-support/admin-support.component').then((module) => module.AdminSupportComponent),
    title: 'Support Center | RepRoot'
  },
  {
    path: 'admin-portal/account-lifecycle',
    canActivate: [adminAuthGuard],
    loadComponent: () => import('./pages/admin/admin-account-lifecycle/admin-account-lifecycle.component').then((module) => module.AdminAccountLifecycleComponent),
    title: 'Recycle Center | RepRoot'
  },
  {
    path: 'admin-portal/errors/web',
    canActivate: [adminAuthGuard],
    data: { platformGroup: 'web' },
    loadComponent: () => import('./pages/admin/admin-error-logs/admin-error-logs.component').then((module) => module.AdminErrorLogsComponent),
    title: 'Error Logs · Web | RepRoot'
  },
  {
    path: 'admin-portal/errors/android',
    canActivate: [adminAuthGuard],
    data: { platformGroup: 'android' },
    loadComponent: () => import('./pages/admin/admin-error-logs/admin-error-logs.component').then((module) => module.AdminErrorLogsComponent),
    title: 'Error Logs · Android | RepRoot'
  },
  {
    path: 'admin-portal/errors/ios',
    canActivate: [adminAuthGuard],
    data: { platformGroup: 'ios' },
    loadComponent: () => import('./pages/admin/admin-error-logs/admin-error-logs.component').then((module) => module.AdminErrorLogsComponent),
    title: 'Error Logs · iOS | RepRoot'
  },
  {
    path: 'client/dashboard',
    canActivate: [clientAuthGuard],
    loadComponent: () =>
      import('./pages/studio/client/client-dashboard/client-dashboard.component').then(
        (module) => module.ClientDashboardComponent
      ),
    title: 'Client Dashboard'
  },
  {
    path: 'professional/clients/add',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-manual-client-create/professional-manual-client-create.component').then(
        (module) => module.ProfessionalManualClientCreateComponent
      ),
    title: 'Add Client'
  },
  {
    path: 'professional/groups/:groupId/clients/add',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-manual-client-create/professional-manual-client-create.component').then(
        (module) => module.ProfessionalManualClientCreateComponent
      ),
    title: 'Add Client'
  },
  {
    path: 'professional/clients/:clientId',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-client-profile/professional-client-profile.component').then(
        (module) => module.ProfessionalClientProfileComponent
      ),
    title: 'Client Profile'
  },
  {
    path: 'professional/clients/:clientId/templates/:assignmentId',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-client-template/professional-client-template.component').then(
        (module) => module.ProfessionalClientTemplateComponent
      ),
    title: 'Client Template'
  },
  {
    path: 'professional/groups/:groupId/client-form/create',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-client-form-create/professional-client-form-create.component').then(
        (module) => module.ProfessionalClientFormCreateComponent
      ),
    title: 'Create Client Form'
  },
  {
    path: 'professional/templates',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-templates/professional-templates.component').then(
        (module) => module.ProfessionalTemplatesComponent
      ),
    title: 'Tracking Templates'
  },
  {
    path: 'professional/templates/create',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-tracking-template-create/professional-tracking-template-create.component').then(
        (module) => module.ProfessionalTrackingTemplateCreateComponent
      ),
    title: 'Create Tracking Template'
  },
  {
    path: 'professional/templates/:templateId/edit',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-tracking-template-create/professional-tracking-template-create.component').then(
        (module) => module.ProfessionalTrackingTemplateCreateComponent
      ),
    title: 'Edit Tracking Template'
  },
  {
    path: 'professional/groups/:groupId/tracking-template/create',
    redirectTo: 'professional/templates',
    pathMatch: 'full'
  },
  {
    path: 'professional/groups/:groupId/users',
    redirectTo: 'professional/groups/:groupId',
    pathMatch: 'full'
  },
  {
    path: 'professional/account-settings',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-account-settings/professional-account-settings.component').then(
        (module) => module.ProfessionalAccountSettingsComponent
      ),
    title: 'Settings'
  },
  {
    path: 'professional/schedule',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-schedule/professional-schedule.component').then(
        (module) => module.ProfessionalScheduleComponent
      ),
    title: 'Schedule'
  },
  {
    path: 'professional/resource',
    canActivate: [professionalAuthGuard],
    loadComponent: () =>
      import('./pages/studio/professional/professional-references/professional-references.component').then(
        (module) => module.ProfessionalReferencesComponent
      ),
    title: 'Resource Library'
  },
  {
    path: 'public/forms/:publicSlug',
    loadComponent: () =>
      import('./pages/studio/client/public-lead-form/public-lead-form.component').then((module) => module.PublicLeadFormComponent),
    title: 'Professional Lead Form'
  },
  {
    path: 'public/group-registration/:publicSlug',
    loadComponent: () =>
      import('./pages/studio/client/public-group-registration/public-group-registration.component').then(
        (module) => module.PublicGroupRegistrationComponent
    ),
    title: 'Group Client Registration'
  },
  {
    path: 'error',
    loadComponent: () =>
      import('./pages/error-page/error-page.component').then((module) => module.ErrorPageComponent),
    title: 'Error | RepRoot'
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
    title: 'Page Not Found | RepRoot'
  }
];
