from datetime import date
from pathlib import Path
import os

import dj_database_url
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

# Local dev convenience only: a real deployment sets these as actual process
# env vars (Render, Docker, etc.), which always take priority — load_dotenv()
# does not override a variable that's already set. If python-dotenv isn't
# installed yet (e.g. a venv that predates this), skip it rather than crash;
# .env then simply has no effect until `pip install -r requirements.txt` runs.
try:
  from dotenv import load_dotenv
  load_dotenv(BASE_DIR / '.env')
except ImportError:
  pass

DEVELOPMENT_SECRET_KEY = 'local-development-only-secret-key'
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', DEVELOPMENT_SECRET_KEY)
DEBUG = os.environ.get('DJANGO_DEBUG', 'False').lower() == 'true'

if not DEBUG and SECRET_KEY == DEVELOPMENT_SECRET_KEY:
  raise ImproperlyConfigured('DJANGO_SECRET_KEY must be set to a secure value when DJANGO_DEBUG is False.')

# 10.0.2.2 is how the Android emulator reaches this PC's localhost. In DEBUG
# mode these development hosts are always merged with configured hosts rather
# than being replaced by DJANGO_ALLOWED_HOSTS. Production remains explicit.
development_allowed_hosts = ['localhost', '127.0.0.1', '10.0.2.2']
render_external_hostname = os.environ.get('RENDER_EXTERNAL_HOSTNAME', '').strip()

configured_allowed_hosts = [
  host.strip()
  for host in os.environ.get('DJANGO_ALLOWED_HOSTS', '').split(',')
  if host.strip()
]

ALLOWED_HOSTS = list(dict.fromkeys([
  *(development_allowed_hosts if DEBUG else []),
  *configured_allowed_hosts,
  *([render_external_hostname] if render_external_hostname else []),
]))

INSTALLED_APPS = [
  'django.contrib.admin',
  'django.contrib.auth',
  'django.contrib.contenttypes',
  'django.contrib.sessions',
  'django.contrib.messages',
  'django.contrib.staticfiles',
  'corsheaders',
  'rest_framework',
  'rest_framework.authtoken',
  'accounts',
  'admin_portal',
]

MIDDLEWARE = [
  'corsheaders.middleware.CorsMiddleware',
  'django.middleware.security.SecurityMiddleware',
  'whitenoise.middleware.WhiteNoiseMiddleware',
  'django.contrib.sessions.middleware.SessionMiddleware',
  'django.middleware.common.CommonMiddleware',
  'django.middleware.csrf.CsrfViewMiddleware',
  'django.contrib.auth.middleware.AuthenticationMiddleware',
  'django.contrib.messages.middleware.MessageMiddleware',
  'django.middleware.clickjacking.XFrameOptionsMiddleware',
  'admin_portal.middleware.ErrorCaptureMiddleware',
]

ROOT_URLCONF = 'config.urls'

TEMPLATES = [
  {
    'BACKEND': 'django.template.backends.django.DjangoTemplates',
    'DIRS': [],
    'APP_DIRS': True,
    'OPTIONS': {
      'context_processors': [
        'django.template.context_processors.request',
        'django.contrib.auth.context_processors.auth',
        'django.contrib.messages.context_processors.messages',
      ],
    },
  },
]

WSGI_APPLICATION = 'config.wsgi.application'

DATABASE_URL = os.environ.get('DATABASE_URL')

if DATABASE_URL:
  DATABASES = {
    'default': dj_database_url.parse(
      DATABASE_URL,
      conn_max_age=int(os.environ.get('POSTGRES_CONN_MAX_AGE', '600')),
      conn_health_checks=True,
    )
  }
else:
  DATABASES = {
    'default': {
      'ENGINE': 'django.db.backends.postgresql',
      'NAME': os.environ.get('POSTGRES_DB', 'professional_platform'),
      'USER': os.environ.get('POSTGRES_USER', 'postgres'),
      'PASSWORD': os.environ.get('POSTGRES_PASSWORD', 'postgres'),
      'HOST': os.environ.get('POSTGRES_HOST', 'localhost'),
      'PORT': os.environ.get('POSTGRES_PORT', '5432'),
      'OPTIONS': {
        'connect_timeout': int(os.environ.get('POSTGRES_CONNECT_TIMEOUT', '5')),
      },
    }
  }

