from django.core.files.uploadedfile import UploadedFile
from django.core.cache import cache
from rest_framework import permissions

from .data_usage import calculate_professional_data_usage
from .models import ProfessionalProfile


def request_has_upload(request) -> bool:
  if request.FILES:
    return True
  return any(
    isinstance(value, UploadedFile) or (isinstance(value, str) and value.startswith('data:image/'))
    for value in request.data.values()
  )


def upload_fits_storage(professional, request) -> bool:
  cache.delete(f'professional-data-usage:v5:{professional.pk}')
  usage = calculate_professional_data_usage(professional)
  uploaded_bytes = sum(int(upload.size) for upload in request.FILES.values())
  uploaded_bytes += sum(
    int(len(value.split(',', 1)[-1]) * 0.75)
    for value in request.data.values()
    if isinstance(value, str) and value.startswith('data:image/')
  )
  projected_percent = usage.get('usage_percent', 0) + (
    uploaded_bytes / max(1, usage.get('included_quota_bytes', 1)) * 100
  )
  return projected_percent <= usage.get('hard_limit_percent', 120)


class ProfessionalAccessPermission(permissions.IsAuthenticated):
  """Central professional lifecycle and storage-write enforcement."""

  message = 'This professional account is unavailable.'

  def has_permission(self, request, view):
    if not super().has_permission(request, view):
      return False
    profile = getattr(request.user, 'professional_profile', None)
    if profile is None:
      return True
    if profile.lifecycle_status in (ProfessionalProfile.LIFECYCLE_FROZEN, ProfessionalProfile.LIFECYCLE_RECYCLED):
      self.message = 'This professional account is frozen. Contact support to restore access.'
      return False
    if request_has_upload(request) and not upload_fits_storage(request.user, request):
      self.message = 'New uploads are paused at the 120% temporary storage ceiling. Delete files or upgrade storage.'
      return False
    return True
