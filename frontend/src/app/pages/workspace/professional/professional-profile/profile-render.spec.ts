import 'zone.js';
import 'zone.js/testing';

import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideRouter } from '@angular/router';
import { of } from 'rxjs';
import { describe, expect, it, beforeEach } from 'vitest';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { ProfessionalProfileComponent } from './professional-profile.component';

/**
 * The profile page renders its sections behind a CSS `order`, and an earlier
 * attempt resolved them through @ViewChild + ngTemplateOutlet instead. That
 * version compiled cleanly and still failed at runtime: the templates are not
 * resolved during the change-detection pass that renders them, so the grid came
 * up empty and threw ExpressionChangedAfterItHasBeenChecked.
 *
 * These tests exist because "it compiles" did not catch that.
 */
const PROFILE: any = {
  profile_setup_completed: true,
  first_name: 'Ashok',
  last_name: 'Medasani',
  professional_headline: '',
  about_me: 'I coach people.',
  professional_type: 'Trainer',
  years_experience: 5,
  specializations: 'Strength, mobility',
  languages_known: 'English, Telugu',
  training_style: 'Progressive overload',
  certification_name: 'CPT',
  certification_issued_by: 'NASM',
  certification_year: 2020,
  country: 'United States',
  state: 'Missouri',
  profile_images: [
    { id: 1, category: 'Certificates', title: 'CPT', url: '/media/a.jpg' },
    { id: 2, category: 'Other Images', title: 'Gym', url: '/media/b.jpg' }
  ],
  profile_links: [{ title: 'Site', url: 'https://x.com' }],
  profile_visibility: {
    professional_headline: true, about: true, professional_summary: true,
    specializations: true, experience: true, languages: true,
    training_style: true, certification: true, images: true, links: true
  },
  profile_section_order: ['links', 'images', 'about']
};

function setup(profile: any): ComponentFixture<ProfessionalProfileComponent> {
  // Each call builds its own module, so a test can render a second, different
  // profile without inheriting the first one's providers.
  TestBed.resetTestingModule();
  TestBed.configureTestingModule({
    imports: [ProfessionalProfileComponent],
    providers: [
      provideRouter([]),
      // The page shell pulls in several API services; they are never called in
      // these tests, they just have to be constructible.
      provideHttpClient(),
      {
        provide: ProfessionalAuthApiService,
        useValue: {
          getProfile: () => of(profile),
          // Consumed by the surrounding page shell, not by anything under test.
          getDataUsage: () => of({ usage_percent: 0 }),
          getNotifications: () => of({ notifications: [], unread_count: 0 }),
          markNotificationRead: () => of({}),
          clearNotifications: () => of({}),
          logout: () => of({}),
          updateProfileVisibility: () => of({ profile_visibility: profile.profile_visibility, profile_section_order: [], message: '' }),
          updateProfileSectionOrder: (o: string[]) => of({ profile_visibility: profile.profile_visibility, profile_section_order: o, message: '' })
        }
      }
    ]
  });
  const fixture = TestBed.createComponent(ProfessionalProfileComponent);
  fixture.detectChanges();
  return fixture;
}

describe('professional profile page', () => {
  let fixture: ComponentFixture<ProfessionalProfileComponent>;

  beforeEach(() => {
    fixture = setup(structuredClone(PROFILE));
  });

  it('renders every populated section on the first pass', () => {
    const slots = fixture.nativeElement.querySelectorAll('.section-slot');
    expect(slots.length).toBe(9);
  });

  it('survives a second change-detection pass without values shifting', () => {
    // This is the check that would have caught the ngTemplateOutlet bug: in
    // dev mode a second pass re-runs bindings and throws NG0100 if any changed.
    expect(() => fixture.detectChanges()).not.toThrow();
    expect(fixture.nativeElement.querySelectorAll('.section-slot').length).toBe(9);
  });

  it('honours the stored section order', () => {
    const component = fixture.componentInstance;
    // Stored order was partial; the rest must be appended, not dropped.
    expect(component.orderedSections.slice(0, 3)).toEqual(['links', 'images', 'about']);
    expect(component.orderedSections.length).toBe(9);
    expect(component.sectionPosition('links')).toBe(0);
    expect(component.sectionPosition('about')).toBe(2);
  });

  it('applies that order as a CSS order value in the DOM', () => {
    const slots: HTMLElement[] = Array.from(fixture.nativeElement.querySelectorAll('.section-slot'));
    const orders = slots.map((el) => el.style.order);
    expect(orders.filter((o) => o !== '').length).toBe(9);
    expect(new Set(orders).size).toBe(9);
  });

  it('shows the name and headline without a visibility toggle', () => {
    const hero = fixture.nativeElement.querySelector('.hero-copy');
    expect(hero.textContent).toContain('Ashok Medasani');
    expect(hero.querySelector('.visibility-toggle')).toBeNull();
  });

  it('splits the gallery into certificates and other images', () => {
    const component = fixture.componentInstance;
    expect(component.certificateImages.map((i) => i.title)).toEqual(['CPT']);
    expect(component.otherImages.map((i) => i.title)).toEqual(['Gym']);
  });

  it('renders no empty slots when the profile has no content', () => {
    const bare: any = structuredClone(PROFILE);
    bare.about_me = '';
    bare.professional_type = '';
    bare.specializations = '';
    bare.languages_known = '';
    bare.training_style = '';
    bare.years_experience = null;
    bare.profile_images = [];
    bare.profile_links = [];
    const f2 = setup(bare);
    // Only Certification remains: it renders even when unset, by design.
    expect(f2.nativeElement.querySelectorAll('.section-slot').length).toBe(1);
  });
});