AUTH_PASSWORD_VALIDATORS = [
  {
    'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator',
  },
  {
    'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator',
  },
  {
    'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator',
  },
  {
    'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator',
  },
]

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'America/New_York'
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
MEDIA_URL = '/media/'
MEDIA_ROOT = BASE_DIR / 'media'
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

STORAGES = {
  'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
  'staticfiles': {'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage'},
}

# Production uploads should use durable S3-compatible object storage. Local
# development continues to use MEDIA_ROOT without additional configuration.
AWS_STORAGE_BUCKET_NAME = os.environ.get('AWS_STORAGE_BUCKET_NAME', '').strip()
if AWS_STORAGE_BUCKET_NAME:
  STORAGES['default'] = {
    'BACKEND': 'storages.backends.s3.S3Storage',
    'OPTIONS': {
      'bucket_name': AWS_STORAGE_BUCKET_NAME,
      'region_name': os.environ.get('AWS_S3_REGION_NAME', '').strip() or None,
      'endpoint_url': os.environ.get('AWS_S3_ENDPOINT_URL', '').strip() or None,
      'custom_domain': os.environ.get('AWS_S3_CUSTOM_DOMAIN', '').strip() or None,
      'default_acl': None,
      'file_overwrite': False,
      'querystring_auth': os.environ.get('AWS_QUERYSTRING_AUTH', 'True').lower() == 'true',
    },
  }

if not DEBUG and not AWS_STORAGE_BUCKET_NAME:
  raise ImproperlyConfigured(
    'Durable S3-compatible upload storage is required in production. Configure AWS_STORAGE_BUCKET_NAME '
    'and the matching access credentials/endpoint before enabling the service.'
  )

EMAIL_HOST = os.environ.get('EMAIL_HOST', '').strip()
EMAIL_BACKEND = os.environ.get(
  'EMAIL_BACKEND',
  'django.core.mail.backends.smtp.EmailBackend' if EMAIL_HOST else 'django.core.mail.backends.console.EmailBackend',
)
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', '')
EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'True').lower() == 'true'
EMAIL_USE_SSL = os.environ.get('EMAIL_USE_SSL', 'False').lower() == 'true'
EMAIL_TIMEOUT = int(os.environ.get('EMAIL_TIMEOUT', '15'))
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', EMAIL_HOST_USER or 'no-reply@reproot.local')
SUPPORT_EMAIL = os.environ.get('SUPPORT_EMAIL', '').strip()
# STUDIO-HIDDEN 2026-08-17: default was 'studio.support@rep-root.com'.
STUDIO_SUPPORT_EMAIL = os.environ.get('STUDIO_SUPPORT_EMAIL', 'support@rep-root.com').strip()
ERROR_ALERT_EMAIL = os.environ.get('ERROR_ALERT_EMAIL', SUPPORT_EMAIL).strip()
MEETING_FROM_EMAIL = os.environ.get('MEETING_FROM_EMAIL', DEFAULT_FROM_EMAIL).strip()

if not DEBUG and EMAIL_BACKEND == 'django.core.mail.backends.console.EmailBackend':
  raise ImproperlyConfigured('Configure a production EMAIL_BACKEND and EMAIL_HOST before deployment.')

