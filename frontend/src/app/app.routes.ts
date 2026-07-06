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
    redirectTo: 'portal',
    pathMatch: 'full'
  },
  {
    path: 'trainer-access',
    loadComponent: () =>
      import('./pages/trainer-access/trainer-access.component').then((module) => module.TrainerAccessComponent),
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
      import('./pages/trainer-login/trainer-login.component').then((module) => module.TrainerLoginComponent),
    title: 'Trainer Login'
  },
  {
    path: 'trainer/signup',
    loadComponent: () =>
      import('./pages/trainer-signup/trainer-signup.component').then((module) => module.TrainerSignupComponent),
    title: 'Trainer Signup'
  },
  {
    path: 'trainer/forgot-password',
    loadComponent: () =>
      import('./pages/trainer-forgot-password/trainer-forgot-password.component').then(
        (module) => module.TrainerForgotPasswordComponent
      ),
    title: 'Forgot Password'
  },
  {
    path: 'trainer/profile-setup',
    loadComponent: () =>
      import('./pages/trainer-profile-setup/trainer-profile-setup.component').then(
        (module) => module.TrainerProfileSetupComponent
      ),
    title: 'Trainer Profile Setup'
  },
  {
    path: 'trainer/profile',
    loadComponent: () =>
      import('./pages/trainer-profile/trainer-profile.component').then((module) => module.TrainerProfileComponent),
    title: 'Trainer Profile'
  },
  {
    path: 'trainer/account-settings',
    loadComponent: () =>
      import('./pages/trainer-account-settings/trainer-account-settings.component').then(
        (module) => module.TrainerAccountSettingsComponent
      ),
    title: 'Settings'
  }
];
