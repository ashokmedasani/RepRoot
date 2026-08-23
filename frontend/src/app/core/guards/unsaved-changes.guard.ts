import { CanDeactivateFn } from '@angular/router';
import { inject } from '@angular/core';

import { ConfirmationDialogService } from '@shared/confirmation-dialog/confirmation-dialog.service';

/** Implemented by any page that can hold edits worth warning about. */
export interface HasUnsavedChanges {
  hasPendingChanges(): boolean;
}

/**
 * Stops a half-finished edit disappearing when the user navigates away.
 *
 * The case this exists for: adding a profile photo, leaving the page, coming
 * back and finding it gone — because it was never saved and nothing said so.
 * A silently discarded upload reads as a bug in the app rather than a missed
 * click.
 *
 * This covers leaving the page by router navigation. Switching tabs inside
 * Settings is local state rather than routing, so that case is handled in the
 * settings component itself; closing or reloading the browser is handled by a
 * beforeunload listener on the form.
 */
export const unsavedChangesGuard: CanDeactivateFn<HasUnsavedChanges> = async (component) => {
  if (!component?.hasPendingChanges?.()) {
    return true;
  }

  return inject(ConfirmationDialogService).confirm({
    kind: 'warning',
    title: 'Leave without saving?',
    target: 'Your profile changes',
    impact: 'You have unsaved changes, including any photo you just added. Leaving this page discards them.',
    confirmLabel: 'Discard changes'
  });
};
