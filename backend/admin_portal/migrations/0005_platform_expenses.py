import admin_portal.models
import django.db.models.deletion
from django.db import migrations, models


def seed_finance_edit(apps, schema_editor):
  Permission = apps.get_model('admin_portal', 'AdminPermission')
  Role = apps.get_model('admin_portal', 'AdminRole')
  Link = apps.get_model('admin_portal', 'AdminRolePermission')
  permission, _ = Permission.objects.update_or_create(code='admin.finance.edit', defaults={'name': 'Record platform expenses', 'section': 'Finance', 'description': 'Create manual RepRoot operating-expense records.'})
  for role in Role.objects.filter(slug__in=['super-admin', 'operations-admin']):
    Link.objects.update_or_create(role=role, permission=permission, defaults={'allowed': True})


class Migration(migrations.Migration):
  dependencies = [('admin_portal', '0004_finance_ledger_snapshots')]
  operations = [
    migrations.CreateModel(name='PlatformExpense', fields=[
      ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
      ('expense_id', models.CharField(db_index=True, default=admin_portal.models.expense_reference, editable=False, max_length=24, unique=True)),
      ('category', models.CharField(choices=[('INFRASTRUCTURE','Infrastructure'),('SOFTWARE','Software'),('MARKETING','Marketing'),('PAYROLL','Payroll / contractors'),('PROFESSIONAL_SERVICES','Professional services'),('OTHER','Other')], db_index=True, max_length=32)),
      ('amount', models.DecimalField(decimal_places=2, max_digits=12)), ('currency', models.CharField(db_index=True, max_length=3)),
      ('vendor', models.CharField(blank=True, max_length=160)), ('description', models.CharField(max_length=300)), ('expense_date', models.DateField(db_index=True)),
      ('external_reference', models.CharField(blank=True, max_length=120)), ('created_at', models.DateTimeField(auto_now_add=True)),
      ('recorded_by', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='recorded_expenses', to='admin_portal.adminstaffprofile')),
    ], options={'db_table':'platform_expenses','ordering':['-expense_date','-created_at']}),
    migrations.RunPython(seed_finance_edit, migrations.RunPython.noop),
  ]
