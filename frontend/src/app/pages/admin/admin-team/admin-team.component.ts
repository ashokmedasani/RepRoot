import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AdminPermissionRecord, AdminPortalApiService, AdminTeamMember, AdminTeamResponse } from '@core/api/admin-portal-api.service';
import { AdminPageShellComponent } from '@admin-shared/admin-page-shell/admin-page-shell.component';
import { formatApiError } from '@shared/utils/ui-helpers';

@Component({
  selector: 'app-admin-team', standalone: true, imports: [AdminPageShellComponent, FormsModule],
  template: `<app-admin-page-shell title="Team and Access" subtitle="Owner-controlled departments, roles and least-privilege access." activeSection="team">
    @if(message){<p class="message">{{message}}</p>}
    @if(data){
      <section class="owner"><div><small>Protected account</small><strong>{{data.viewer.full_name || data.viewer.username}}</strong></div><span>Owner authority cannot be delegated or edited by staff.</span></section>
      <section class="panel"><h2>Add team member</h2><p>Give each person only the department and actions needed for their work. They must replace the temporary password at first sign-in.</p>
        <div class="fields"><input placeholder="First name" [(ngModel)]="form.first_name"><input placeholder="Last name" [(ngModel)]="form.last_name"><input placeholder="Username" [(ngModel)]="form.username"><input type="email" placeholder="Work email" [(ngModel)]="form.email"><input type="password" placeholder="Temporary password (10+ characters)" [(ngModel)]="form.password">
          <select [(ngModel)]="form.department">@for(department of creatableDepartments();track department.code){<option [value]="department.code">{{department.name}}</option>}</select>
          <select [(ngModel)]="form.authority_level"><option [ngValue]="10">Staff</option><option [ngValue]="50">Department Admin</option></select>
          <select [(ngModel)]="form.role_slug" (change)="applyRoleDefaults()">@for(role of data.roles;track role.slug){<option [value]="role.slug">{{role.name}}</option>}</select>
        </div>
        <div class="permissions">@for(section of sections();track section){<fieldset><legend>{{section}}</legend>@for(permission of permissionsFor(section);track permission.code){<label><input type="checkbox" [checked]="form.permissions.includes(permission.code)" (change)="toggle(permission.code)"><span>{{permission.name}}<small>{{permission.code}}</small></span></label>}</fieldset>}</div>
        <button class="primary" (click)="create()">Create staff account</button>
      </section>
      <section class="panel"><h2>Current team</h2>@for(member of data.staff;track member.staff_id){<article [class.protected]="member.is_owner"><div><strong>{{member.full_name||member.username}} @if(member.is_owner){<em>OWNER</em>}</strong><small>{{member.email}} · {{member.staff_id}}</small><small>{{member.department_label}} · {{authorityLabel(member.authority_level)}} @if(member.must_change_password){· Password setup pending}</small></div><span>{{member.role}}</span><span>{{member.status}}</span>@if(!member.is_owner){<button (click)="selectMember(member)">Manage access</button>}@else{<span>Protected</span>}</article>}</section>
      @if(editing){<div class="overlay"><section class="dialog"><header><div><h2>{{editing.full_name||editing.username}}</h2><small>{{editing.department_label}} · {{authorityLabel(editing.authority_level)}}</small></div><button (click)="editing=undefined">Close</button></header><label>Role<select [(ngModel)]="editing.role_slug">@for(role of data.roles;track role.slug){<option [value]="role.slug">{{role.name}}</option>}</select></label><label>Status<select [(ngModel)]="editing.status"><option value="ACTIVE">Active</option><option value="DISABLED">Disabled</option></select></label><div class="permissions">@for(section of sections();track section){<fieldset><legend>{{section}}</legend>@for(permission of permissionsFor(section);track permission.code){<label><input type="checkbox" [checked]="editing.permissions.includes(permission.code)" (change)="toggleEdit(permission.code)">{{permission.name}}</label>}</fieldset>}</div><button class="primary" (click)="saveMember()">Save access</button></section></div>}
    }
  </app-admin-page-shell>`,
  styles: [`.message,.panel,.owner{border:1px solid var(--app-border);border-radius:1rem;padding:1rem;background:var(--app-surface);margin-bottom:1rem}.owner{display:flex;justify-content:space-between;gap:1rem;border-color:var(--app-primary);background:var(--app-primary-soft)}.owner div{display:grid}.fields,.permissions{display:grid;grid-template-columns:repeat(3,1fr);gap:.7rem;margin:1rem 0}.fields input,.fields select,.dialog select{min-height:2.5rem;border:1px solid var(--app-border);border-radius:.6rem;padding:.5rem;background:var(--app-surface);color:var(--app-text)}fieldset{display:grid;gap:.45rem;border:1px solid var(--app-border);border-radius:.7rem;padding:.7rem}fieldset label{display:flex;gap:.5rem}fieldset span{display:grid}small{color:var(--app-muted)}button{border:1px solid var(--app-border);border-radius:.6rem;padding:.55rem .75rem;background:var(--app-surface);color:var(--app-text);font-weight:700}.primary{background:var(--app-primary);color:#fff;border:0}.panel article{display:grid;grid-template-columns:1fr auto auto auto;gap:.7rem;align-items:center;padding:.75rem 0;border-top:1px solid var(--app-border)}.panel article div{display:grid}.panel article.protected{border-left:.25rem solid var(--app-primary);padding-left:.75rem}.panel em{font-size:.65rem;font-style:normal;border-radius:1rem;padding:.2rem .4rem;background:var(--app-primary);color:#fff}.overlay{position:fixed;inset:0;z-index:50;display:grid;place-items:center;padding:1rem;background:rgb(15 23 42/.5)}.dialog{width:min(62rem,100%);max-height:90vh;overflow:auto;border-radius:1rem;padding:1rem;background:var(--app-surface)}.dialog header{display:flex;justify-content:space-between}.dialog>label{display:grid;margin:.5rem 0}@media(max-width:850px){.fields,.permissions{grid-template-columns:1fr}.panel article{grid-template-columns:1fr auto}.owner{display:grid}}`]
})
export class AdminTeamComponent implements OnInit {
  data?: AdminTeamResponse; message = ''; editing?: AdminTeamMember;
  form = { first_name:'', last_name:'', username:'', email:'', password:'', department:'OPERATIONS', authority_level:10, role_slug:'support-agent', permissions:[] as string[] };
  constructor(private api: AdminPortalApiService) {}
  ngOnInit(): void { this.load(); }
  load(): void { this.api.getTeam().subscribe({next:v=>{this.data=v;this.form.department=this.creatableDepartments()[0]?.code||v.viewer.department;this.applyRoleDefaults();},error:e=>this.message=formatApiError(e,'Team could not be loaded.')}); }
  creatableDepartments(){ return (this.data?.departments||[]).filter(d=>d.code!=='OWNER' && (this.data?.viewer.is_owner || d.code===this.data?.viewer.department)); }
  authorityLabel(level:number): string { return level >= 100 ? 'Owner' : level >= 50 ? 'Department Admin' : 'Staff'; }
  sections(): string[]{ return [...new Set((this.data?.permissions||[]).map(p=>p.section))]; }
  permissionsFor(s:string):AdminPermissionRecord[]{ return(this.data?.permissions||[]).filter(p=>p.section===s); }
  applyRoleDefaults():void{ this.form.permissions=this.form.role_slug==='super-admin'?(this.data?.permissions||[]).map(p=>p.code):[]; }
  toggle(c:string):void{ this.form.permissions=this.form.permissions.includes(c)?this.form.permissions.filter(v=>v!==c):[...this.form.permissions,c]; }
  create():void{ this.api.createTeamMember(this.form).subscribe({next:r=>{this.message=r.message;this.form={first_name:'',last_name:'',username:'',email:'',password:'',department:this.creatableDepartments()[0]?.code||'OPERATIONS',authority_level:10,role_slug:'support-agent',permissions:[]};this.load();},error:e=>this.message=formatApiError(e,'Could not create team member.')}); }
  selectMember(m:AdminTeamMember):void{ this.editing={...m,permissions:[...m.permissions]}; }
  toggleEdit(c:string):void{ if(this.editing)this.editing.permissions=this.editing.permissions.includes(c)?this.editing.permissions.filter(v=>v!==c):[...this.editing.permissions,c]; }
  saveMember():void{ if(this.editing)this.api.updateTeamMember(this.editing.staff_id,{role_slug:this.editing.role_slug,status:this.editing.status,permissions:this.editing.permissions}).subscribe({next:r=>{this.message=r.message;this.editing=undefined;this.load();},error:e=>this.message=formatApiError(e,'Could not update access.')}); }
}