# Optional production calendar bridge. RepRoot scheduling continues to work
# internally when this is disabled; enabled meetings are mirrored to one Google
# Calendar and receive a unique Google Meet room.
GOOGLE_CALENDAR_ENABLED = os.environ.get('GOOGLE_CALENDAR_ENABLED', 'False').lower() == 'true'
GOOGLE_CALENDAR_CLIENT_ID = os.environ.get('GOOGLE_CALENDAR_CLIENT_ID', '').strip()
GOOGLE_CALENDAR_CLIENT_SECRET = os.environ.get('GOOGLE_CALENDAR_CLIENT_SECRET', '').strip()
GOOGLE_CALENDAR_REFRESH_TOKEN = os.environ.get('GOOGLE_CALENDAR_REFRESH_TOKEN', '').strip()
GOOGLE_CALENDAR_ID = os.environ.get('GOOGLE_CALENDAR_ID', '').strip()
GOOGLE_CALENDAR_TIMEOUT_SECONDS = int(os.environ.get('GOOGLE_CALENDAR_TIMEOUT_SECONDS', '15'))

if GOOGLE_CALENDAR_ENABLED and not all([
  GOOGLE_CALENDAR_CLIENT_ID,
  GOOGLE_CALENDAR_CLIENT_SECRET,
  GOOGLE_CALENDAR_REFRESH_TOKEN,
  GOOGLE_CALENDAR_ID,
]):
  raise ImproperlyConfigured(
    'Google Calendar is enabled but its OAuth client, refresh token, or calendar ID is missing.'
  )

# Optional "Continue with Google" sign-in/signup for professionals. Disabled
# (and silently ignored) until a real Web OAuth Client ID is provided. This is
# a separate Google Cloud OAuth client from GOOGLE_CALENDAR_CLIENT_ID above —
# it is a public client ID embedded in the frontend, not a secret.
GOOGLE_OAUTH_CLIENT_ID = os.environ.get('GOOGLE_OAUTH_CLIENT_ID', '').strip()
GOOGLE_OAUTH_ENABLED = bool(GOOGLE_OAUTH_CLIENT_ID)

CACHE_URL = os.environ.get('CACHE_URL', '').strip()
if CACHE_URL:
  CACHES = {
    'default': {
      'BACKEND': 'django.core.cache.backends.redis.RedisCache',
      'LOCATION': CACHE_URL,
      'TIMEOUT': 600,
    }
  }
else:
  CACHES = {
    'default': {
      'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
      'LOCATION': 'reproot-local-cache',
    }
  }

# 4300 = web frontend. The Flutter app talks to the backend natively (Dio),
# not through a browser origin, so it isn't subject to CORS at all.
CORS_ALLOWED_ORIGINS = [
  origin.strip()
  for origin in os.environ.get(
    'CORS_ALLOWED_ORIGINS',
    'http://localhost:4300,http://127.0.0.1:4300',
  ).split(',')
  if origin.strip()
]

# django-cors-headers' default allow-list doesn't include this custom header;
# the web app and mobile app both send it on every request so backend-caught
# exceptions (admin_portal.middleware.ErrorCaptureMiddleware) know which
# platform hit them. Without this, every cross-origin request carrying the
# header fails CORS preflight — not just the error-report endpoint.
from corsheaders.defaults import default_headers  # noqa: E402

CORS_ALLOW_HEADERS = [*default_headers, 'x-client-platform']

CSRF_TRUSTED_ORIGINS = [
  origin.strip()
  for origin in os.environ.get('CSRF_TRUSTED_ORIGINS', ','.join(CORS_ALLOWED_ORIGINS)).split(',')
  if origin.strip()
]

DJANGO_PROXY_SSL_HEADER = os.environ.get(
  'DJANGO_PROXY_SSL_HEADER', 'HTTP_X_FORWARDED_PROTO'
).strip()
if DJANGO_PROXY_SSL_HEADER not in {
  'HTTP_X_FORWARDED_PROTO',
  'HTTP_CLOUDFRONT_FORWARDED_PROTO',
}:
  raise ImproperlyConfigured(
    'DJANGO_PROXY_SSL_HEADER must be HTTP_X_FORWARDED_PROTO or '
    'HTTP_CLOUDFRONT_FORWARDED_PROTO.'
  )
