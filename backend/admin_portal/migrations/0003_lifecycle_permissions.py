from django.db import migrations


def add_permissions(apps, schema_editor):
    Permission = apps.get_model('admin_portal', 'AdminPermission')
    Role = apps.get_model('admin_portal', 'AdminRole')
    Link = apps.get_model('admin_portal', 'AdminRolePermission')
    definitions = {
        'admin.lifecycle.view': 'View account lifecycle and Recycle Center',
        'admin.lifecycle.manage': 'Recycle, restore, and permanently delete accounts',
    }
    permissions = {}
    for code, name in definitions.items():
        permissions[code], _ = Permission.objects.update_or_create(
            code=code, defaults={'name': name, 'section': 'Account Lifecycle'}
        )
    for role in Role.objects.filter(slug__in=['super-admin', 'support-admin']):
        for permission in permissions.values():
            Link.objects.update_or_create(role=role, permission=permission, defaults={'allowed': True})


class Migration(migrations.Migration):
    dependencies = [('admin_portal', '0002_seed_roles_permissions')]
    operations = [migrations.RunPython(add_permissions, migrations.RunPython.noop)]
