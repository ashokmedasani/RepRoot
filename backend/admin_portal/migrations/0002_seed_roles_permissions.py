from django.db import migrations


PERMISSIONS = {
  'admin.dashboard.view': ('View dashboard', 'Dashboard'),
  'admin.trainers.list': ('List trainers', 'Trainers'),
  'admin.trainers.view_basic': ('View basic trainer information', 'Trainers'),
  'admin.trainers.view_sensitive': ('View sensitive trainer information', 'Trainers'),
  'admin.clients.list': ('List clients', 'Clients'),
  'admin.clients.view_basic': ('View basic client information', 'Clients'),
  'admin.clients.view_sensitive': ('View sensitive client information', 'Clients'),
  'admin.support.list': ('List support requests', 'Support'),
  'admin.support.view': ('View support requests', 'Support'),
  'admin.staff.list': ('List staff', 'Staff'),
  'admin.staff.create': ('Create staff', 'Staff'),
  'admin.roles.manage': ('Manage roles and permissions', 'Staff'),
  'admin.audit.view': ('View audit logs', 'Audit'),
  'admin.audit.export': ('Export audit logs', 'Audit'),
  'admin.reports.view': ('View aggregate reports', 'Reports'),
  'admin.reports.export': ('Export aggregate reports', 'Reports'),
  'admin.finance.view': ('View finance summaries', 'Finance'),
  'admin.finance.export': ('Export finance summaries', 'Finance'),
  'admin.settings.view': ('View settings', 'Settings'),
  'admin.settings.edit': ('Edit settings', 'Settings'),
}

ROLE_GRANTS = {
  'super-admin': '*',
  'support-admin': {
    'admin.dashboard.view', 'admin.trainers.list', 'admin.trainers.view_basic', 'admin.clients.list',
    'admin.clients.view_basic', 'admin.support.list', 'admin.support.view', 'admin.audit.view',
  },
  'support-agent': {
    'admin.dashboard.view', 'admin.trainers.list', 'admin.trainers.view_basic', 'admin.clients.list',
    'admin.clients.view_basic', 'admin.support.list', 'admin.support.view',
  },
  'operations-admin': {
    'admin.dashboard.view', 'admin.reports.view', 'admin.reports.export', 'admin.finance.view',
    'admin.finance.export', 'admin.audit.view',
  },
  'read-only-analyst': {'admin.dashboard.view', 'admin.reports.view', 'admin.finance.view'},
}


def seed_roles(apps, schema_editor):
  Permission = apps.get_model('admin_portal', 'AdminPermission')
  Role = apps.get_model('admin_portal', 'AdminRole')
  Link = apps.get_model('admin_portal', 'AdminRolePermission')
  permission_objects = {}
  for code, (name, section) in PERMISSIONS.items():
    permission_objects[code], _ = Permission.objects.update_or_create(
      code=code, defaults={'name': name, 'section': section}
    )
  role_names = {
    'super-admin': 'Super Admin',
    'support-admin': 'Support Admin',
    'support-agent': 'Support Agent',
    'operations-admin': 'Operations Admin',
    'read-only-analyst': 'Read-Only Analyst',
  }
  for slug, grants in ROLE_GRANTS.items():
    role, _ = Role.objects.update_or_create(slug=slug, defaults={'name': role_names[slug]})
    codes = permission_objects.keys() if grants == '*' else grants
    for code in codes:
      Link.objects.update_or_create(role=role, permission=permission_objects[code], defaults={'allowed': True})


class Migration(migrations.Migration):
  dependencies = [('admin_portal', '0001_initial')]
  operations = [migrations.RunPython(seed_roles, migrations.RunPython.noop)]
