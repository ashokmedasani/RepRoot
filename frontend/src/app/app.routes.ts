import { Routes } from '@angular/router';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () =>
      import('./pages/landing/landing.component').then((module) => module.LandingComponent),
    title: 'Trainer Management Platform'
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
    loadComponent: () =>
      import('./pages/clients/client-profile/client-profile.component').then((module) => module.ClientProfileComponent),
    title: 'Client Portal'
  },
  {
    path: 'client/change-password',
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
    path: 'trainer/profile-setup',
    loadComponent: () =>
      import('./pages/trainer/trainer-profile-setup/trainer-profile-setup.component').then(
        (module) => module.TrainerProfileSetupComponent
      ),
    title: 'Trainer Profile Setup'
  },
  {
    path: 'trainer/profile',
    loadComponent: () =>
      import('./pages/trainer/trainer-profile/trainer-profile.component').then((module) => module.TrainerProfileComponent),
    title: 'Trainer Profile'
  },
  {
    path: 'trainer/forms-groups',
    loadComponent: () =>
      import('./pages/trainer/trainer-forms-groups/trainer-forms-groups.component').then(
        (module) => module.TrainerFormsGroupsComponent
      ),
    title: 'Forms & Groups'
  },
  {
    path: 'trainer/forms/create',
    loadComponent: () =>
      import('./pages/trainer/trainer-lead-form-create/trainer-lead-form-create.component').then(
        (module) => module.TrainerLeadFormCreateComponent
      ),
    title: 'Create Lead Form'
  },
  {
    path: 'trainer/groups/create',
    loadComponent: () =>
      import('./pages/trainer/trainer-group-create/trainer-group-create.component').then(
        (module) => module.TrainerGroupCreateComponent
      ),
    title: 'Create Group'
  },
  {
    path: 'trainer/groups/:groupId',
    loadComponent: () =>
      import('./pages/trainer/trainer-group-users/trainer-group-users.component').then(
        (module) => module.TrainerGroupUsersComponent
      ),
    title: 'Group Details'
  },
  {
    path: 'trainer/clients',
    loadComponent: () =>
      import('./pages/trainer/trainer-clients/trainer-clients.component').then(
        (module) => module.TrainerClientsComponent
      ),
    title: 'Clients'
  },
  {
    path: 'trainer/clients/:clientId/templates/:assignmentId',
    loadComponent: () =>
      import('./pages/trainer/trainer-client-template-detail/trainer-client-template-detail.component').then(
        (module) => module.TrainerClientTemplateDetailComponent
      ),
    title: 'Assigned Template'
  },
  {
    path: 'trainer/clients/:clientId',
    loadComponent: () =>
      import('./pages/trainer/trainer-client-profile/trainer-client-profile.component').then(
        (module) => module.TrainerClientProfileComponent
      ),
    title: 'Client Profile'
  },
  {
    path: 'trainer/groups/:groupId/client-form/create',
    loadComponent: () =>
      import('./pages/trainer/trainer-client-form-create/trainer-client-form-create.component').then(
        (module) => module.TrainerClientFormCreateComponent
      ),
    title: 'Create Client Form'
  },
  {
    path: 'trainer/templates',
    loadComponent: () =>
      import('./pages/trainer/trainer-templates/trainer-templates.component').then(
        (module) => module.TrainerTemplatesComponent
      ),
    title: 'Tracking Templates'
  },
  {
    path: 'trainer/templates/create',
    loadComponent: () =>
      import('./pages/trainer/trainer-tracking-template-create/trainer-tracking-template-create.component').then(
        (module) => module.TrainerTrackingTemplateCreateComponent
      ),
    title: 'Create Tracking Template'
  },
  {
    path: 'trainer/templates/:templateId/edit',
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
    loadComponent: () =>
      import('./pages/trainer/trainer-group-users/trainer-group-users.component').then(
        (module) => module.TrainerGroupUsersComponent
      ),
    title: 'Group Users'
  },
  {
    path: 'trainer/account-settings',
    loadComponent: () =>
      import('./pages/trainer/trainer-account-settings/trainer-account-settings.component').then(
        (module) => module.TrainerAccountSettingsComponent
      ),
    title: 'Settings'
  },
  {
    path: 'trainer/references',
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
  }
];