SECURE_PROXY_SSL_HEADER = (DJANGO_PROXY_SSL_HEADER, 'https')
SECURE_SSL_REDIRECT = os.environ.get('DJANGO_SECURE_SSL_REDIRECT', 'False' if DEBUG else 'True').lower() == 'true'
SESSION_COOKIE_SECURE = os.environ.get('DJANGO_SESSION_COOKIE_SECURE', 'False' if DEBUG else 'True').lower() == 'true'
CSRF_COOKIE_SECURE = os.environ.get('DJANGO_CSRF_COOKIE_SECURE', 'False' if DEBUG else 'True').lower() == 'true'
SECURE_HSTS_SECONDS = int(os.environ.get('DJANGO_SECURE_HSTS_SECONDS', '0' if DEBUG else '31536000'))
SECURE_HSTS_INCLUDE_SUBDOMAINS = os.environ.get(
  'DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS', 'False' if DEBUG else 'True'
).lower() == 'true'
SECURE_HSTS_PRELOAD = os.environ.get('DJANGO_SECURE_HSTS_PRELOAD', 'False' if DEBUG else 'True').lower() == 'true'
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = 'same-origin'
X_FRAME_OPTIONS = 'DENY'

REST_FRAMEWORK = {
  'DEFAULT_PERMISSION_CLASSES': [
    'rest_framework.permissions.IsAuthenticated',
  ],
  'DEFAULT_AUTHENTICATION_CLASSES': [
    'accounts.authentication.ExpiringTokenAuthentication',
  ],
  'DEFAULT_THROTTLE_RATES': {
    'auth': os.environ.get('THROTTLE_AUTH_RATE', '20/min'),
    'otp': os.environ.get('THROTTLE_OTP_RATE', '5/min'),
    'directory': os.environ.get('THROTTLE_DIRECTORY_RATE', '60/min'),
      'public_registration': os.environ.get('THROTTLE_PUBLIC_REGISTRATION_RATE', '30/hour'),
      'support': os.environ.get('THROTTLE_SUPPORT_RATE', '30/hour'),
      'errors': os.environ.get('THROTTLE_ERRORS_RATE', '60/min'),
      'payments': os.environ.get('THROTTLE_PAYMENTS_RATE', '30/hour'),
  },
}

REPROOT_AUTH_TOKEN_TTL_HOURS = int(os.environ.get('REPROOT_AUTH_TOKEN_TTL_HOURS', '12'))
REPROOT_LEGAL_LAST_UPDATED_DATE = os.environ.get('REPROOT_LEGAL_LAST_UPDATED_DATE', '2026-08-16').strip()
try:
  date.fromisoformat(REPROOT_LEGAL_LAST_UPDATED_DATE)
except ValueError as exc:
  raise ImproperlyConfigured('REPROOT_LEGAL_LAST_UPDATED_DATE must use YYYY-MM-DD format.') from exc

# Compatibility aliases: existing account rows and API clients still use the
# role-specific version fields. A single configured date now drives both roles
# so every legal screen and acceptance check changes together.
REPROOT_PROFESSIONAL_LEGAL_VERSION = REPROOT_LEGAL_LAST_UPDATED_DATE
REPROOT_CLIENT_LEGAL_VERSION = REPROOT_LEGAL_LAST_UPDATED_DATE
REPROOT_LEGAL_EFFECTIVE_DATE = REPROOT_LEGAL_LAST_UPDATED_DATE
REPROOT_LEGAL_DOCUMENT_VERSION = REPROOT_LEGAL_LAST_UPDATED_DATE
REPROOT_SUPPORTED_COUNTRIES = {
  value.strip().upper()
  for value in os.environ.get('REPROOT_SUPPORTED_COUNTRIES', 'IN,INDIA,US,USA,UNITED STATES,UNITED STATES OF AMERICA').split(',')
  if value.strip()
}
# Limits are tier-aware so premium capacity can change without rewriting API
# views or Angular pages. Existing professionals remain on Starter unless an admin
# explicitly changes their ProfessionalProfile.plan_tier.
REPROOT_DEFAULT_PLAN = os.environ.get('REPROOT_DEFAULT_PLAN', 'starter_free').strip().lower()

