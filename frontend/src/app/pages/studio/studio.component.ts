import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ThemeSwitcherComponent } from '@shared/theme-switcher/theme-switcher.component';

interface PlatformFeature {
  title: string;
  description: string;
}

@Component({
  selector: 'app-studio',
  standalone: true,
  imports: [RouterLink, ThemeSwitcherComponent],
  templateUrl: './studio.component.html',
  styleUrl: './studio.component.scss'
})
export class StudioComponent {
  readonly appName = 'RepRoot Studio';
  readonly launchRoute = '/portal';

  readonly professionalFeatures: PlatformFeature[] = [
    {
      title: 'Leads',
      description: 'Track new prospects from first conversation to conversion.'
    },
    {
      title: 'Groups',
      description: 'Organize training cohorts, shared plans, and accountability circles.'
    },
    {
      title: 'Clients',
      description: 'Manage profiles, goals, progress notes, and professional follow-ups.'
    },
    {
      title: 'Targets',
      description: 'Set daily, weekly, and monthly expectations from one workspace.'
    }
  ];

  readonly clientFeatures: PlatformFeature[] = [
    {
      title: 'Profile',
      description: 'Review personal details and professional-approved fitness information.'
    },
    {
      title: 'Goals',
      description: 'See active goals and understand what progress should look like.'
    },
    {
      title: 'Targets',
      description: 'View daily, weekly, and monthly targets in a focused client portal.'
    },
    {
      title: 'Progress',
      description: 'Submit updates that help the professional guide the next step.'
    }
  ];
}
