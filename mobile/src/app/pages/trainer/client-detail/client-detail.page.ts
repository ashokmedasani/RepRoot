import { DatePipe } from '@angular/common';
import { Component, OnDestroy, OnInit, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, RouterLink } from '@angular/router';
import {
  AlertController,
  ToastController
} from '@ionic/angular';
import {
  IonBackButton,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonLabel,
  IonSegment,
  IonSegmentButton,
  IonTitle,
  IonToolbar
} from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { sendOutline, checkmarkOutline, closeOutline, addOutline, trashOutline } from 'ionicons/icons';

import { ChatApiService, ChatMessageRecord } from '../../../core/api/chat-api.service';
import {
  ClientAccessDetailResponse,
  ClientAccessRecord,
  ClientReminder,
  DynamicField,
  FormsGroupsApiService,
  ProgressEntry
} from '../../../core/api/forms-groups-api.service';
import {
  TemplateAssignmentRecord,
  TemplatesApiService,
  TrackingTemplateRecord
} from '../../../core/api/templates-api.service';

type DetailTab = 'info' | 'overview' | 'tracking' | 'chat' | 'actions';

/** Trainer view of one client: profile, edit requests, schedules, tracking, chat, and account actions. */
@Component({
  selector: 'app-client-detail',
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
    IonSegment,
    IonSegmentButton,
    IonLabel
  ],
  template: `
    <ion-header>
      <ion-toolbar>
        <ion-buttons slot="start"><ion-back-button defaultHref="/trainer/tabs/clients" /></ion-buttons>
        <ion-title>{{ client ? client.first_name + ' ' + client.last_name : 'Client' }}</ion-title>
      </ion-toolbar>
    </ion-header>
    <ion-content>
      <div class="page-pad">
        @if (message) {
          <p class="error-text">{{ message }}</p>
        }

        @if (client) {
          <div class="profile-card">
            @if (client.photo) {
              <img class="avatar" [src]="client.photo" alt="" />
            } @else {
              <div class="avatar avatar-fallback">{{ initials }}</div>
            }
            <div style="flex:1;min-width:0">
              <strong>{{ client.first_name }} {{ client.last_name }}</strong>
              <small>{{ client.group_name || 'No group' }}</small>
            </div>
            <span class="pill" [class.ok]="client.is_active" [class.bad]="!client.is_active">
              {{ client.is_active ? 'Active' : 'Inactive' }}
            </span>
          </div>

          <ion-segment class="detail-tabs" [(ngModel)]="tab" mode="md" [scrollable]="true">
            <ion-segment-button value="info"><ion-label>Info</ion-label></ion-segment-button>
            <ion-segment-button value="overview"><ion-label>Activity</ion-label></ion-segment-button>
            <ion-segment-button value="tracking"><ion-label>Tracking</ion-label></ion-segment-button>
            <ion-segment-button value="chat">
              <ion-label>Chat</ion-label>
              @if (chatUnreadCount > 0) {
                <span class="segment-count">{{ chatBadgeLabel }}</span>
              }
            </ion-segment-button>
            <ion-segment-button value="actions"><ion-label>Actions</ion-label></ion-segment-button>
          </ion-segment>

          <!-- ============ CLIENT INFORMATION ============ -->
          @if (tab === 'info') {
            @if (detail?.pending_change_request; as request) {
              <div class="card" style="border-color: var(--app-primary)">
                <h3>{{ request.request_type === 'account_deletion' ? 'Account deletion requested' : 'Profile edit awaiting review' }}</h3>
                @if (request.client_note) {
                  <p class="sub">Client note: {{ request.client_note }}</p>
                }
                @if (request.request_type === 'profile_edit') {
                  <div class="kv-list">
                    @for (change of proposedChanges; track change.key) {
                      <div class="kv"><span>{{ change.label }}</span><strong>{{ change.from || '—' }} → {{ change.to }}</strong></div>
                    }
                  </div>
                }
                <div class="form-two" style="margin-top:.8rem">
                  <ion-button size="small" (click)="review('approve')" [disabled]="isReviewing">
                    <ion-icon slot="start" name="checkmark-outline" />Approve
                  </ion-button>
                  <ion-button size="small" color="danger" fill="outline" (click)="review('reject')" [disabled]="isReviewing">
                    <ion-icon slot="start" name="close-outline" />Reject
                  </ion-button>
                </div>
              </div>
            }

            <div class="card">
              <h3>Client information</h3>
              <div class="kv-list">
                <div class="kv"><span>Username</span><strong>{{ client.username }}</strong></div>
                <div class="kv"><span>Email</span><strong>{{ client.email || '—' }}</strong></div>
                <div class="kv"><span>Group</span><strong>{{ client.group_name }}</strong></div>
                <div class="kv"><span>Reference</span><strong>{{ client.reference_id }}</strong></div>
                <div class="kv"><span>Onboarding</span><strong>{{ onboardingLabel }}</strong></div>
                <div class="kv"><span>Joined</span><strong>{{ client.created_at | date: 'dd MMM yyyy' }}</strong></div>
                @for (field of registrationFields; track field.label) {
                  @if (answerFor(field)) {
                    <div class="kv"><span>{{ field.label }}</span><strong>{{ answerFor(field) }}</strong></div>
                  }
                }
              </div>
            </div>
          }

          <!-- ============ ACTIVITY ============ -->
          @if (tab === 'overview') {
            <div class="card">
              <h3>Follow-up schedules</h3>
              @for (reminder of reminders; track reminder.id) {
                <div class="check-row" [class.done]="reminder.status === 'done'">
                  <button type="button" class="tick" (click)="toggleReminder(reminder)">
                    @if (reminder.status === 'done') { ✓ }
                  </button>
                  <div class="check-main">
                    <strong>{{ reminder.title }}</strong>
                    <small>{{ reminder.date | date: 'dd MMM' }}{{ reminder.time ? ' · ' + reminder.time.slice(0, 5) : '' }}</small>
                  </div>
                  <ion-button size="small" fill="clear" color="danger" (click)="removeReminder(reminder)">
                    <ion-icon slot="icon-only" name="trash-outline" />
                  </ion-button>
                </div>
              } @empty {
                <p class="empty-note">No schedules for this client.</p>
              }
              @if (showReminderForm) {
                <div class="form-grid" style="margin-top:.75rem">
                  <label><span>Title</span><input [(ngModel)]="reminderTitle" placeholder="e.g. Progress check" /></label>
                  <div class="form-two">
                    <label><span>Date</span><input type="date" [(ngModel)]="reminderDate" /></label>
                    <label><span>Time</span><input type="time" [(ngModel)]="reminderTime" /></label>
                  </div>
                  <ion-button size="small" (click)="addReminder()" [disabled]="!reminderTitle.trim() || !reminderDate">Save schedule</ion-button>
                </div>
              } @else {
                <ion-button size="small" fill="outline" style="margin-top:.5rem" (click)="showReminderForm = true">
                  <ion-icon slot="start" name="add-outline" />Add schedule
                </ion-button>
              }
            </div>

            <div class="card">
              <h3>Client activity</h3>
              @for (entry of progress.slice(0, 6); track entry.id) {
                <div class="check-row done">
                  <div class="tick">✓</div>
                  <div class="check-main">
                    <strong>{{ entry.title }}</strong>
                    <small>{{ entry.date | date: 'dd MMM yyyy' }}{{ entry.status ? ' · ' + entry.status : '' }}</small>
                  </div>
                </div>
              } @empty {
                <p class="empty-note">No progress records yet.</p>
              }
            </div>

            <div class="card">
              <h3>Trainer notes <small style="font-weight:600;color:var(--app-muted)">(private)</small></h3>
              <div class="form-grid">
                <textarea [(ngModel)]="trainerNotes" placeholder="Private notes about this client…"></textarea>
              </div>
              <ion-button size="small" style="margin-top:.5rem" (click)="saveNotes()" [disabled]="isSavingNotes">
                {{ isSavingNotes ? 'Saving…' : 'Save notes' }}
              </ion-button>
            </div>
          }

          <!-- ============ TRACKING ============ -->
          @if (tab === 'tracking') {
            <div class="card">
              <h3>Assigned templates</h3>
              <div class="row-list">
                @for (assignment of assignments; track assignment.id) {
                  <a class="row-item" [routerLink]="['/trainer/tabs/clients', clientId, 'templates', assignment.id]">
                    <div class="row-main">
                      <h3>{{ assignment.template_name }}</h3>
                      <p>{{ assignment.template_cadence }} · assigned {{ assignment.assigned_at | date: 'dd MMM' }}</p>
                    </div>
                    <div class="row-side"><span class="pill info">View graphs</span></div>
                  </a>
                } @empty {
                  <p class="empty-note">No templates assigned yet.</p>
                }
              </div>

              @if (assignableTemplates.length) {
                <div class="form-grid" style="margin-top:.8rem">
                  <label>
                    <span>Assign a template</span>
                    <select [(ngModel)]="templateToAssign">
                      <option [ngValue]="0" disabled>Choose template</option>
                      @for (template of assignableTemplates; track template.id) {
                        <option [ngValue]="template.id">{{ template.name }}</option>
                      }
                    </select>
                  </label>
                  <ion-button size="small" (click)="assign()" [disabled]="!templateToAssign || isAssigning">Assign</ion-button>
                </div>
              }
            </div>
            <p class="hint-note">Open an assigned template to see its analytics graphs, entries, and sharing options.</p>
          }

          <!-- ============ CHAT ============ -->
          @if (tab === 'chat') {
            <div class="chat-scroll" style="margin-top:.5rem">
              @for (chatMessage of chatMessages; track chatMessage.id) {
                <div class="chat-bubble" [class.mine]="chatMessage.sender === 'trainer'" [class.theirs]="chatMessage.sender === 'client'">
                  {{ chatMessage.text }}
                  <time>{{ chatMessage.created_at | date: 'dd MMM HH:mm' }}</time>
                </div>
              } @empty {
                <p class="empty-note">No messages yet. Say hello!</p>
              }
            </div>
            <div style="display:flex;gap:.5rem;margin-top:.5rem">
              <input
                [(ngModel)]="chatDraft"
                (keyup.enter)="sendChat()"
                placeholder="Message {{ client.first_name }}…"
                style="flex:1;border:1px solid var(--app-border);border-radius:999px;padding:.6rem .9rem;background:var(--app-surface);color:var(--app-text)"
              />
              <ion-button (click)="sendChat()" [disabled]="!chatDraft.trim()">
                <ion-icon slot="icon-only" name="send-outline" />
              </ion-button>
            </div>
          }

          <!-- ============ ACTIONS ============ -->
          @if (tab === 'actions') {
            <div class="menu-card">
              <button type="button" (click)="toggleActive()">
                {{ client.is_active ? 'Deactivate account' : 'Activate account' }}
                <span class="chev">›</span>
              </button>
              <button type="button" (click)="resetPassword()">Reset password<span class="chev">›</span></button>
              <button type="button" (click)="resetClient()">Reset client data<span class="chev">›</span></button>
              <button type="button" class="danger" (click)="deleteClient()">Delete client<span class="chev">›</span></button>
            </div>
            @if (temporaryPassword) {
              <div class="card">
                <h3>Temporary password</h3>
                <p class="sub">Share this with the client — it must be changed at next login.</p>
                <strong style="font-size:1.2rem">{{ temporaryPassword }}</strong>
              </div>
            }
            <p class="hint-note">Deactivating blocks login without deleting data. Reset clears tracking history. Delete is permanent.</p>
          }
        }
        <div class="bottom-space"></div>
      </div>
    </ion-content>
  `,
  styles: [`
    .detail-tabs { margin-top: .8rem; }
    .detail-tabs ion-segment-button { min-width: 5.25rem; }
    .segment-count { position: absolute; top: .16rem; right: .28rem; display: inline-grid; min-width: 1.2rem; height: 1.2rem; place-items: center; border-radius: 999px; padding: 0 .28rem; background: #e11d48; color: #fff; font-size: .61rem; font-weight: 800; }
  `]
})
export class ClientDetailPage implements OnInit, OnDestroy {
  private readonly route = inject(ActivatedRoute);
  private readonly formsGroupsApi = inject(FormsGroupsApiService);
  private readonly templatesApi = inject(TemplatesApiService);
  private readonly chatApi = inject(ChatApiService);
  private readonly alertController = inject(AlertController);
  private readonly toastController = inject(ToastController);

