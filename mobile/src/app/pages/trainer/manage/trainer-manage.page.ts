import { DatePipe } from '@angular/common';
import { Component, OnInit, inject } from '@angular/core';
import { RouterLink } from '@angular/router';
import {
  IonContent,
  IonHeader,
  IonIcon,
  IonRefresher,
  IonRefresherContent,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import {
  addCircleOutline,
  calendarOutline,
  documentTextOutline,
  folderOpenOutline,
  layersOutline,
  peopleOutline
} from 'ionicons/icons';

import { FormsGroupsApiService, FormsGroupsOverview } from '../../../core/api/forms-groups-api.service';
import { TemplatesApiService, TrackingTemplateRecord } from '../../../core/api/templates-api.service';

/** Manage hub — quick actions (Forms, Groups, Templates, References, Schedule) + recent items, per the reference design. */
@Component({
  selector: 'app-trainer-manage',
  standalone: true,
  imports: [
    DatePipe,
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonIcon
  ],
  template: `
    <ion-header><ion-toolbar><ion-title>Manage</ion-title></ion-toolbar></ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad manage-page">
        <p class="eyebrow">Quick actions</p>
        <div class="quick-grid">
          <a routerLink="/trainer/tabs/manage/forms-groups"><ion-icon name="document-text-outline" /><span>Forms</span></a>
          <a routerLink="/trainer/tabs/manage/forms-groups" [queryParams]="{ tab: 'groups' }"><ion-icon name="people-outline" /><span>Groups</span></a>
          <a routerLink="/trainer/tabs/manage/templates"><ion-icon name="layers-outline" /><span>Templates</span></a>
          <a routerLink="/trainer/tabs/manage/references"><ion-icon name="folder-open-outline" /><span>References</span></a>
          <a routerLink="/trainer/tabs/manage/schedule"><ion-icon name="calendar-outline" /><span>Schedule</span></a>
          <a routerLink="/trainer/tabs/clients/new"><ion-icon name="add-circle-outline" /><span>New client</span></a>
        </div>

        <div class="section-row">
          <h2>Recent items</h2>
        </div>
        <div class="row-list">
          @if (overview?.lead_form; as leadForm) {
            <a class="row-item" routerLink="/trainer/tabs/manage/forms-groups">
              <ion-icon name="document-text-outline" style="font-size:1.3rem;color:var(--app-success)" />
              <div class="row-main">
                <h3>{{ leadForm.title }}</h3>
                <p>Main form · updated {{ leadForm.updated_at | date: 'dd MMM' }}</p>
              </div>
              <div class="row-side"><span class="pill info">Form</span></div>
            </a>
          }
          @for (template of templates.slice(0, 2); track template.id) {
            <a class="row-item" routerLink="/trainer/tabs/manage/templates">
              <ion-icon name="layers-outline" style="font-size:1.3rem;color:var(--app-primary)" />
              <div class="row-main">
                <h3>{{ template.name }}</h3>
                <p>Template · updated {{ template.updated_at | date: 'dd MMM' }}</p>
              </div>
              <div class="row-side"><span class="pill info">Template</span></div>
            </a>
          }
          @for (group of (overview?.groups || []).slice(0, 2); track group.id) {
            <a class="row-item" [routerLink]="['/trainer/tabs/manage/groups', group.id]">
              <ion-icon name="people-outline" style="font-size:1.3rem;color:var(--app-accent)" />
              <div class="row-main">
                <h3>{{ group.name }}</h3>
                <p>Group{{ group.has_registration_form ? ' · registration link active' : '' }}</p>
              </div>
              <div class="row-side"><span class="pill info">Group</span></div>
            </a>
          }
          @if (!overview?.lead_form && !templates.length && !overview?.groups?.length) {
            <p class="empty-note">Create your first form, group, or template to see it here.</p>
          }
        </div>

        @if (overview?.pending_forms?.length) {
          <div class="section-row">
            <h2>Waiting for review</h2>
            <a routerLink="/trainer/tabs/manage/forms-groups" [queryParams]="{ tab: 'requests' }">Open</a>
          </div>
          <div class="row-list">
            @for (submission of overview!.pending_forms.slice(0, 3); track submission.id) {
              <a class="row-item" routerLink="/trainer/tabs/manage/forms-groups" [queryParams]="{ tab: 'requests' }">
                <div class="row-main">
                  <h3>{{ submission.applicant_name }}</h3>
                  <p>Submitted {{ submission.submitted_at | date: 'dd MMM' }}</p>
                </div>
                <div class="row-side"><span class="pill warn">Pending</span></div>
              </a>
            }
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class TrainerManagePage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);

  overview: FormsGroupsOverview | null = null;
  templates: TrackingTemplateRecord[] = [];

  constructor() {
    addIcons({ calendarOutline, documentTextOutline, folderOpenOutline, peopleOutline, addCircleOutline, layersOutline });
  }

  ngOnInit(): void {
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        done?.();
      },
      error: () => done?.()
    });
    this.templatesApi.getTemplates().subscribe({
      next: (response) => (this.templates = response.templates),
      error: () => (this.templates = [])
    });
  }
}
