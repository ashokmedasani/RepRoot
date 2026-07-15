import { DatePipe } from '@angular/common';
import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { ToastController } from '@ionic/angular';
import { Capacitor } from '@capacitor/core';
import { Share } from '@capacitor/share';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { addOutline, shareSocialOutline, trashOutline } from 'ionicons/icons';

import {
  DynamicField,
  FormsGroupsApiService,
  GroupRegistrationSubmission,
  GroupUsersResponse,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';

type GroupTab = 'members' | 'registration' | 'settings';

/** One training group: members, group-registration form/link, pending registrations, and settings. */
@Component({
  selector: 'app-group-detail',
  standalone: true,
  imports: [
    DatePipe,
    FormsModule,
    RouterLink,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonButtons,
    IonBackButton,
    IonButton,
    IonIcon,
    IonContent,
    IonRefresher,
    IonRefresherContent,
    IonSegment,
    IonSegmentButton,
    IonLabel
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage/forms-groups" /></ion-buttons>
        <ion-title>{{ group?.name || 'Group' }}</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <ion-segment [(ngModel)]="tab" mode="md">
          <ion-segment-button value="members"><ion-label>Members</ion-label></ion-segment-button>
          <ion-segment-button value="registration">
            <ion-label>Registration{{ pendingSubmissions.length ? ' (' + pendingSubmissions.length + ')' : '' }}</ion-label>
          </ion-segment-button>
          <ion-segment-button value="settings"><ion-label>Settings</ion-label></ion-segment-button>
        </ion-segment>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (tab === 'members') {
          <div class="row-list">
            @for (client of data?.clients || []; track client.id) {
              <a class="row-item" [routerLink]="['/trainer/tabs/clients', client.id]">
                @if (client.photo) {
                  <img class="avatar-sm" [src]="client.photo" alt="" />
                } @else {
                  <div class="avatar-sm avatar-fallback">{{ (client.first_name[0] || '') + (client.last_name[0] || '') }}</div>
                }
                <div class="row-main">
                  <h3>{{ client.first_name }} {{ client.last_name }}</h3>
                  <p>{{ client.username }}</p>
                </div>
                <div class="row-side">
                  <span class="pill" [class.ok]="client.is_active" [class.bad]="!client.is_active">
                    {{ client.is_active ? 'Active' : 'Inactive' }}
                  </span>
                </div>
              </a>
            } @empty {
              <p class="empty-note">No members yet.</p>
            }
          </div>
          <ion-button expand="block" fill="outline" style="margin-top:1rem" routerLink="/trainer/tabs/clients/new">
            <ion-icon slot="start" name="add-outline" />Add client manually
          </ion-button>
        }

        @if (tab === 'registration') {
          @if (group?.registration_form; as regForm) {
            <div class="card">
              <h3>Group registration link</h3>
              <p class="sub">Known clients register straight into {{ group?.name }} with this link.</p>
              <div class="kv-list">
                <div class="kv"><span>Link</span><strong style="word-break:break-all">{{ registrationLink }}</strong></div>
                <div class="kv"><span>Fields</span><strong>{{ regForm.fields.length }}</strong></div>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="shareRegistrationLink()">
                  <ion-icon slot="start" name="share-social-outline" />Share link
                </ion-button>
                <ion-button size="small" fill="outline" (click)="startFormEdit()">Edit fields</ion-button>
              </div>
            </div>
          } @else if (!isEditingForm) {
            <div class="card">
              <h3>No registration form</h3>
              <p class="sub">Create one to get a shareable registration URL for this group.</p>
              <ion-button size="small" (click)="startFormEdit()"><ion-icon slot="start" name="add-outline" />Create registration form</ion-button>
            </div>
          }

          @if (isEditingForm) {
            <div class="card">
              <h3>Registration questions</h3>
              <p class="hint-note">Name and email are always collected. Add group-specific questions below.</p>
              @for (field of customFields; track $index) {
                <div style="border:1px dashed var(--app-border);border-radius:.7rem;padding:.7rem;margin-top:.6rem">
                  <div class="form-two">
                    <label><span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Question</span><input [(ngModel)]="field.label" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)" /></label>
                    <label><span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Type</span>
                      <select [(ngModel)]="field.field_type" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)">
                        <option value="short_text">Short text</option>
                        <option value="long_text">Long text</option>
                        <option value="number">Number</option>
                        <option value="phone">Phone</option>
                        <option value="dropdown">Dropdown</option>
                        <option value="yes_no">Yes / No</option>
                        <option value="date">Date</option>
                      </select>
                    </label>
                  </div>
                  <div style="display:flex;justify-content:space-between;align-items:center;margin-top:.4rem">
                    <label style="display:flex;align-items:center;gap:.4rem;font-size:.8rem;color:var(--app-muted)">
                      <input type="checkbox" [(ngModel)]="field.required" />Required
                    </label>
                    <ion-button size="small" fill="clear" color="danger" (click)="customFields.splice($index, 1)">
                      <ion-icon slot="icon-only" name="trash-outline" />
                    </ion-button>
                  </div>
                </div>
              }
              <ion-button size="small" fill="outline" style="margin-top:.6rem" (click)="addField()">
                <ion-icon slot="start" name="add-outline" />Add question
              </ion-button>
              <div class="form-two" style="margin-top:.8rem">
                <ion-button size="small" (click)="saveRegistrationForm()" [disabled]="isSavingForm">
                  {{ isSavingForm ? 'Saving…' : 'Save form' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="isEditingForm = false">Cancel</ion-button>
              </div>
            </div>
          }

          @if (pendingSubmissions.length) {
            <div class="section-row"><h2>Pending registrations</h2></div>
            @for (submission of pendingSubmissions; track submission.id) {
              <div class="card" style="margin-top:.5rem">
                <h3 style="margin:0">{{ submission.applicant_name }}</h3>
                <p class="sub" style="margin:.15rem 0 .5rem">{{ submission.email }} · {{ submission.submitted_at | date: 'dd MMM' }}</p>
                @if (convertingId === submission.id) {
                  <div class="form-grid">
                    <label><span>Client username</span><input [(ngModel)]="convertUsername" autocapitalize="off" /></label>
                    <label>
                      <span>Temporary password</span>
                      <div style="display:flex;gap:.5rem">
                        <input [(ngModel)]="convertPassword" style="flex:1" />
                        <ion-button size="small" fill="outline" (click)="generateConvertPassword()">Generate</ion-button>
                      </div>
                    </label>
                    <label style="display:flex;align-items:center;gap:.5rem;font-size:.85rem;color:var(--app-text)">
                      <input type="checkbox" [(ngModel)]="convertSendCredentials" style="width:auto" />Email credentials
                    </label>
                    <div class="form-two">
                      <ion-button size="small" (click)="convert(submission)" [disabled]="isConverting || !convertUsername.trim() || convertPassword.length < 8">
                        {{ isConverting ? 'Creating…' : 'Create client' }}
                      </ion-button>
                      <ion-button size="small" fill="clear" (click)="convertingId = 0">Cancel</ion-button>
                    </div>
                  </div>
                } @else {
                  <ion-button size="small" (click)="startConvert(submission)">Approve &amp; create client</ion-button>
                }
              </div>
            }
          }
        }

        @if (tab === 'settings') {
          <div class="card">
            <h3>Group settings</h3>
            <div class="form-grid">
              <label><span>Name</span><input [(ngModel)]="editName" /></label>
              <label><span>Description</span><textarea [(ngModel)]="editDescription"></textarea></label>
            </div>
            <ion-button size="small" style="margin-top:.7rem" (click)="saveGroup()" [disabled]="isSavingGroup || !editName.trim()">
              {{ isSavingGroup ? 'Saving…' : 'Save changes' }}
            </ion-button>
          </div>
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `
})
export class GroupDetailPage implements OnInit {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly toastController = inject(ToastController);

  groupId = 0;
  tab: GroupTab = 'members';
  data: GroupUsersResponse | null = null;
  group: TrainerGroup | null = null;
  message = '';
  registrationLinkBase = '';

  isEditingForm = false;
  isSavingForm = false;
  customFields: DynamicField[] = [];

  convertingId = 0;
  isConverting = false;
  convertUsername = '';
  convertPassword = '';
  convertSendCredentials = true;

  editName = '';
  editDescription = '';
  isSavingGroup = false;

  constructor() {
    addIcons({ addOutline, shareSocialOutline, trashOutline });
  }

  get pendingSubmissions(): GroupRegistrationSubmission[] {
    return (this.data?.registration_submissions || []).filter((submission) => submission.status === 'pending');
  }

  get registrationLink(): string {
    const slug = this.group?.registration_form?.public_slug;

    if (!slug) {
      return '';
    }

    return `${this.registrationLinkBase}/public/group-registration/${slug}`;
  }

  ngOnInit(): void {
    this.groupId = Number(this.route.snapshot.paramMap.get('groupId'));
    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  async shareRegistrationLink(): Promise<void> {
    const url = this.registrationLink;

    if (!url) {
      return;
    }

    if (Capacitor.isNativePlatform()) {
      await Share.share({ title: `Join ${this.group?.name}`, text: `Register for ${this.group?.name}`, url });
      return;
    }

    if (navigator.share) {
      try {
        await navigator.share({ title: `Join ${this.group?.name}`, url });
        return;
      } catch {
        // fall through to clipboard
      }
    }

    await navigator.clipboard.writeText(url);
    await this.toast('Link copied to clipboard.');
  }

  startFormEdit(): void {
    this.customFields = (this.group?.registration_form?.fields || [])
      .filter((field) => !field.is_core)
      .map((field) => ({ ...field }));
    this.isEditingForm = true;
  }

  addField(): void {
    this.customFields.push({ label: '', field_type: 'short_text', required: false, placeholder: '', help_text: '' });
  }

  saveRegistrationForm(): void {
    this.isSavingForm = true;
    const fields = this.customFields.filter((field) => field.label.trim());

    this.formsGroupsApi.saveRegistrationForm(this.groupId, fields).subscribe({
      next: () => {
        this.isSavingForm = false;
        this.isEditingForm = false;
        this.load();
        void this.toast('Registration form saved.');
      },
      error: (error: unknown) => {
        this.isSavingForm = false;
        this.message = this.formatError(error, 'Could not save the registration form.');
      }
    });
  }

  startConvert(submission: GroupRegistrationSubmission): void {
    this.convertingId = submission.id;
    this.convertUsername = `${submission.first_name}_${submission.last_name}`.toLowerCase().replace(/[^a-z0-9_]+/g, '');
    this.generateConvertPassword();
  }

  generateConvertPassword(): void {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    let value = '';
    const random = new Uint32Array(10);
    crypto.getRandomValues(random);
    random.forEach((n) => (value += alphabet[n % alphabet.length]));
    this.convertPassword = `${value.slice(0, 8)}!${value.slice(8)}`;
  }

  convert(submission: GroupRegistrationSubmission): void {
    this.isConverting = true;
    this.formsGroupsApi
      .createManualClient({
        group_id: this.groupId,
        username: this.convertUsername.trim(),
        password: this.convertPassword,
        confirm_password: this.convertPassword,
        registration_answers: {},
        send_credentials: this.convertSendCredentials,
        registration_submission_id: submission.id
      })
      .subscribe({
        next: (response) => {
          this.isConverting = false;
          this.convertingId = 0;
          this.load();
          void this.toast(`Client created. Temp password: ${response.temporary_password}`);
        },
        error: (error: unknown) => {
          this.isConverting = false;
          this.message = this.formatError(error, 'Could not create the client.');
        }
      });
  }

  saveGroup(): void {
    this.isSavingGroup = true;
    this.formsGroupsApi.updateGroup(this.groupId, this.editName.trim(), this.editDescription.trim()).subscribe({
      next: () => {
        this.isSavingGroup = false;
        this.load();
        void this.toast('Group updated.');
      },
      error: (error: unknown) => {
        this.isSavingGroup = false;
        this.message = this.formatError(error, 'Could not update the group.');
      }
    });
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getGroupUsers(this.groupId).subscribe({
      next: (data) => {
        this.data = data;
        this.group = data.group;
        this.editName = data.group.name;
        this.editDescription = data.group.description;
        done?.();
      },
      error: () => {
        this.message = 'Could not load this group.';
        done?.();
      }
    });

    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        const publicLink = overview.lead_form?.public_link || '';
        this.registrationLinkBase = publicLink.includes('/public/')
          ? publicLink.split('/public/')[0]
          : window.location.origin;
      },
      error: () => (this.registrationLinkBase = window.location.origin)
    });
  }

  private formatError(error: unknown, fallback: string): string {
    if (error instanceof HttpErrorResponse && error.error && typeof error.error === 'object') {
      const values = Object.values(error.error as Record<string, unknown>).flat();

      if (values.length) {
        return values.map((value) => String(value)).join(' ');
      }
    }

    return fallback;
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 2400, position: 'bottom' });
    await toast.present();
  }
}
