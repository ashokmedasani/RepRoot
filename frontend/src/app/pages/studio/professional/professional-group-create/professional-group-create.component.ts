import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';

import { FormsGroupsApiService } from '@core/api/forms-groups-api.service';
import { ProfessionalPageShellComponent } from '@studio-shared/professional-page-shell/professional-page-shell.component';

@Component({
  selector: 'app-professional-group-create',
  standalone: true,
  imports: [FormsModule, RouterLink, ProfessionalPageShellComponent],
  templateUrl: './professional-group-create.component.html',
  styleUrl: './professional-group-create.component.scss'
})
export class ProfessionalGroupCreateComponent implements OnInit {
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
          void this.router.navigate(['/professional/forms-groups']);
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
        // route, which stranded professionals on this page until they refreshed.
        void this.router.navigate(['/professional/groups', response.group.id, 'client-form', 'create'], {
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