# Canonical public plan codes. Legacy codes are retained only as aliases so
# existing database rows resolve to current plans; they do not define another
# set of limits and are not exposed in the billing catalogue.
REPROOT_PLAN_ALIASES = {
  'starter': 'starter_free',
  'premium': 'premium_unlimited',
}

# Storage quotas are still being tuned against real usage data, so the
# Starter Free byte limit stays a single env-configurable knob; Pro and
# Premium Unlimited are derived as multiples of it (10x, 50x respectively —
# i.e. Premium Unlimited is also 5x Pro) unless explicitly overridden.
REPROOT_STARTER_FREE_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_STARTER_FREE_STORAGE_LIMIT_BYTES', str(100 * 1024 * 1024))
)
REPROOT_PRO_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_PRO_STORAGE_LIMIT_BYTES', str(1024 * 1024 * 1024))
)
REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES', str(10 * 1024 * 1024 * 1024))
)

# Public 3-tier billing system: Free / Pro / Premium
REPROOT_PLAN_TIERS = {
  'starter_free': {
    'name': 'Free',
    'lead_forms': int(os.environ.get('REPROOT_STARTER_FREE_LEAD_FORM_LIMIT', '1')),
    'groups': int(os.environ.get('REPROOT_STARTER_FREE_GROUP_LIMIT', '3')),
    'clients': None,
    'templates': int(os.environ.get('REPROOT_STARTER_FREE_TEMPLATE_LIMIT', '5')),
    # Reads the new RESOURCE env var name first, falling back to the old
    # REFERENCE name (in case an existing deployment's .env still sets that)
    # before the hardcoded default -- this feature was renamed from
    # "Reference" to "Resource" but a live .env can't be renamed for you.
    'resources': int(
      os.environ.get('REPROOT_STARTER_FREE_RESOURCE_LIMIT')
      or os.environ.get('REPROOT_STARTER_FREE_REFERENCE_LIMIT')
      or '30'
    ),
    'categories': int(os.environ.get('REPROOT_STARTER_FREE_CATEGORY_LIMIT', '5')),
    'subcategories_per_category': int(os.environ.get('REPROOT_STARTER_FREE_SUBCATEGORY_LIMIT', '3')),
    'professional_storage_bytes': REPROOT_STARTER_FREE_STORAGE_LIMIT_BYTES,
    'client_data_retention_days': int(os.environ.get('REPROOT_STARTER_FREE_DATA_RETENTION_DAYS', '60')),
  },
  'pro': {
    'name': 'Pro',
    'lead_forms': int(os.environ.get('REPROOT_PRO_LEAD_FORM_LIMIT', '2')),
    'groups': int(os.environ.get('REPROOT_PRO_GROUP_LIMIT', '10')),
    'clients': None,
    'templates': int(os.environ.get('REPROOT_PRO_TEMPLATE_LIMIT', '15')),
    'resources': int(
      os.environ.get('REPROOT_PRO_RESOURCE_LIMIT')
      or os.environ.get('REPROOT_PRO_REFERENCE_LIMIT')
      or '100'
    ),
    'categories': int(os.environ.get('REPROOT_PRO_CATEGORY_LIMIT', '20')),
    'subcategories_per_category': int(os.environ.get('REPROOT_PRO_SUBCATEGORY_LIMIT', '10')),
    'professional_storage_bytes': REPROOT_PRO_STORAGE_LIMIT_BYTES,
    'client_data_retention_days': int(os.environ.get('REPROOT_PRO_DATA_RETENTION_DAYS', '90')),
  },
  'premium_unlimited': {
    'name': 'Premium',
    'lead_forms': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_LEAD_FORM_LIMIT', '3')),
    'groups': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_GROUP_LIMIT', '25')),
    'clients': None,
    'templates': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_TEMPLATE_LIMIT', '50')),
    'resources': int(
      os.environ.get('REPROOT_PREMIUM_UNLIMITED_RESOURCE_LIMIT')
      or os.environ.get('REPROOT_PREMIUM_UNLIMITED_REFERENCE_LIMIT')
      or '250'
    ),
    'categories': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_CATEGORY_LIMIT', '50')),
    'subcategories_per_category': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_SUBCATEGORY_LIMIT', '20')),
    'professional_storage_bytes': REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES,
    'client_data_retention_days': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_DATA_RETENTION_DAYS', '180')),
  },
}

