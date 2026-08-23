import { Injectable, signal } from '@angular/core';

/**
 * The in-app walkthrough.
 *
 * Every step points at something real on the page — the notification bell, the
 * Workspace Setup box, the Activity tabs — rather than describing it in the
 * abstract. An earlier version was a centred dialog full of bullet points, and
 * reading a list about a screen while that screen sits ignored behind a dim
 * overlay teaches nobody anything. A step here highlights the actual element
 * and says one sentence about it.
 *
 * The tour crosses pages: when the next step lives elsewhere, the overlay
 * navigates and picks up where it left off. That is what makes it a tour of the
 * product rather than eight separate popups.
 *
 * Steps whose target is not on screen are skipped automatically. Plenty of them
 * are conditional — Workspace Setup disappears once setup is done, the Payments
 * tab only exists when payments are on — and a tour that stalls pointing at
 * nothing is worse than one that is a step shorter.
 */

/** Matches ProfessionalSection in the page shell, so a page never has to say
 *  which guide it wants — the shell already knows which page it is. */
export type GuidePageKey =
  | 'dashboard'
  | 'forms-groups'
  | 'templates'
  | 'clients'
  | 'schedule'
  | 'resource'
  | 'profile'
  | 'settings';

export interface GuideStep {
  page: GuidePageKey;
  /** CSS selector for the element to highlight. `null` centres the step, used
   *  for the one-line introduction to a page. */
  target: string | null;
  /** A control to click before looking for the target -- a tab, usually.
   *  Without this the tour could describe Payments while Activity was still
   *  the visible tab, which is exactly how it read before. */
  activate?: string;
  title: string;
  body: string;
}

export interface GuidePage {
  key: GuidePageKey;
  title: string;
  route: string;
  summary: string;
}

const WELCOME_TOUR_SEEN_KEY = 'reproot-welcome-tour-seen';

@Injectable({ providedIn: 'root' })
export class GuideService {
  readonly pages: GuidePage[] = [
    { key: 'dashboard', title: 'Dashboard', route: '/professional/dashboard', summary: 'Everything waiting on you, in one place.' },
    { key: 'forms-groups', title: 'Forms and Groups', route: '/professional/forms-groups', summary: 'How new people reach you, and how you organise them.' },
    { key: 'templates', title: 'Templates', route: '/professional/templates', summary: 'The check-ins your clients fill in.' },
    { key: 'clients', title: 'Clients', route: '/professional/clients', summary: 'Every client you work with.' },
    { key: 'schedule', title: 'Schedule', route: '/professional/schedule', summary: 'Your availability and every meeting.' },
    { key: 'resource', title: 'Resource Library', route: '/professional/resource', summary: 'The material you share with clients.' },
    { key: 'profile', title: 'Profile', route: '/professional/profile', summary: 'What your clients see about you.' },
    { key: 'settings', title: 'Settings', route: '/professional/account-settings', summary: 'Your account, plan, and how you get paid.' }
  ];

