import traceback

VALID_PLATFORMS = ('web', 'android', 'ios')


def _resolve_identity(request):
  """Best-effort professional/client identity from the raw Authorization header.

  process_exception sees the original Django HttpRequest, not DRF's wrapped
  Request, so request.user/request.auth as DRF sets them aren't reliably
  available here — this replicates what TokenAuthentication and
  ClientTokenAuthentication do, directly against the token tables.
  """
  header = request.META.get('HTTP_AUTHORIZATION', '')
  parts = header.split()
  if len(parts) != 2:
    return None, None

  scheme, key = parts
  try:
    if scheme.lower() == 'token':
      from rest_framework.authtoken.models import Token
      token = Token.objects.select_related('user').filter(key=key).first()
      return (token.user, None) if token else (None, None)
    if scheme.lower() == 'clienttoken':
      from accounts.models import ClientAuthToken
      auth_token = ClientAuthToken.objects.select_related('client__professional').filter(key=key).first()
      return (None, auth_token.client) if auth_token else (None, None)
  except Exception:
    pass
  return None, None


class ErrorCaptureMiddleware:
  """Auto-logs unhandled server-side exceptions as ErrorLog(source=backend).

  DRF's own exception handler already turns recognized API errors
  (validation, permission, not-found) into proper 4xx responses without an
  exception ever reaching here — process_exception only sees genuine
  unhandled bugs, which is exactly what belongs in the error console.

  A failure in here must never turn into a *second*, worse 500, so every
  step is wrapped and swallowed.
  """

  def __init__(self, get_response):
    self.get_response = get_response

  def __call__(self, request):
    return self.get_response(request)

  def process_exception(self, request, exception):
    try:
      from .models import ErrorLog, record_error

      platform = request.META.get('HTTP_X_CLIENT_PLATFORM', '').strip().lower()
      if platform not in VALID_PLATFORMS:
        platform = ErrorLog.PLATFORM_UNKNOWN

      professional, client = _resolve_identity(request)
      message = str(exception).strip() or exception.__class__.__name__

      record_error(
        platform=platform,
        message=message,
        source=ErrorLog.SOURCE_BACKEND,
        level=ErrorLog.LEVEL_FATAL,
        professional=professional,
        client=client,
        stack_trace=traceback.format_exc(),
        request_path=request.path,
      )
    except Exception:
      pass
    return None