# Data usage warning & account lifecycle thresholds
REPROOT_DATA_USAGE_WARNING_PERCENT = int(os.environ.get('REPROOT_DATA_USAGE_WARNING_PERCENT', '75'))
REPROOT_DATA_USAGE_DANGER_PERCENT = int(os.environ.get('REPROOT_DATA_USAGE_DANGER_PERCENT', '90'))
REPROOT_STORAGE_HARD_LIMIT_PERCENT = int(os.environ.get('REPROOT_STORAGE_HARD_LIMIT_PERCENT', '120'))
REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS = int(os.environ.get('REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS', '14'))
REPROOT_DATA_DELETION_DAYS = int(os.environ.get('REPROOT_DATA_DELETION_DAYS', '30'))

# Recycle Bin: how long a soft-deleted item (chat message, tracking/progress
# entry, reminder, reference, template) stays restorable before permanent purge.
REPROOT_RECYCLE_BIN_DAYS = int(os.environ.get('REPROOT_RECYCLE_BIN_DAYS', '14'))
# A deleted professional ACCOUNT is held longer than an individual deleted item.
# Deliberately separate from REPROOT_RECYCLE_BIN_DAYS above: that one governs the
# per-item bin (client accounts, chat images, resources) shown in Settings and
# described to users as 14 days. Changing one must not silently move the other.
REPROOT_PROFESSIONAL_RECYCLE_DAYS = int(os.environ.get('REPROOT_PROFESSIONAL_RECYCLE_DAYS', '30'))
# The optional cooling-off period before a requested deletion becomes real. The
# professional can still sign in during it, and signing in cancels the deletion.
REPROOT_DELETION_HOLD_DAYS = int(os.environ.get('REPROOT_DELETION_HOLD_DAYS', '14'))
# Minimum gap between changes to the username or email a professional signs in
# with. The first change is always allowed regardless of account age.
REPROOT_SIGNIN_CHANGE_COOLDOWN_DAYS = int(os.environ.get('REPROOT_SIGNIN_CHANGE_COOLDOWN_DAYS', '30'))
REPROOT_OPERATIONAL_DATA_MAX_DAYS = int(os.environ.get('REPROOT_OPERATIONAL_DATA_MAX_DAYS', '180'))
REPROOT_ERROR_LOG_RETENTION_DAYS = int(os.environ.get('REPROOT_ERROR_LOG_RETENTION_DAYS', '90'))

# Storage usage is intentionally a calm operational indicator, not a live
# counter that changes while the professional navigates between pages.
REPROOT_DATA_USAGE_CACHE_SECONDS = int(os.environ.get('REPROOT_DATA_USAGE_CACHE_SECONDS', '120'))

# Stripe Billing — self-serve upgrade support for all tiers. Test-mode keys work
# with zero business verification; swap for live keys only when actually
# charging real cards. plan_tier is never written by anything except the
# webhook below, so a Checkout Session that never completes leaves the
# professional on their current tier with no partial state to clean up.
STRIPE_SECRET_KEY = os.environ.get('STRIPE_SECRET_KEY', '')
STRIPE_PUBLISHABLE_KEY = os.environ.get('STRIPE_PUBLISHABLE_KEY', '')
STRIPE_WEBHOOK_SECRET = os.environ.get('STRIPE_WEBHOOK_SECRET', '')
STRIPE_PRO_PRICE_ID = os.environ.get('STRIPE_PRO_PRICE_ID', '')
STRIPE_PREMIUM_UNLIMITED_PRICE_ID = os.environ.get('STRIPE_PREMIUM_UNLIMITED_PRICE_ID', '')
STRIPE_PREMIUM_PRICE_ID = os.environ.get('STRIPE_PREMIUM_PRICE_ID', '')  # Legacy, kept for backward compatibility
REPROOT_BILLING_SUCCESS_URL = os.environ.get(
  'REPROOT_BILLING_SUCCESS_URL', 'http://localhost:4300/professional/account-settings?billing=success'
)
REPROOT_BILLING_CANCEL_URL = os.environ.get(
  'REPROOT_BILLING_CANCEL_URL', 'http://localhost:4300/professional/account-settings?billing=cancelled'
)