  clientId = 0;
  tab: DetailTab = 'info';
  detail: ClientAccessDetailResponse | null = null;
  client: ClientAccessRecord | null = null;
  registrationFields: DynamicField[] = [];
  reminders: ClientReminder[] = [];
  progress: ProgressEntry[] = [];
  assignments: TemplateAssignmentRecord[] = [];
  allTemplates: TrackingTemplateRecord[] = [];
  chatMessages: ChatMessageRecord[] = [];
  chatDraft = '';
  chatUnreadCount = 0;
  trainerNotes = '';
  message = '';
  isSavingNotes = false;
  isReviewing = false;
  isAssigning = false;
  templateToAssign = 0;
  temporaryPassword = '';
  showReminderForm = false;
  reminderTitle = '';
  reminderDate = '';
  reminderTime = '';

  private chatPoll: ReturnType<typeof setInterval> | null = null;
  private unreadPoll: ReturnType<typeof setInterval> | null = null;

  constructor() {
    addIcons({ sendOutline, checkmarkOutline, closeOutline, addOutline, trashOutline });
  }

  get initials(): string {
    return `${this.client?.first_name?.[0] || ''}${this.client?.last_name?.[0] || ''}`.toUpperCase() || 'C';
  }

  get onboardingLabel(): string {
    switch (this.client?.onboarding_method) {
      case 'manual':
        return 'Added manually';
      case 'group_registration':
        return 'Group registration';
      default:
        return 'Public enquiry';
    }
  }

