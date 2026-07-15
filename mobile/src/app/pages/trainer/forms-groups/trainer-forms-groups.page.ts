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
import { addOutline, shareSocialOutline, trashOutline, chevronDownOutline, chevronUpOutline } from 'ionicons/icons';

import {
  DynamicField,
  FormsGroupsApiService,
  FormsGroupsOverview,
  LeadSubmission,
  TrainerGroup
} from '../../../core/api/forms-groups-api.service';

type FormsTab = 'form' | 'requests' | 'groups';

/** Forms & Groups — lead form builder + public link, request review/approval, and group management. */
@Component({
  selector: 'app-trainer-forms-groups',
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
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/manage" /></ion-buttons>
        <ion-title>Forms &amp; Groups</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <ion-refresher slot="fixed" (ionRefresh)="refresh($event)">
        <ion-refresher-content />
      </ion-refresher>
      <div class="page-pad">
        <ion-segment [(ngModel)]="tab" mode="md">
          <ion-segment-button value="form"><ion-label>Main Form</ion-label></ion-segment-button>
          <ion-segment-button value="requests">
            <ion-label>Requests{{ overview?.pending_forms?.length ? ' (' + overview?.pending_forms?.length + ')' : '' }}</ion-label>
          </ion-segment-button>
          <ion-segment-button value="groups"><ion-label>Groups</ion-label></ion-segment-button>
        </ion-segment>

        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        <!-- ============ MAIN LEAD FORM ============ -->
        @if (tab === 'form') {
          @if (overview?.lead_form; as leadForm) {
            <div class="card">
              <h3>{{ leadForm.title }}</h3>
              <p class="sub">Public enquiry form · {{ leadForm.fields.length }} fields</p>
              <div class="kv-list">
                <div class="kv"><span>Public link</span><strong style="word-break:break-all">{{ leadForm.public_link }}</strong></div>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="shareLink(leadForm.public_link, leadForm.title)">
                  <ion-icon slot="start" name="share-social-outline" />Share link
                </ion-button>
                <ion-button size="small" fill="outline" (click)="startFormEdit()">Edit fields</ion-button>
              </div>
            </div>
          } @else if (!isEditingForm) {
            <div class="card">
              <h3>No enquiry form yet</h3>
              <p class="sub">Create your public Main Form so prospects can reach you.</p>
              <ion-button size="small" (click)="startFormEdit()"><ion-icon slot="start" name="add-outline" />Create form</ion-button>
            </div>
          }

          @if (isEditingForm) {
            <div class="card">
              <h3>{{ overview?.lead_form ? 'Edit form' : 'Create form' }}</h3>
              <div class="form-grid">
                <label><span>Form title</span><input [(ngModel)]="formTitle" placeholder="e.g. Start Training With Me" /></label>
              </div>
              <p class="hint-note">Core fields (name, email) are always included. Add your own questions below.</p>
              @for (field of customFields; track $index) {
                <div class="field-editor">
                  <div class="form-two">
                    <label><span>Question</span><input [(ngModel)]="field.label" /></label>
                    <label>
                      <span>Type</span>
                      <select [(ngModel)]="field.field_type">
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
                  @if (field.field_type === 'dropdown') {
                    <label style="display:block;margin-top:.4rem">
                      <span style="display:block;margin-bottom:.25rem;color:var(--app-muted);font-size:.72rem;font-weight:800;text-transform:uppercase">Options (comma separated)</span>
                      <input [ngModel]="(field.options || []).join(', ')" (ngModelChange)="setOptions(field, $event)" style="width:100%;border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .7rem;background:var(--app-surface);color:var(--app-text)" />
                    </label>
                  }
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
                <ion-button size="small" (click)="saveForm()" [disabled]="isSavingForm || !formTitle.trim()">
                  {{ isSavingForm ? 'Saving…' : 'Save form' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="isEditingForm = false">Cancel</ion-button>
              </div>
            </div>
          }
        }

        <!-- ============ REQUESTS ============ -->
        @if (tab === 'requests') {
          <div class="row-list">
            @for (submission of overview?.pending_forms || []; track submission.id) {
              <div class="card" style="margin-top:0">
                <div style="display:flex;justify-content:space-between;align-items:center" (click)="expandedId = expandedId === submission.id ? 0 : submission.id">
                  <div>
                    <h3 style="margin:0">{{ submission.applicant_name }}</h3>
                    <p class="sub" style="margin:.15rem 0 0">{{ submission.email }} · {{ submission.submitted_at | date: 'dd MMM' }}</p>
                  </div>
                  <ion-icon [name]="expandedId === submission.id ? 'chevron-up-outline' : 'chevron-down-outline'" />
                </div>

                @if (expandedId === submission.id) {
                  <div class="kv-list" style="margin-top:.7rem">
                    @for (answer of answersOf(submission); track answer.key) {
                      <div class="kv"><span>{{ answer.key }}</span><strong>{{ answer.value }}</strong></div>
                    }
                  </div>

                  @if (approvingId === submission.id) {
                    <div class="form-grid" style="margin-top:.8rem">
                      <label>
                        <span>Group</span>
                        <select [(ngModel)]="approveGroupId">
                          <option [ngValue]="0" disabled>Select group</option>
                          @for (group of overview?.groups || []; track group.id) {
                            <option [ngValue]="group.id">{{ group.name }}</option>
                          }
                        </select>
                      </label>
                      <label><span>Client username</span><input [(ngModel)]="approveUsername" autocapitalize="off" /></label>
                      <label>
                        <span>Temporary password</span>
                        <div style="display:flex;gap:.5rem">
                          <input [(ngModel)]="approvePassword" style="flex:1" />
                          <ion-button size="small" fill="outline" (click)="generateApprovePassword()">Generate</ion-button>
                        </div>
                      </label>
                      <label style="display:flex;align-items:center;gap:.5rem;font-size:.85rem;color:var(--app-text)">
                        <input type="checkbox" [(ngModel)]="approveSendCredentials" style="width:auto" />
                        Email credentials to client
                      </label>
                      <div class="form-two">
                        <ion-button size="small" (click)="approve(submission)" [disabled]="isApproving || !approveGroupId || !approveUsername.trim() || approvePassword.length < 8">
                          {{ isApproving ? 'Creating…' : 'Create client' }}
                        </ion-button>
                        <ion-button size="small" fill="clear" (click)="approvingId = 0">Cancel</ion-button>
                      </div>
                    </div>
                  } @else {
                    <div class="form-two" style="margin-top:.8rem">
                      <ion-button size="small" (click)="startApprove(submission)">Approve</ion-button>
                      <ion-button size="small" color="danger" fill="outline" (click)="deletePending(submission)">Delete</ion-button>
                    </div>
                  }
                }
              </div>
            } @empty {
              <p class="empty-note">No pending requests.</p>
            }
          </div>

          @if (overview?.approved_forms?.length) {
            <div class="section-row"><h2>Approved</h2></div>
            <div class="row-list">
              @for (submission of overview!.approved_forms.slice(0, 10); track submission.id) {
                <div class="row-item">
                  <div class="row-main">
                    <h3>{{ submission.applicant_name }}</h3>
                    <p>{{ submission.client_access?.group_name || '' }}{{ submission.client_access ? ' · ' + submission.client_access.username : '' }}</p>
                  </div>
                  <div class="row-side"><span class="pill ok">Client</span></div>
                </div>
              }
            </div>
          }
        }

        <!-- ============ GROUPS ============ -->
        @if (tab === 'groups') {
          <div class="row-list">
            @for (group of overview?.groups || []; track group.id) {
              <a class="row-item" [routerLink]="['/trainer/tabs/manage/groups', group.id]">
                <div class="row-main">
                  <h3>{{ group.name }}</h3>
                  <p>{{ group.description || 'No description' }}</p>
                </div>
                <div class="row-side">
                  <span class="pill" [class.ok]="group.has_registration_form" [class.warn]="!group.has_registration_form">
                    {{ group.has_registration_form ? 'Reg. link' : 'No form' }}
                  </span>
                </div>
              </a>
            } @empty {
              <p class="empty-note">No groups yet — create one below.</p>
            }
          </div>

          @if (showGroupForm) {
            <div class="card">
              <h3>New group</h3>
              <div class="form-grid">
                <label><span>Name</span><input [(ngModel)]="groupName" placeholder="e.g. Strength Cohort" /></label>
                <label><span>Description</span><textarea [(ngModel)]="groupDescription"></textarea></label>
              </div>
              <div class="form-two" style="margin-top:.7rem">
                <ion-button size="small" (click)="createGroup()" [disabled]="isSavingGroup || !groupName.trim()">
                  {{ isSavingGroup ? 'Creating…' : 'Create group' }}
                </ion-button>
                <ion-button size="small" fill="clear" (click)="showGroupForm = false">Cancel</ion-button>
              </div>
            </div>
          } @else {
            <ion-button expand="block" fill="outline" style="margin-top:1rem" (click)="showGroupForm = true" [disabled]="(overview?.groups?.length || 0) >= (overview?.max_groups || 99)">
              <ion-icon slot="start" name="add-outline" />
              New group ({{ overview?.groups?.length || 0 }}/{{ overview?.max_groups || '—' }})
            </ion-button>
          }
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `,
  styles: [`
    .field-editor { border: 1px dashed var(--app-border); border-radius: var(--app-radius-md); padding: .7rem; margin-top: .6rem; }
  `]
})
export class TrainerFormsGroupsPage implements OnInit {
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly route = inject(ActivatedRoute);
  private readonly toastController = inject(ToastController);

  tab: FormsTab = 'form';
  overview: FormsGroupsOverview | null = null;
  message = '';
  expandedId = 0;

  isEditingForm = false;
  isSavingForm = false;
  formTitle = '';
  customFields: DynamicField[] = [];

  approvingId = 0;
  isApproving = false;
  approveGroupId = 0;
  approveUsername = '';
  approvePassword = '';
  approveSendCredentials = true;

  showGroupForm = false;
  isSavingGroup = false;
  groupName = '';
  groupDescription = '';

  constructor() {
    addIcons({ addOutline, shareSocialOutline, trashOutline, chevronDownOutline, chevronUpOutline });
  }

  ngOnInit(): void {
    const requestedTab = this.route.snapshot.queryParamMap.get('tab');

    if (requestedTab === 'groups' || requestedTab === 'requests') {
      this.tab = requestedTab;
    }

    this.load();
  }

  refresh(event: CustomEvent): void {
    this.load(() => (event.target as HTMLIonRefresherElement).complete());
  }

  answersOf(submission: LeadSubmission): Array<{ key: string; value: string }> {
    return Object.entries(submission.answers || {}).map(([key, value]) => ({
      key: key.replace(/_/g, ' '),
      value: String(value)
    }));
  }

  async shareLink(url: string, title: string): Promise<void> {
    if (Capacitor.isNativePlatform()) {
      await Share.share({ title, text: `Fill out my ${title} form`, url });
      return;
    }

    if (navigator.share) {
      try {
        await navigator.share({ title, url });
        return;
      } catch {
        // cancelled or unsupported — copy instead
      }
    }

    await navigator.clipboard.writeText(url);
    await this.toast('Link copied to clipboard.');
  }

  startFormEdit(): void {
    const leadForm = this.overview?.lead_form;
    this.formTitle = leadForm?.title || 'Training Enquiry';
    this.customFields = (leadForm?.fields || []).filter((field) => !field.is_core).map((field) => ({ ...field }));
    this.isEditingForm = true;
  }

  addField(): void {
    this.customFields.push({ label: '', field_type: 'short_text', required: false, placeholder: '', help_text: '' });
  }

  setOptions(field: DynamicField, raw: string): void {
    field.options = raw
      .split(',')
      .map((option) => option.trim())
      .filter(Boolean);
  }

  saveForm(): void {
    this.isSavingForm = true;
    const fields = this.customFields.filter((field) => field.label.trim());

    this.formsGroupsApi.saveLeadForm(this.formTitle.trim(), fields).subscribe({
      next: () => {
        this.isSavingForm = false;
        this.isEditingForm = false;
        this.load();
        void this.toast('Form saved.');
      },
      error: (error: unknown) => {
        this.isSavingForm = false;
        this.message = this.formatError(error, 'Could not save the form.');
      }
    });
  }

  startApprove(submission: LeadSubmission): void {
    this.approvingId = submission.id;
    this.approveGroupId = this.overview?.groups?.length === 1 ? this.overview.groups[0].id : 0;
    this.approveUsername = `${submission.first_name}_${submission.last_name}`.toLowerCase().replace(/[^a-z0-9_]+/g, '');
    this.generateApprovePassword();
  }

  generateApprovePassword(): void {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    let value = '';
    const random = new Uint32Array(10);
    crypto.getRandomValues(random);
    random.forEach((n) => (value += alphabet[n % alphabet.length]));
    this.approvePassword = `${value.slice(0, 8)}!${value.slice(8)}`;
  }

  approve(submission: LeadSubmission): void {
    this.isApproving = true;
    this.formsGroupsApi
      .createClientAccess(submission.id, {
        group_id: this.approveGroupId,
        username: this.approveUsername.trim(),
        password: this.approvePassword,
        confirm_password: this.approvePassword,
        registration_answers: submission.answers || {},
        send_credentials: this.approveSendCredentials
      })
      .subscribe({
        next: () => {
          this.isApproving = false;
          this.approvingId = 0;
          this.load();
          void this.toast(`Client created. Temp password: ${this.approvePassword}`);
        },
        error: (error: unknown) => {
          this.isApproving = false;
          this.message = this.formatError(error, 'Could not create the client.');
        }
      });
  }

  deletePending(submission: LeadSubmission): void {
    this.formsGroupsApi.deletePendingForm(submission.id).subscribe({
      next: () => this.load(),
      error: () => void this.toast('Could not delete the request.')
    });
  }

  createGroup(): void {
    this.isSavingGroup = true;
    this.formsGroupsApi.createGroup(this.groupName.trim(), this.groupDescription.trim()).subscribe({
      next: () => {
        this.isSavingGroup = false;
        this.showGroupForm = false;
        this.groupName = '';
        this.groupDescription = '';
        this.load();
      },
      error: (error: unknown) => {
        this.isSavingGroup = false;
        this.message = this.formatError(error, 'Could not create the group.');
      }
    });
  }

  private load(done?: () => void): void {
    this.formsGroupsApi.getOverview().subscribe({
      next: (overview) => {
        this.overview = overview;
        this.message = '';
        done?.();
      },
      error: () => {
        this.message = 'Could not load forms & groups.';
        done?.();
      }
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
