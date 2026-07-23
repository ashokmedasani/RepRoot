from rest_framework.permissions import BasePermission

from .models import AdminStaffProfile


def permission_codes_for(staff):
  role_codes = set(
    staff.role.permission_links.filter(allowed=True).values_list('permission__code', flat=True)
  )
  for code, allowed in staff.permission_overrides.values_list('permission__code', 'allowed'):
    if allowed:
      role_codes.add(code)
    else:
      role_codes.discard(code)
  return sorted(role_codes)


def active_staff_for(user):
  if not user or not user.is_authenticated or not user.is_active:
    return None
  return (
    AdminStaffProfile.objects.select_related('user', 'role')
    .filter(user=user, status=AdminStaffProfile.STATUS_ACTIVE)
    .first()
  )


class HasAdminPermission(BasePermission):
  message = 'You do not have permission to access this administrative resource.'

  def has_permission(self, request, view):
    staff = active_staff_for(request.user)
    required = getattr(view, 'required_permission', '')
    if not staff or not required:
      return False
    if staff.must_change_password:
      self.message = 'You must change your temporary password before using the Admin Portal.'
      return False
    request.admin_staff = staff
    return required in permission_codes_for(staff)