  get chatBadgeLabel(): string {
    return this.chatUnreadCount > 99 ? '99+' : String(this.chatUnreadCount);
  }

  get assignableTemplates(): TrackingTemplateRecord[] {
    const assignedIds = new Set(this.assignments.map((assignment) => assignment.template_id));
    return this.allTemplates.filter((template) => !assignedIds.has(template.id));
  }

  get proposedChanges(): Array<{ key: string; label: string; from: string; to: string }> {
    const request = this.detail?.pending_change_request;

    if (!request || !this.client) {
      return [];
    }

    return Object.entries(request.proposed_answers).map(([key, value]) => ({
      key,
      label: this.labelFor(key),
      from: String(this.client?.registration_answers?.[key] ?? ''),
      to: String(value)
    }));
  }

  ngOnInit(): void {
    this.clientId = Number(this.route.snapshot.paramMap.get('clientId'));
    this.load();
    this.loadUnreadMessages();
    this.chatPoll = setInterval(() => {
      if (this.tab === 'chat') {
        this.loadChat();
      }
    }, 8000);
    this.unreadPoll = setInterval(() => this.loadUnreadMessages(), 5000);
  }

  ngOnDestroy(): void {
    if (this.chatPoll) {
      clearInterval(this.chatPoll);
    }
    if (this.unreadPoll) {
      clearInterval(this.unreadPoll);
    }
  }

