import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { FormsGroupsApiService } from '../../../core/api/forms-groups-api.service';
import { TrainerPageShellComponent } from '../../../shared/trainer-page-shell/trainer-page-shell.component';

@Component({
  selector: 'app-trainer-group-create',
  standalone: true,
  imports: [FormsModule, RouterLink, TrainerPageShellComponent],
  templateUrl: './trainer-group-create.component.html',
  styleUrl: './trainer-group-create.component.scss'
})
export class TrainerGroupCreateComponent implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly router = inject(Router);

  groupName = 'Group 1';
  groupDescription = '';
  isLoading = true;
  isSaving = false;
  message = '';
  messageType: 'success' | 'error' = 'success';

  ngOnInit(): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        if (!overview.has_lead_form) {
          void this.router.navigate(['/trainer/forms-groups']);
          return;
        }

        this.groupName = `Group ${overview.groups.length + 1}`;
        this.isLoading = false;
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Could not load group setup.');
        this.isLoading = false;
      }
    });
  }

  createGroup(): void {
    this.isSaving = true;
    this.message = '';
    this.formsGroupsApi.createGroup(this.groupName, this.groupDescription).subscribe({
      next: (response) => {
        this.messageType = 'success';
        this.message = 'Group created successfully. Review and confirm the client creation form for this group.';
        // Each path piece must be its own segment - a combined
        // 'client-form/create' string gets URL-encoded and never matches the
        // route, which stranded trainers on this page until they refreshed.
        void this.router.navigate(['/trainer/groups', response.group.id, 'client-form', 'create'], {
          queryParams: { from: 'group-create' }
        });
      },
      error: (error: unknown) => {
        this.messageType = 'error';
        this.message = this.formatApiError(error, 'Group could not be created.');
        this.isSaving = false;
      }
    });
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }
}
