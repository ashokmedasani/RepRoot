import { Component, OnInit, inject } from '@angular/core';
import { DatePipe } from '@angular/common';
import { RouterLink } from '@angular/router';
import { IonBadge, IonButton, IonContent, IonHeader, IonItem, IonLabel, IonList, IonRefresher, IonRefresherContent, IonTitle, IonToolbar } from '@ionic/angular/standalone';
import { FormsGroupsApiService, FormsGroupsOverview } from '../../../core/api/forms-groups-api.service';

@Component({ selector: 'app-trainer-forms-groups', standalone: true, imports: [DatePipe, RouterLink, IonBadge, IonButton, IonContent, IonHeader, IonItem, IonLabel, IonList, IonRefresher, IonRefresherContent, IonTitle, IonToolbar], template: `
  <ion-header><ion-toolbar><ion-title>Forms & Groups</ion-title></ion-toolbar></ion-header>
  <ion-content><ion-refresher slot="fixed" (ionRefresh)="refresh($event)"><ion-refresher-content /></ion-refresher><div class="page-pad">
    @if(message){<p class="error-text">{{message}}</p>}
    @if(overview; as data){
      <div class="kpi-grid"><div class="kpi-tile"><span>Groups</span><strong>{{data.groups.length}} / {{data.max_groups}}</strong></div><div class="kpi-tile"><span>Pending Forms</span><strong>{{data.pending_forms.length}}</strong></div></div>
      <div class="section-head"><h2 class="section-title">Groups</h2><ion-button size="small" routerLink="/trainer/tabs/manage">Create</ion-button></div>
      <ion-list inset>@for(group of data.groups; track group.id){<ion-item button detail [routerLink]="['/trainer/tabs/clients']" [queryParams]="{group: group.id}"><ion-label><h3>{{group.name}}</h3><p>{{group.description || 'Client group'}} · {{group.has_registration_form ? 'Registration ready' : 'Registration form needed'}}</p></ion-label></ion-item>}@empty{<ion-item lines="none"><ion-label color="medium">No groups created yet.</ion-label></ion-item>}</ion-list>
      <h2 class="section-title">Incoming Requests</h2><ion-list inset>@for(request of data.pending_forms; track request.id){<ion-item><ion-label><h3>{{request.applicant_name}}</h3><p>{{request.email}} · {{request.submitted_at | date:'mediumDate'}}</p></ion-label><ion-badge slot="end" color="warning">Pending</ion-badge><ion-button slot="end" size="small" fill="clear" color="danger" (click)="remove(request.id)">Delete</ion-button></ion-item>}@empty{<ion-item lines="none"><ion-label color="medium">No pending requests.</ion-label></ion-item>}</ion-list>
      <h2 class="section-title">Lead form</h2><ion-list inset><ion-item><ion-label><h3>{{data.lead_form?.title || 'No lead form yet'}}</h3><p>{{data.has_lead_form ? 'Public form is ready to share.' : 'Create a form from Manage.'}}</p></ion-label><ion-button slot="end" size="small" routerLink="/trainer/tabs/manage">Open</ion-button></ion-item></ion-list>
    }
  </div></ion-content>` })
export class TrainerFormsGroupsPage implements OnInit {
  private readonly api = inject(FormsGroupsApiService); overview: FormsGroupsOverview | null = null; message = '';
  ngOnInit(): void { this.load(); }
  refresh(event: CustomEvent): void { this.load(() => (event.target as HTMLIonRefresherElement).complete()); }
  remove(id: number): void { this.api.deletePendingForm(id).subscribe({ next: () => this.load(), error: () => this.message = 'Request could not be removed.' }); }
  private load(done?: () => void): void { this.api.getOverview().subscribe({ next: value => { this.overview = value; this.message = ''; done?.(); }, error: () => { this.message = 'Could not load forms and groups.'; done?.(); } }); }
}
