import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AdminPortalApiService } from '../../../core/api/admin-portal-api.service';
import { formatApiError } from '../../../shared/utils/ui-helpers';

@Component({selector:'app-admin-login',standalone:true,imports:[FormsModule],template:`
  <main class="login-page"><section class="login-card"><div class="brand"><span>CF</span><div><strong>CoachFlow</strong><small>Internal Admin Portal</small></div></div><p class="eyebrow">Authorized staff only</p><h1>Admin sign in</h1><p class="intro">Use your internal staff credentials. Trainer and client accounts cannot access this portal.</p>
  <form (ngSubmit)="submit()"><label>Work email or username<input name="identifier" [(ngModel)]="identifier" autocomplete="username" required></label><label>Password<input name="password" [(ngModel)]="password" type="password" autocomplete="current-password" required></label>@if(message){<p class="error">{{message}}</p>}<button class="primary-action" [disabled]="loading">{{loading?'Signing in…':'Sign In'}}</button></form><p class="security">Access is permission-controlled and administrative activity is audited.</p></section></main>`,styles:[`
  :host{display:block;min-height:100vh;background:radial-gradient(circle at 15% 15%,var(--app-primary-soft),transparent 30rem),var(--app-bg)}.login-page{display:grid;min-height:100vh;place-items:center;padding:1.5rem}.login-card{width:min(29rem,100%);border:1px solid var(--app-border);border-radius:1rem;padding:2rem;background:var(--app-surface);box-shadow:var(--app-shadow-lg)}.brand{display:flex;gap:.75rem;align-items:center;margin-bottom:2.2rem}.brand>span{display:grid;width:2.5rem;height:2.5rem;place-items:center;border-radius:.75rem;background:var(--app-primary);color:white;font-weight:850}.brand div{display:grid}.brand small{color:var(--app-muted)}h1{margin:0;font-size:2rem}.intro,.security{color:var(--app-muted)}form{display:grid;gap:1rem;margin-top:1.5rem}label{display:grid;gap:.4rem;font-weight:700}.primary-action{margin-top:.25rem}.error{margin:0;border-radius:.6rem;padding:.7rem;background:#fff0ef;color:#b42318}.security{margin:1.4rem 0 0;font-size:.78rem}
  `]})
export class AdminLoginComponent {
  identifier=''; password=''; message=''; loading=false;
  constructor(private api:AdminPortalApiService,private router:Router){}
  submit():void{if(!this.identifier||!this.password)return;this.loading=true;this.message='';this.api.login(this.identifier,this.password).subscribe({next:()=>void this.router.navigate(['/admin-portal/dashboard']),error:(error)=>{this.loading=false;this.message=formatApiError(error,'Sign in could not be completed.')}})}
}