  answerFor(field: DynamicField): string {
    const key = field.key || field.label;
    return String(this.client?.registration_answers?.[key] ?? '');
  }

  toggleReminder(reminder: ClientReminder): void {
    const status = reminder.status === 'done' ? 'pending' : 'done';
    this.formsGroupsApi.updateReminder(reminder.id, { status }).subscribe({
      next: (response) => {
        this.reminders = this.reminders.map((item) => (item.id === reminder.id ? response.reminder : item));
      }
    });
  }

  removeReminder(reminder: ClientReminder): void {
    this.formsGroupsApi.deleteReminder(reminder.id).subscribe({
      next: () => (this.reminders = this.reminders.filter((item) => item.id !== reminder.id))
    });
  }

  addReminder(): void {
    this.formsGroupsApi
      .createClientReminder(this.clientId, {
        title: this.reminderTitle.trim(),
        date: this.reminderDate,
        time: this.reminderTime || null,
        notes: '',
        notify_trainer: true
      })
      .subscribe({
        next: (response) => {
          this.reminders = [...this.reminders, response.reminder];
          this.showReminderForm = false;
          this.reminderTitle = '';
          this.reminderDate = '';
          this.reminderTime = '';
        },
        error: () => this.toast('Could not save the schedule.')
      });
  }