  /**
   * Every step, in tour order. Targets are `data-tour` attributes rather than
   * class names: a class is a styling decision that someone will reasonably
   * rename one day, and the tour would break silently.
   */
  readonly steps: GuideStep[] = [
    // --- Dashboard ---------------------------------------------------------
    {
      page: 'dashboard',
      target: '[data-tour="sidebar-nav"]',
      title: 'Your workspace',
      body: 'Every part of RepRoot is here. The badges show what needs you, so you can tell at a glance where to go.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="notifications"]',
      title: 'Notifications',
      body: 'Anything that happened while you were away: new requests, client messages, payment updates.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="workspace-setup"]',
      title: 'Workspace setup',
      body: 'While anything here is incomplete this box stays on your dashboard. Finish all five and it disappears for good.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="plan-totals"]',
      title: 'Your plan',
      body: 'Your current plan, and how much of it you are using. These counts move as you add clients, groups, templates and resources.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="dashboard-tabs"]',
      title: 'Activity, Payments and Schedules',
      body: 'Three views of the same day. Activity is messages and requests, Payments is money owed and received, Schedules is what is coming up.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="activity-summary"]',
      activate: '[data-tour="tab-activity"]',
      title: 'Activity: what is waiting on you',
      body: 'Unread messages, people who applied, and clients asking to change their account. The cards below list each one.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="payments-panel"]',
      activate: '[data-tour="tab-payments"]',
      title: 'Payments: a one-time setup first',
      body: 'Before you can track money you pick a reporting currency, and that choice is permanent. Set up your payment methods here too — this is how you collect from clients, separate from your own RepRoot plan.'
    },
    {
      page: 'dashboard',
      target: '[data-tour="schedules-panel"]',
      activate: '[data-tour="tab-schedules"]',
      title: 'Schedules: what is coming up',
      body: 'Anything overdue, due in the next day, and due this week — plus what you have finished recently.'
    },

    // --- Forms and Groups --------------------------------------------------
    {
      page: 'forms-groups',
      target: '[data-tour="lead-form-link"]',
      activate: '[data-tour="tab-forms"]',
      title: 'Your public lead form',
      body: 'Share this link anywhere. Anyone who fills it in arrives here as a request for you to approve or decline.'
    },
    {
      page: 'forms-groups',
      target: '[data-tour="meeting-settings"]',
      title: 'Introductory meetings',
      body: 'Turn this on and applicants can also request a first meeting with you. Every request still needs your approval.'
    },
    {
      page: 'forms-groups',
      target: '[data-tour="form-requests"]',
      title: 'Form requests',
      body: 'Everyone who applied. Approving one turns them into a client with their own portal access.'
    },
    {
      page: 'forms-groups',
      target: '[data-tour="tab-groups"]',
      activate: '[data-tour="tab-groups"]',
      title: 'Client Groups',
      body: 'The second tab. Groups organise your clients, and each has its own Client Information Form for people you already know.'
    },
    {
      page: 'forms-groups',
      target: '[data-tour="groups"]',
      activate: '[data-tour="tab-groups"]',
      title: 'Your groups',
      body: 'Create a group, share its form, and everyone who completes it lands here ready to become a client.'
    },

    // --- Templates ---------------------------------------------------------
    {
      page: 'templates',
      target: '[data-tour="create-template"]',
      title: 'Create Template',
      body: 'Top right, on every page in this workspace, is the main action for that page. Here it builds a new tracking template from scratch.'
    },
    {
      page: 'templates',
      target: '[data-tour="template-slots"]',
      title: 'Template slots',
      body: 'Templates belong to you, not to a group, so any template can be assigned to any client. Your plan sets how many you can keep.'
    },
    {
      page: 'templates',
      target: '[data-tour="standard-templates"]',
      title: 'Standard templates',
      body: 'Ready-made check-ins. Adopt one and change it, rather than starting from an empty form.'
    },
    {
      page: 'templates',
      target: '[data-tour="my-templates"]',
      title: 'Your templates',
      body: 'Fields are always optional for clients: a template guides a check-in, it never stops anyone submitting one.'
    },

    // --- Clients -----------------------------------------------------------
    {
      page: 'clients',
      target: '[data-tour="add-client"]',
      title: 'Add Client',
      body: 'Top right again. Add someone directly when you already know them, instead of waiting for them to come through a form.'
    },
    {
      page: 'clients',
      target: '[data-tour="client-summary"]',
      title: 'Your clients at a glance',
      body: 'How many you have, and how many are still on a temporary password and have not signed in yet.'
    },
    {
      page: 'clients',
      target: '[data-tour="client-table"]',
      title: 'Every client',
      body: 'Open anyone to assign templates, read their entries, message them, or set a follow-up. Came From tells you how they reached you.'
    },

    // --- Schedule ----------------------------------------------------------
    {
      page: 'schedule',
      target: '[data-tour="schedule-calendar"]',
      title: 'Your month',
      body: 'Busy days are shaded. Click any day to narrow the lists below to just that day.'
    },
    {
      page: 'schedule',
      target: '[data-tour="schedule-meetings"]',
      title: 'Meetings by where they came from',
      body: 'Requests from clients, meetings you booked yourself, and meetings from your lead form each have their own box.'
    },

    // --- Resource Library --------------------------------------------------
    {
      page: 'resource',
      target: '[data-tour="resource-search"]',
      title: 'Your resource library',
      body: 'PDFs, images, notes and YouTube links, organised into categories. Share them with a client alongside a template.'
    },

    // --- Profile -----------------------------------------------------------
    {
      page: 'profile',
      target: '[data-tour="profile-preview"]',
      title: 'What clients see',
      body: 'Your name, headline and location are always visible. Every other section is private until you make it public.'
    },

    // --- Settings ----------------------------------------------------------
    {
      page: 'settings',
      target: '[data-tour="settings-tabs"]',
      title: 'Settings',
      body: 'Your account and security, your RepRoot plan, how you collect money from clients, and this guide. Replay any of this from Application Guide.'
    }
  ];

