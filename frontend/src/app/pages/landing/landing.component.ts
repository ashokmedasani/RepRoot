import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ThemeSwitcherComponent } from '../../shared/theme-switcher/theme-switcher.component';

interface PlatformFeature {
  title: string;
  description: string;
}

@Component({
  selector: 'app-landing',
  standalone: true,
  imports: [RouterLink, ThemeSwitcherComponent],
  templateUrl: './landing.component.html',
  styleUrl: './landing.component.scss'
})
export class LandingComponent {
  readonly temporaryAppName = 'CoachFlow Studio';
  readonly nextPageRoute = '/portal';

  readonly trainerFeatures: PlatformFeature[] = [
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
      description: 'Manage profiles, goals, progress notes, and trainer follow-ups.'
    },
    {
      title: 'Targets',
      description: 'Set daily, weekly, and monthly expectations from one workspace.'
    }
  ];

  readonly clientFeatures: PlatformFeature[] = [
    {
      title: 'Profile',
      description: 'Review personal details and trainer-approved fitness information.'
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
      description: 'Submit updates that help the trainer guide the next step.'
    }
  ];
}