  saveNotes(): void {
    this.isSavingNotes = true;
    this.formsGroupsApi.saveTrainerNotes(this.clientId, this.trainerNotes).subscribe({
      next: () => {
        this.isSavingNotes = false;
        this.toast('Notes saved.');
      },
      error: () => {
        this.isSavingNotes = false;
        this.toast('Could not save notes.');
      }
    });
  }

  review(action: 'approve' | 'reject'): void {
    const request = this.detail?.pending_change_request;

    if (!request) {
      return;
    }

    this.isReviewing = true;
    this.formsGroupsApi.reviewChangeRequest(this.clientId, request.id, action).subscribe({
      next: (response) => {
        this.isReviewing = false;

        if (this.detail) {
          this.detail.pending_change_request = null;
        }

        this.client = response.client;
        this.toast(action === 'approve' ? 'Changes approved.' : 'Request rejected.');
      },
      error: () => {
        this.isReviewing = false;
        this.toast('Could not complete the review.');
      }
    });
  }

  assign(): void {
    if (!this.templateToAssign) {
      return;
    }

    this.isAssigning = true;
    this.templatesApi.assignTemplate(this.clientId, this.templateToAssign).subscribe({
      next: (response) => {
        this.assignments = [...this.assignments, response.assignment];
        this.templateToAssign = 0;
        this.isAssigning = false;
      },
      error: () => {
        this.isAssigning = false;
        this.toast('Could not assign the template.');
      }
    });
  }

  sendChat(): void {
    const text = this.chatDraft.trim();

    if (!text) {
      return;
    }

    this.chatDraft = '';
    this.chatApi.sendTrainerMessage(this.clientId, text).subscribe({
      next: (response) => (this.chatMessages = [...this.chatMessages, response.chat_message]),
      error: () => this.toast('Message failed to send.')
    });
  }

