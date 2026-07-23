from django.db import migrations, models
import django.db.models.deletion
import admin_portal.models


def seed_operations_permissions(apps, schema_editor):
  Permission=apps.get_model('admin_portal','AdminPermission'); Role=apps.get_model('admin_portal','AdminRole'); Link=apps.get_model('admin_portal','AdminRolePermission')
  records={
    'admin.operations.view':('View product and storage operations','Operations'),
    'admin.users.view':('Search user directory and support metadata','Users'),
    'admin.communications.view':('View notification and delivery health','Communications'),
    'admin.health.view':('View application health and configured services','Technical'),
    'admin.support.access_request':('Request consent-based support access','Support'),
    'admin.support.actions':('Run approved support actions','Support'),
    'admin.search.use':('Use internal global search','Operations'),
  }
  objects={}
  for code,(name,section) in records.items(): objects[code],_=Permission.objects.update_or_create(code=code,defaults={'name':name,'section':section})
  super_role=Role.objects.get(slug='super-admin')
  for permission in objects.values(): Link.objects.update_or_create(role=super_role,permission=permission,defaults={'allowed':True})
  grants={'support-admin':{'admin.users.view','admin.support.access_request','admin.support.actions','admin.search.use'},'support-agent':{'admin.users.view','admin.support.access_request','admin.search.use'},'operations-admin':{'admin.operations.view','admin.users.view','admin.communications.view','admin.health.view','admin.search.use'},'technical-admin':{'admin.operations.view','admin.communications.view','admin.health.view','admin.search.use'},'security-admin':{'admin.users.view','admin.health.view','admin.search.use'},'read-only-analyst':{'admin.operations.view'}}
  for slug,codes in grants.items():
    role=Role.objects.filter(slug=slug).first()
    if role:
      for code in codes: Link.objects.update_or_create(role=role,permission=objects[code],defaults={'allowed':True})


class Migration(migrations.Migration):
  dependencies=[('accounts','0016_shared_notifications'),('admin_portal','0006_owner_and_staff_security')]
  operations=[
    migrations.CreateModel(name='OperationEvent',fields=[('id',models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name='ID')),('event_type',models.CharField(db_index=True,max_length=100)),('module',models.CharField(db_index=True,max_length=40)),('actor_type',models.CharField(choices=[('professional','Professional'),('client','Client'),('system','System')],db_index=True,max_length=20)),('professional_reference',models.CharField(blank=True,db_index=True,max_length=24)),('client_reference',models.CharField(blank=True,db_index=True,max_length=32)),('plan_tier',models.CharField(blank=True,db_index=True,max_length=20)),('platform',models.CharField(blank=True,db_index=True,max_length=20)),('success',models.BooleanField(db_index=True,default=True)),('duration_ms',models.PositiveIntegerField(blank=True,null=True)),('metadata',models.JSONField(blank=True,default=dict)),('occurred_at',models.DateTimeField(auto_now_add=True,db_index=True))],options={'db_table':'operation_events','ordering':['-occurred_at'],'indexes':[models.Index(fields=['module','occurred_at'],name='operation_module_time_idx')]}),
    migrations.CreateModel(name='SupportAccessGrant',fields=[('id',models.BigAutoField(auto_created=True,primary_key=True,serialize=False,verbose_name='ID')),('access_id',models.CharField(default=admin_portal.models.support_access_reference,editable=False,max_length=24,unique=True)),('scope',models.CharField(choices=[('metadata','Account metadata'),('module','Specific module'),('readonly','Read-only account view')],default='metadata',max_length=16)),('module',models.CharField(blank=True,max_length=40)),('reason',models.TextField()),('status',models.CharField(choices=[('requested','Requested'),('approved','Approved'),('revoked','Revoked'),('expired','Expired')],db_index=True,default='requested',max_length=12)),('consent_reference',models.CharField(blank=True,max_length=120)),('approved_at',models.DateTimeField(blank=True,null=True)),('expires_at',models.DateTimeField(blank=True,db_index=True,null=True)),('revoked_at',models.DateTimeField(blank=True,null=True)),('created_at',models.DateTimeField(auto_now_add=True)),('incident',models.ForeignKey(on_delete=django.db.models.deletion.CASCADE,related_name='access_grants',to='accounts.supportincident')),('requested_by',models.ForeignKey(on_delete=django.db.models.deletion.PROTECT,related_name='requested_support_access',to='admin_portal.adminstaffprofile'))],options={'db_table':'support_access_grants','ordering':['-created_at']}),
    migrations.RunPython(seed_operations_permissions,migrations.RunPython.noop),
  ]
