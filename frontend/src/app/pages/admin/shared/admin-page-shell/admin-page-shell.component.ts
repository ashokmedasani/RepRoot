import { Component, Input, inject } from '@angular/core';
import { Router, RouterLink } from '@angular/router';

import { AdminPortalApiService } from '@core/api/admin-portal-api.service';

type AdminSection = 'dashboard' | 'finance' | 'audit' | 'lifecycle' | 'errors-web' | 'errors-mobile';

@Component({
  selector: 'app-admin-page-shell',
  standalone: true,
  imports: [RouterLink],
  template: `
    <div class="admin-shell">
      <aside class="admin-sidebar">
        <a class="admin-brand" routerLink="/admin-portal/dashboard"><span><img src="/brand/reproot/mark.png" alt=""></span><strong><span class="admin-brand__rep">Rep</span><span class="admin-brand__root">Root</span></strong><small>Internal</small></a>
        <nav aria-label="Admin Portal navigation">
          <a routerLink="/admin-portal/dashboard" [class.active]="activeSection === 'dashboard'"><span>▦</span>Dashboard</a>
          @if (can('admin.finance.view')) { <a routerLink="/admin-portal/finance" [class.active]="activeSection === 'finance'"><span>$</span>Finance</a> }
          @if (can('admin.lifecycle.view')) { <a routerLink="/admin-portal/account-lifecycle" [class.active]="activeSection === 'lifecycle'"><span>R</span>Recycle Center</a> }
          @if (can('admin.audit.view')) { <a routerLink="/admin-portal/audit-logs" [class.active]="activeSection === 'audit'"><span>≡</span>Audit Logs</a> }
          @if (can('admin.errors.list')) { <a routerLink="/admin-portal/errors/web" [class.active]="activeSection === 'errors-web'"><span>⚠</span>Error Logs · Web</a> }
          @if (can('admin.errors.list')) { <a routerLink="/admin-portal/errors/mobile" [class.active]="activeSection === 'errors-mobile'"><span>⚠</span>Error Logs · Mobile</a> }
        </nav>
        <div class="staff-card"><small>{{ staff?.staff_id }}</small><strong>{{ staff?.full_name }}</strong><span>{{ staff?.role }}</span></div>
        <button type="button" class="signout" (click)="signOut()">Sign Out</button>
      </aside>
      <main class="admin-main">
        <header><div><p class="eyebrow">Admin Portal</p><h1>{{ title }}</h1><p>{{ subtitle }}</p></div><ng-content select="[page-actions]"></ng-content></header>
        <section class="admin-content"><ng-content></ng-content></section>
      </main>
    </div>
  `,
  styles: [`
    .admin-shell{display:grid;grid-template-columns:16.5rem minmax(0,1fr);min-height:100vh;background:var(--app-bg)}
    .admin-sidebar{position:sticky;top:0;display:flex;flex-direction:column;height:100vh;border-right:1px solid var(--app-border);padding:1.2rem;background:var(--app-surface)}
    .admin-brand{display:grid;grid-template-columns:2.3rem 1fr;gap:0 .65rem;align-items:center;margin-bottom:2rem;color:var(--app-text);text-decoration:none}.admin-brand>span{grid-row:1/3;display:grid;width:2.3rem;height:2.3rem;place-items:center;border-radius:.7rem;background:#ffffff;overflow:hidden;box-shadow:0 4px 10px rgba(11,125,227,0.25)}.admin-brand>span img{width:100%;height:100%;object-fit:contain}.admin-brand small{color:var(--app-muted);font-size:.68rem;text-transform:uppercase;letter-spacing:.12em}.admin-brand__rep{color:var(--app-text)}.admin-brand__root{color:var(--app-primary)}
    nav{display:grid;gap:.35rem}nav a{display:flex;align-items:center;gap:.75rem;border-radius:.65rem;padding:.72rem .8rem;color:var(--app-muted);font-weight:650;text-decoration:none}nav a span{display:grid;width:1.3rem;place-items:center}nav a:hover,nav a.active{background:var(--app-primary-soft);color:var(--app-primary-strong)}
    .staff-card{display:grid;gap:.15rem;margin-top:auto;border:1px solid var(--app-border);border-radius:.75rem;padding:.85rem}.staff-card small,.staff-card span{color:var(--app-muted);font-size:.72rem}.signout{margin-top:.65rem;border:1px solid var(--app-border);border-radius:.65rem;padding:.7rem;background:var(--app-surface);color:var(--app-text);font-weight:700}
    .admin-main{min-width:0;padding:2rem clamp(1.25rem,4vw,3.5rem)}header{display:flex;align-items:flex-end;justify-content:space-between;gap:1rem;max-width:80rem;margin:0 auto;border-bottom:1px solid var(--app-border);padding-bottom:1.1rem}h1{margin:0;font-size:var(--app-h1-page)}header p:not(.eyebrow){margin:.35rem 0 0;color:var(--app-muted)}.admin-content{max-width:80rem;margin:1.5rem auto 0}
    @media(max-width:800px){.admin-shell{grid-template-columns:1fr}.admin-sidebar{position:static;height:auto}.admin-sidebar nav{grid-template-columns:repeat(3,1fr)}.staff-card{margin-top:1rem}.admin-main{padding:1.25rem}.admin-sidebar nav a{justify-content:center}.admin-sidebar nav a span{display:none}}
  `]
})
export class AdminPageShellComponent {
  private readonly api = inject(AdminPortalApiService);
  private readonly router = inject(Router);

  @Input({ required: true }) title = '';
  @Input() subtitle = '';
  @Input() activeSection: AdminSection = 'dashboard';
  readonly staff = this.api.currentStaff();

  can(permission: string): boolean { return this.api.hasPermission(permission); }
  signOut(): void { this.api.logout().subscribe({ next: () => this.finish(), error: () => this.finish() }); }
  private finish(): void { this.api.clearSession(); void this.router.navigate(['/admin-portal/login']); }
}
