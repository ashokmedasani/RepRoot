"""
Cold-storage relocation for heavy locked resources (PDFs/images). See
DOWNGRADE_LOCK_SYSTEM_PLAN.md 3.6: a locked resource is never deleted, but
leaving its file sitting in the same "hot" storage location as active
resources costs the same as if it were still in active use -- so the moment
a resource locks, its file is relocated to a cheaper/cold prefix, and moved
back automatically the instant it's active again (upgrade, reorder, or a
freed slot promoting it back). text_note resources have no file and
video_link resources store a URL, not a file -- both are left untouched.

Implemented as a plain storage-key relocation via Django's default_storage
abstraction, so it works unchanged whether the deployment's default storage
backend is local FileSystemStorage (dev) or S3Storage (prod). An actual S3
storage-class transition (e.g. STANDARD -> GLACIER) would be a further,
purely cost-driven optimization -- the plan doc explicitly defers that kind
of thing until there's real usage data to justify it; this hook only
handles relocating to a distinct "cold" key prefix, which is what an
external lifecycle rule (or a future storage-class migration) would target.
"""

from django.core.files.base import ContentFile

from .models import ProfessionalResource

COLD_PREFIX = 'professional-resources-cold/'
HOT_PREFIX = 'professional-resources/'

HEAVY_RESOURCE_TYPES = {ProfessionalResource.TYPE_PDF, ProfessionalResource.TYPE_IMAGE}


def _relocate(resource, old_prefix, new_prefix) -> bool:
  file_field = resource.file
  if not file_field or not file_field.name:
    return False
  if not file_field.name.startswith(old_prefix):
    return False  # already relocated (or never was in the expected location)

  storage = file_field.storage
  old_name = file_field.name
  new_name = new_prefix + old_name[len(old_prefix):]

  if not storage.exists(old_name):
    return False

  try:
    with storage.open(old_name, 'rb') as fh:
      content = ContentFile(fh.read())
    storage.save(new_name, content)
    storage.delete(old_name)
  # A storage hiccup here must never block the actual lock/unlock action it's
  # riding along with -- worst case the file just stays in its current tier
  # until the next sync call retries it.
  except Exception:
    return False

  resource.file.name = new_name
  resource.save(update_fields=['file'])
  return True


def move_resource_to_cold_storage(resource) -> bool:
  """Called when a resource transitions from active to locked. No-op for
  text_note/video_link resources (no meaningful file) and a no-op if already
  relocated. Returns True if a move actually happened."""
  if resource.resource_type not in HEAVY_RESOURCE_TYPES:
    return False
  return _relocate(resource, HOT_PREFIX, COLD_PREFIX)


def restore_resource_from_cold_storage(resource) -> bool:
  """Called when a resource transitions from locked back to active (plan
  upgrade, reorder, or deleting another item freeing its slot). Reverses
  move_resource_to_cold_storage."""
  if resource.resource_type not in HEAVY_RESOURCE_TYPES:
    return False
  return _relocate(resource, COLD_PREFIX, HOT_PREFIX)


def sync_resource_cold_storage(professional) -> dict:
  """Call after anything that can change which resources are locked -- the
  same trigger points as plan_lock_cascade.sync_group_lock_cascade: a plan
  tier change, a reorder of categories/resources, or a category/resource
  delete that promotes a previously-locked resource. Diffs each heavy
  resource's current storage location against its current lock status and
  relocates anything out of sync, in either direction.

  Returns {'moved_to_cold': [id, ...], 'restored_to_hot': [id, ...]}.
  """
  from .plan_lock_status import compute_lock_status

  status = compute_lock_status(professional)
  locked_ids = set(status['resources']['locked_ids'])

  moved_to_cold = []
  restored_to_hot = []

  heavy_resources = ProfessionalResource.objects.filter(
    professional=professional, resource_type__in=HEAVY_RESOURCE_TYPES
  ).exclude(file='')

  for resource in heavy_resources:
    if resource.id in locked_ids:
      if move_resource_to_cold_storage(resource):
        moved_to_cold.append(resource.id)
    else:
      if restore_resource_from_cold_storage(resource):
        restored_to_hot.append(resource.id)

  return {'moved_to_cold': moved_to_cold, 'restored_to_hot': restored_to_hot}