# No real Stripe pricing is wired up yet. Rather than hide "Update plan" until
# it exists, checkout falls back to instantly applying the chosen tier with no
# payment involved whenever a tier's real Stripe price isn't configured — lets
# the whole lifecycle (limits, storage quota, lock/grace clearing) be exercised
# end-to-end today. Flip this off once real prices are set for every tier.
# This development shortcut is still subordinate to the master payment lock;
# it cannot change a plan while REPROOT_PAYMENTS_ENABLED is false.
REPROOT_BILLING_TEST_MODE = os.environ.get('REPROOT_BILLING_TEST_MODE', 'True' if DEBUG else 'False').lower() == 'true'

# Razorpay is backend-only. Never expose the key secret or webhook secret to
# either frontend. The public key ID is returned only as part of checkout.
RAZORPAY_KEY_ID = os.environ.get('RAZORPAY_KEY_ID', '')
RAZORPAY_KEY_SECRET = os.environ.get('RAZORPAY_KEY_SECRET', '')
RAZORPAY_WEBHOOK_SECRET = os.environ.get('RAZORPAY_WEBHOOK_SECRET', '')
RAZORPAY_BASE_URL = os.environ.get('RAZORPAY_BASE_URL', 'https://api.razorpay.com').rstrip('/')
RAZORPAY_PERSONAL_LINK = os.environ.get('RAZORPAY_PERSONAL_LINK', '')
REPROOT_BILLING_PROVIDER = os.environ.get('REPROOT_BILLING_PROVIDER', 'razorpay').strip().lower()
REPROOT_ADS_ENABLED = False
# Payment mutations stay locked for the testing launch. Enable only after the
# selected provider, webhook verification, and production credentials are ready.
REPROOT_PAYMENTS_ENABLED = os.environ.get('REPROOT_PAYMENTS_ENABLED', 'False').lower() == 'true'

# Manual payment tracking -- reporting currency, a professional's own payment
# methods, payment requests and proofs between them and their clients -- is a
# core part of the product and involves no payment provider at all.
#
# It is deliberately NOT governed by REPROOT_PAYMENTS_ENABLED. That flag exists
# to stop professionals changing subscription tier, and pointing it at this as
# well meant switching off plan upgrades also silently froze the manual payment
# workspace: the screen loaded, the form accepted input, and every save came
# back 503. Separate concerns, separate switches.
REPROOT_MANUAL_PAYMENTS_ENABLED = (
  os.environ.get('REPROOT_MANUAL_PAYMENTS_ENABLED', 'True').lower() == 'true'
)

# Base URL used when building links inside notification emails (Client Payments).
REPROOT_FRONTEND_URL = os.environ.get('REPROOT_FRONTEND_URL', 'http://localhost:4300')


def _normalized_domain_set(variable_name, default=''):
  return {
    domain.strip().lower().rstrip('.')
    for domain in os.environ.get(variable_name, default).split(',')
    if domain.strip()
  }


# Keep the allowlist empty to accept legitimate business domains. During a
# controlled public test it can be set to selected consumer providers. The
# blocklist applies in both modes and contains only disposable/reserved domains.
REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS = _normalized_domain_set(
  'REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS'
)
REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS = _normalized_domain_set(
  'REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS',
  'example.com,example.org,example.net,example.test,localhost,mailinator.com,guerrillamail.com,10minutemail.com',
)
