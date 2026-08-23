import { Injectable, NgZone } from '@angular/core';
import { NavigationEnd, Router } from '@angular/router';
import { filter } from 'rxjs';

export interface UserActionSnapshot {
  /** Human phrasing, e.g. `Clicked "Save and continue"`. Empty when nothing has been clicked yet. */
  label: string;
  /** Route the action happened on — may differ from the current route if the click caused navigation. */
  route: string;
  /** Milliseconds between the action and the moment the snapshot is taken. */
  ageMs: number;
}

/**
 * Records the last thing the user did, so an error report can say what
 * triggered it rather than only where it happened.
 *
 * Deliberately a single passive document listener rather than a directive
 * sprinkled across templates: there are hundreds of buttons in this app, and
 * any approach requiring each one to be annotated would be wrong within a
 * week. Nothing needs to opt in, and adding a new button anywhere is
 * automatically covered.
 *
 * Runs outside Angular's zone — this fires on every click in the app and must
 * not schedule a change-detection pass just to write two fields.
 */
@Injectable({ providedIn: 'root' })
export class UserActionService {
  private label = '';
  private route = '';
  private at = 0;

  constructor(router: Router, zone: NgZone) {
    zone.runOutsideAngular(() => {
      // Capture phase, so the breadcrumb is recorded even when a handler
      // stops propagation or the element is detached during the click.
      document.addEventListener('click', (event) => this.capture(event), { capture: true });
    });

    // A navigation with no click before it (deep link, redirect, guard bounce)
    // must not inherit a stale label from the previous page.
    router.events.pipe(filter((event): event is NavigationEnd => event instanceof NavigationEnd)).subscribe(() => {
      if (this.at && Date.now() - this.at > 30_000) {
        this.clear();
      }
    });
  }

  /** Lets a component name an action the DOM cannot describe (a drag, a swipe, an auto-save). */
  record(label: string, route?: string): void {
    const clean = this.sanitize(label);
    if (!clean) {
      return;
    }
    this.label = clean;
    this.route = route ?? this.currentRoute();
    this.at = Date.now();
  }

  snapshot(): UserActionSnapshot {
    return {
      label: this.label,
      route: this.route,
      ageMs: this.at ? Date.now() - this.at : 0
    };
  }

  private capture(event: Event): void {
    try {
      const control = this.findControl(event.target);
      if (!control) {
        return;
      }
      const described = this.describe(control);
      if (described) {
        this.label = described;
        this.route = this.currentRoute();
        this.at = Date.now();
      }
    } catch {
      // A breadcrumb is a convenience. It must never interfere with a click.
    }
  }

  private findControl(target: EventTarget | null): HTMLElement | null {
    let node = target instanceof HTMLElement ? target : null;
    for (let depth = 0; node && depth < 6; depth += 1) {
      const tag = node.tagName.toLowerCase();
      if (tag === 'button' || tag === 'a' || node.getAttribute('role') === 'button') {
        return node;
      }
      if (tag === 'input') {
        const type = (node as HTMLInputElement).type;
        if (type === 'submit' || type === 'button' || type === 'checkbox' || type === 'radio') {
          return node;
        }
      }
      if (tag === 'select' || tag === 'summary') {
        return node;
      }
      node = node.parentElement;
    }
    return null;
  }

  private describe(control: HTMLElement): string {
    const tag = control.tagName.toLowerCase();
    const verb = tag === 'a' ? 'Followed link' : tag === 'select' ? 'Changed dropdown' : 'Clicked';
    const name = this.sanitize(
      control.getAttribute('aria-label') ||
        (control as HTMLInputElement).value ||
        control.textContent ||
        control.getAttribute('title') ||
        ''
    );

    if (!name) {
      // An unlabelled control is still worth recording — where it sits often
      // identifies it well enough to reproduce the path.
      const hint = control.className && typeof control.className === 'string'
        ? control.className.split(/\s+/).filter(Boolean)[0]
        : '';
      return hint ? `${verb} an unlabelled ${tag} (.${hint})` : `${verb} an unlabelled ${tag}`;
    }
    return `${verb} "${name}"`;
  }

  private sanitize(value: string): string {
    // Collapse the whitespace Angular templates leave behind, and cap length —
    // a button label is a hint, not a payload. Anything that looks like a
    // credential is dropped outright rather than travelling to the mailbox;
    // the backend scrubs too, but the safest data is data never sent.
    const text = String(value || '').replace(/\s+/g, ' ').trim().slice(0, 80);
    if (!text) {
      return '';
    }
    if (/(?:password|token|secret|otp|api[_-]?key)/i.test(text)) {
      return '';
    }
    return text;
  }

  private currentRoute(): string {
    try {
      return window.location.pathname || '';
    } catch {
      return '';
    }
  }

  private clear(): void {
    this.label = '';
    this.route = '';
    this.at = 0;
  }
}