  /** Index into whichever step list is running. Null means nothing is running. */
  readonly stepIndex = signal<number | null>(null);

  /** The steps the current run is walking: all of them, or one page's worth. */
  readonly activeSteps = signal<GuideStep[]>([]);

  get stepCount(): number {
    return this.activeSteps().length;
  }

  currentStep(): GuideStep | null {
    const index = this.stepIndex();
    return index === null ? null : this.activeSteps()[index] ?? null;
  }

  pageFor(key: GuidePageKey | string): GuidePage | null {
    return this.pages.find((page) => page.key === key) ?? null;
  }

  stepsForPage(key: GuidePageKey): GuideStep[] {
    return this.steps.filter((step) => step.page === key);
  }

  // --- Running -------------------------------------------------------------

  /** The whole product, every page in order. */
  startFullTour(): void {
    this.activeSteps.set(this.steps);
    this.stepIndex.set(0);
  }

  /** Just one page, for the play buttons in the Application Guide. */
  startPageTour(key: GuidePageKey): void {
    const steps = this.stepsForPage(key);
    if (!steps.length) {
      return;
    }
    this.activeSteps.set(steps);
    this.stepIndex.set(0);
  }

  isRunning(): boolean {
    return this.stepIndex() !== null;
  }

  next(): void {
    const index = this.stepIndex();
    if (index === null) {
      return;
    }
    if (index + 1 >= this.activeSteps().length) {
      this.end();
      return;
    }
    this.stepIndex.set(index + 1);
  }

  previous(): void {
    const index = this.stepIndex();
    if (index !== null && index > 0) {
      this.stepIndex.set(index - 1);
    }
  }

  /** Moves past a step whose target is not on the page. */
  skipCurrent(): void {
    this.next();
  }

  end(): void {
    this.stepIndex.set(null);
    this.activeSteps.set([]);
    this.markSeen();
  }

  // --- First run -----------------------------------------------------------

  hasSeenTour(): boolean {
    try {
      return window.localStorage.getItem(WELCOME_TOUR_SEEN_KEY) === 'true';
    } catch {
      // Private browsing can refuse storage. Treating that as "already seen" is
      // the kinder failure: a tour that restarts on every page load is far
      // worse than one that never appears.
      return true;
    }
  }

  startFullTourIfUnseen(): void {
    if (!this.hasSeenTour()) {
      this.startFullTour();
    }
  }

  private markSeen(): void {
    try {
      window.localStorage.setItem(WELCOME_TOUR_SEEN_KEY, 'true');
    } catch {
      // Not being able to remember is not worth failing over.
    }
  }
}
