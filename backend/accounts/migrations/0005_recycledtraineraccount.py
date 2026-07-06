from django.db import migrations, models


class Migration(migrations.Migration):

  dependencies = [
    ('accounts', '0004_trainerprofile_setup_portfolio'),
  ]

  operations = [
    migrations.CreateModel(
      name='RecycledTrainerAccount',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        ('original_user_id', models.PositiveIntegerField(db_index=True)),
        ('email', models.EmailField(db_index=True, max_length=254)),
        ('username', models.CharField(db_index=True, max_length=150)),
        ('first_name', models.CharField(blank=True, max_length=150)),
        ('last_name', models.CharField(blank=True, max_length=150)),
        ('account_snapshot', models.JSONField()),
        ('deleted_at', models.DateTimeField(auto_now_add=True)),
      ],
      options={
        'db_table': 'recycled_trainer_accounts',
        'ordering': ['-deleted_at'],
      },
    ),
  ]
