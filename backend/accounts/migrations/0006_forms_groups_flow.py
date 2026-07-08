from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

  dependencies = [
    migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ('accounts', '0005_recycledtraineraccount'),
  ]

  operations = [
    migrations.CreateModel(
      name='TrainerLeadForm',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('public_slug', models.SlugField(max_length=64, unique=True)),
        ('title', models.CharField(default='Trainer Lead Form', max_length=160)),
        ('fields', models.JSONField(default=list)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        ('trainer', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='lead_form', to=settings.AUTH_USER_MODEL)),
      ],
      options={
        'db_table': 'trainer_lead_forms',
      },
    ),
    migrations.CreateModel(
      name='TrainerGroup',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('name', models.CharField(max_length=120)),
        ('description', models.TextField(blank=True)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        ('trainer', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='trainer_groups', to=settings.AUTH_USER_MODEL)),
      ],
      options={
        'db_table': 'trainer_groups',
        'ordering': ['created_at'],
        'unique_together': {('trainer', 'name')},
      },
    ),
    migrations.CreateModel(
      name='ClientRegistrationForm',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('fields', models.JSONField(default=list)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        ('group', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='client_registration_form', to='accounts.trainergroup')),
      ],
      options={
        'db_table': 'client_registration_forms',
      },
    ),
    migrations.CreateModel(
      name='LeadSubmission',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('first_name', models.CharField(max_length=150)),
        ('last_name', models.CharField(max_length=150)),
        ('email', models.EmailField(max_length=254)),
        ('reference_id', models.CharField(max_length=32, unique=True)),
        ('answers', models.JSONField(default=dict)),
        ('status', models.CharField(choices=[('pending', 'Pending'), ('approved', 'Approved / Converted')], default='pending', max_length=20)),
        ('submitted_at', models.DateTimeField(auto_now_add=True)),
        ('converted_at', models.DateTimeField(blank=True, null=True)),
        ('lead_form', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='submissions', to='accounts.trainerleadform')),
      ],
      options={
        'db_table': 'lead_submissions',
        'ordering': ['-submitted_at'],
      },
    ),
    migrations.CreateModel(
      name='ClientAccess',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('first_name', models.CharField(max_length=150)),
        ('last_name', models.CharField(max_length=150)),
        ('email', models.EmailField(max_length=254)),
        ('username', models.CharField(max_length=150)),
        ('temporary_password', models.CharField(max_length=128)),
        ('registration_answers', models.JSONField(default=dict)),
        ('must_change_password', models.BooleanField(default=True)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('group', models.ForeignKey(on_delete=django.db.models.deletion.PROTECT, related_name='client_access_records', to='accounts.trainergroup')),
        ('lead_submission', models.OneToOneField(on_delete=django.db.models.deletion.PROTECT, related_name='client_access', to='accounts.leadsubmission')),
        ('trainer', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='client_access_records', to=settings.AUTH_USER_MODEL)),
      ],
      options={
        'db_table': 'client_access',
        'ordering': ['-created_at'],
        'unique_together': {('trainer', 'email'), ('trainer', 'username')},
      },
    ),
  ]
