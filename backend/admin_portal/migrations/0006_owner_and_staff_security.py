from django.db import migrations, models


def configure_owner_and_hierarchy(apps, schema_editor):
  Staff = apps.get_model('admin_portal', 'AdminStaffProfile')
  Role = apps.get_model('admin_portal', 'AdminRole')
  Permission = apps.get_model('admin_portal', 'AdminPermission')
  RolePermission = apps.get_model('admin_portal', 'AdminRolePermission')
  admin_grants = {
    'support-admin': {'admin.staff.list', 'admin.staff.create'},
    'operations-admin': {'admin.staff.list', 'admin.staff.create'},
    'finance-admin': {'admin.dashboard.view', 'admin.finance.view', 'admin.finance.edit', 'admin.finance.export', 'admin.audit.view', 'admin.staff.list', 'admin.staff.create'},
    'technical-admin': {'admin.dashboard.view', 'admin.errors.list', 'admin.errors.view', 'admin.errors.manage', 'admin.audit.view', 'admin.staff.list', 'admin.staff.create'},
    'security-admin': {'admin.dashboard.view', 'admin.audit.view', 'admin.lifecycle.view', 'admin.lifecycle.manage', 'admin.errors.list', 'admin.errors.view', 'admin.staff.list', 'admin.staff.create'},
  }
  role_names = {'finance-admin': 'Finance Admin', 'technical-admin': 'Technical Admin', 'security-admin': 'Security Admin'}
  for slug, codes in admin_grants.items():
    role, _ = Role.objects.get_or_create(slug=slug, defaults={'name': role_names.get(slug, slug.replace('-', ' ').title())})
    for permission in Permission.objects.filter(code__in=codes):
      RolePermission.objects.update_or_create(role=role, permission=permission, defaults={'allowed': True})
  for staff in Staff.objects.select_related('user', 'role'):
    staff.authority_level = 50 if 'admin' in staff.role.slug else 10
    staff.save(update_fields=['authority_level'])
  owner = Staff.objects.filter(user__username='reproot.admin').first() or Staff.objects.filter(role__slug='super-admin').order_by('created_at').first()
  if owner:
    owner.is_owner = True
    owner.authority_level = 100
    owner.department = 'OWNER'
    owner.save(update_fields=['is_owner', 'authority_level', 'department'])


class Migration(migrations.Migration):
  atomic = False
  dependencies = [('admin_portal', '0005_platform_expenses')]
  operations = [
    migrations.AddField(model_name='adminstaffprofile', name='department', field=models.CharField(choices=[('OWNER','Owner'),('OPERATIONS','Operations'),('SUPPORT','Customer Support'),('FINANCE','Finance'),('TECHNICAL','Technical Operations'),('SECURITY','Security'),('ANALYTICS','Analytics')], db_index=True, default='OPERATIONS', max_length=20)),
    migrations.AddField(model_name='adminstaffprofile', name='authority_level', field=models.PositiveSmallIntegerField(db_index=True, default=10)),
    migrations.AddField(model_name='adminstaffprofile', name='is_owner', field=models.BooleanField(db_index=True, default=False)),
    migrations.AddField(model_name='adminstaffprofile', name='must_change_password', field=models.BooleanField(default=True)),
    migrations.AddField(model_name='adminstaffprofile', name='last_admin_login_at', field=models.DateTimeField(blank=True, null=True)),
    migrations.RunPython(configure_owner_and_hierarchy, migrations.RunPython.noop),
  ]
