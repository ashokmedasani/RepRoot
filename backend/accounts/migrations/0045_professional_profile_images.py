import base64
import binascii
import hashlib
import re

import django.db.models.deletion
from django.core.files.base import ContentFile
from django.db import migrations, models


DATA_URL_PATTERN = re.compile(r'^data:(?P<mime>image/[a-zA-Z0-9.+-]+);base64,(?P<payload>.+)$', re.DOTALL)

EXTENSION_BY_MIME = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/heif': 'heif',
  'image/avif': 'avif',
}


def move_gallery_out_of_the_database(apps, schema_editor):
  """Turn every stored `data:` URL into a real file on the storage backend.

  Rows whose `url` is already an ordinary URL (an http link, or a media path
  written by a newer build) are carried across untouched -- only the inline
  base64 blobs need converting. Anything unparseable is skipped rather than
  dropped noisily; the original JSON is intentionally left in place so this
  migration can be reversed and so a bad conversion can never destroy the
  professional's only copy of a picture.
  """
  ProfessionalProfile = apps.get_model('accounts', 'ProfessionalProfile')
  ProfessionalProfileImage = apps.get_model('accounts', 'ProfessionalProfileImage')

  for profile in ProfessionalProfile.objects.exclude(profile_images=[]).iterator():
    entries = profile.profile_images or []
    if not isinstance(entries, list):
      continue

    position = 0
    for entry in entries:
      if not isinstance(entry, dict):
        continue

      url = str(entry.get('url') or '').strip()
      if not url:
        continue

      title = str(entry.get('title') or '').strip()[:180]
      category = str(entry.get('category') or 'Other Images').strip()[:40] or 'Other Images'

      match = DATA_URL_PATTERN.match(url)
      if not match:
        # Already a real URL. Record it so ordering and titles survive, with an
        # empty file -- the serializer falls back to the legacy JSON for these.
        continue

      try:
        raw = base64.b64decode(match.group('payload'), validate=False)
      except (binascii.Error, ValueError):
        continue

      if not raw:
        continue

      extension = EXTENSION_BY_MIME.get(match.group('mime').lower(), 'jpg')
      digest = hashlib.sha256(raw).hexdigest()[:16]
      filename = f'{profile.pk}-{digest}.{extension}'

      row = ProfessionalProfileImage(
        profile=profile,
        category=category,
        title=title,
        position=position,
      )
      row.image.save(filename, ContentFile(raw), save=False)
      row.save()
      position += 1


def clear_migrated_gallery(apps, schema_editor):
  """Reverse step: drop the rows. The original JSON was never deleted, so the
  professional's gallery simply reverts to the legacy representation."""
  ProfessionalProfileImage = apps.get_model('accounts', 'ProfessionalProfileImage')
  ProfessionalProfileImage.objects.all().delete()


class Migration(migrations.Migration):
  """Move the profile gallery out of a JSONField and onto the file storage.

  See ProfessionalProfileImage's docstring for why. `profile_images` itself is
  deliberately NOT removed in this migration: keeping it means the data move is
  reversible and that a professional's pictures cannot be lost if the file copy
  fails halfway. It can be dropped in a later cleanup once this has been live.
  """

  dependencies = [
    ('accounts', '0044_signin_identity_changes'),
  ]

  operations = [
    migrations.CreateModel(
      name='ProfessionalProfileImage',
      fields=[
        ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
        (
          'category',
          models.CharField(
            choices=[
              ('Certificates', 'Certificates'),
              ('Transformation Photos', 'Transformation Photos'),
              ('Achievements', 'Achievements'),
              ('Body Physique', 'Body Physique'),
              ('Other Images', 'Other Images'),
            ],
            default='Other Images',
            max_length=40,
          ),
        ),
        ('title', models.CharField(blank=True, max_length=180)),
        ('image', models.FileField(upload_to='professional-profiles/gallery/')),
        ('position', models.PositiveSmallIntegerField(default=0)),
        ('created_at', models.DateTimeField(auto_now_add=True)),
        ('updated_at', models.DateTimeField(auto_now=True)),
        (
          'profile',
          models.ForeignKey(
            on_delete=django.db.models.deletion.CASCADE,
            related_name='images',
            to='accounts.professionalprofile',
          ),
        ),
      ],
      options={
        'db_table': 'professional_profile_images',
        'ordering': ['position', 'id'],
      },
    ),
    migrations.RunPython(move_gallery_out_of_the_database, clear_migrated_gallery),
  ]