  async toggleActive(): Promise<void> {
    if (!this.client) {
      return;
    }

    const target = !this.client.is_active;
    const alert = await this.alertController.create({
      header: target ? 'Activate account?' : 'Deactivate account?',
      message: target ? 'The client will be able to log in again.' : 'The client will no longer be able to log in.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: target ? 'Activate' : 'Deactivate',
          handler: () => {
            this.formsGroupsApi.updateClientStatus(this.clientId, target).subscribe({
              next: (response) => (this.client = response.client)
            });
          }
        }
      ]
    });
    await alert.present();
  }

  async resetPassword(): Promise<void> {
    // Option A: the trainer defines the temporary password (same as manual
    // creation). A generated suggestion is prefilled.
    const suggested = this.generateTemporaryPassword();
    const alert = await this.alertController.create({
      header: 'Reset password',
      message: 'Set the temporary password (min 8 characters, 1 special). The current password stops working immediately.',
      inputs: [{ name: 'password', type: 'text', value: suggested, placeholder: 'Temporary password' }],
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Reset',
          handler: (values: { password?: string }) => {
            const temporaryPassword = (values.password || '').trim() || suggested;
            this.formsGroupsApi.resetClientPassword(this.clientId, temporaryPassword).subscribe({
              next: (response) => (this.temporaryPassword = response.temporary_password),
              error: () => this.toast('Could not reset the password. Check password strength.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  private generateTemporaryPassword(): string {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    const random = new Uint32Array(9);
    crypto.getRandomValues(random);
    let value = '';
    random.forEach((n) => (value += alphabet[n % alphabet.length]));
    return `${value.slice(0, 8)}!${value.slice(8)}`;
  }

  async resetClient(): Promise<void> {
    const alert = await this.alertController.create({
      header: 'Reset client data?',
      message: 'This clears the client’s tracking history. Their account and profile stay.',
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Reset data',
          role: 'destructive',
          handler: () => {
            this.formsGroupsApi.resetClient(this.clientId).subscribe({
              next: () => this.toast('Client data reset.'),
              error: () => this.toast('Could not reset the client.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  async deleteClient(): Promise<void> {
    const alert = await this.alertController.create({
      header: 'Delete client permanently?',
      message: `${this.client?.first_name} ${this.client?.last_name} and all their data will be removed. This cannot be undone.`,
      buttons: [
        { text: 'Cancel', role: 'cancel' },
        {
          text: 'Delete',
          role: 'destructive',
          handler: () => {
            this.formsGroupsApi.deleteClient(this.clientId).subscribe({
              next: () => window.history.back(),
              error: () => this.toast('Could not delete the client.')
            });
          }
        }
      ]
    });
    await alert.present();
  }

  private load(): void {
    this.formsGroupsApi.getClientProfile(this.clientId).subscribe({
      next: (detail) => {
        this.detail = detail;
        this.client = detail.client;
        this.registrationFields = detail.registration_fields || [];
        this.trainerNotes = detail.trainer_notes || '';
      },
      error: () => (this.message = 'Could not load this client.')
    });

    this.formsGroupsApi.getClientReminders(this.clientId).subscribe({
      next: (response) => (this.reminders = response.reminders),
      error: () => (this.reminders = [])
    });

    this.formsGroupsApi.getClientProgress(this.clientId).subscribe({
      next: (response) => (this.progress = response.progress),
      error: () => (this.progress = [])
    });

    this.templatesApi.getAssignments(this.clientId).subscribe({
      next: (response) => (this.assignments = response.assignments),
      error: () => (this.assignments = [])
    });

    this.templatesApi.getTemplates().subscribe({
      next: (response) => (this.allTemplates = response.templates),
      error: () => (this.allTemplates = [])
    });

    this.loadChat();
  }

  private loadChat(): void {
    const lastId = this.chatMessages.length ? this.chatMessages[this.chatMessages.length - 1].id : undefined;
    this.chatApi.getTrainerMessages(this.clientId, lastId).subscribe({
      next: (response) => {
        if (response.messages.length) {
          this.chatMessages = [...this.chatMessages, ...response.messages];
        }
      },
      error: () => undefined
    });
  }

  private loadUnreadMessages(): void {
    this.chatApi.getTrainerUnreadCounts().subscribe({
      next: (summary) => (this.chatUnreadCount = summary.by_client[String(this.clientId)] || 0),
      error: () => (this.chatUnreadCount = 0)
    });
  }

  private labelFor(key: string): string {
    const field = this.registrationFields.find((item) => (item.key || item.label) === key);
    return field?.label || key.replace(/_/g, ' ');
  }

  private async toast(text: string): Promise<void> {
    const toast = await this.toastController.create({ message: text, duration: 1800, position: 'bottom' });
    await toast.present();
  }
}
