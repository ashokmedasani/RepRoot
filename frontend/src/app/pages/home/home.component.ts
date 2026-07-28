import { Component, ElementRef, HostListener } from '@angular/core';
import { RouterLink } from '@angular/router';

import { ThemeSwitcherComponent } from '@shared/theme-switcher/theme-switcher.component';

interface StudioFeature {
  label: string;
}

interface BrandValue {
  label: string;
}

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [RouterLink, ThemeSwitcherComponent],
  templateUrl: './home.component.html',
  styleUrl: './home.component.scss'
})
export class HomeComponent {
  readonly supportEmail = window.APP_CONFIG?.supportEmail || '';

  readonly studioFeatures: StudioFeature[] = [
    { label: 'Client Management' },
    { label: 'Custom Forms' },
    { label: 'Progress Tracking' },
    { label: 'Communication' },
    { label: 'Notes' },
    { label: 'Groups' },
    { label: 'Payments' },
    { label: 'Dashboard' },
    { label: 'Reports' }
  ];

  readonly values: BrandValue[] = [
    { label: 'Simplicity' },
    { label: 'Trust' },
    { label: 'Transparency' },
    { label: 'Progress' },
    { label: 'Consistency' },
    { label: 'Relationships' },
    { label: 'Privacy' },
    { label: 'Innovation' }
  ];

  constructor(private readonly hostRef: ElementRef<HTMLElement>) {}

  // Same-page "#section" links: intercept and scroll instantly. The global
  // `scroll-behavior: smooth` in styles.scss is silently dropped in some
  // environments (headless/automated browsers, reduced-motion setups), so
  // relying on native anchor scrolling alone leaves the click doing nothing.
  @HostListener('click', ['$event'])
  onHostClick(event: MouseEvent): void {
    const anchor = (event.target as HTMLElement)?.closest('a[href^="#"]');
    if (!anchor) return;

    const id = anchor.getAttribute('href')!.slice(1);
    const target = this.hostRef.nativeElement.querySelector(`#${id}`) || document.getElementById(id);
    if (!target) return;

    event.preventDefault();
    target.scrollIntoView({ behavior: 'instant' as ScrollBehavior, block: 'start' });
    history.replaceState(null, '', `#${id}`);
  }
}
