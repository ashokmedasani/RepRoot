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

# 10.0.2.2 is how the Android emulator reaches this PC's localhost.
default_allowed_hosts = ['localhost', '127.0.0.1', '10.0.2.2']
render_external_hostname = os.environ.get('RENDER_EXTERNAL_HOSTNAME', '').strip()

if render_external_hostname:
  default_allowed_hosts.append(render_external_hostname)

ALLOWED_HOSTS = [
  host.strip()
  for host in os.environ.get('DJANGO_ALLOWED_HOSTS', ','.join(default_allowed_hosts)).split(',')
  if host.strip()
]

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

if not DEBUG and EMAIL_BACKEND == 'django.core.mail.backends.console.EmailBackend':
  raise ImproperlyConfigured('Configure a production EMAIL_BACKEND and EMAIL_HOST before deployment.')

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

SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
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
    'rest_framework.authentication.TokenAuthentication',
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

# Limits are tier-aware so premium capacity can change without rewriting API
# views or Angular pages. Existing professionals remain on Starter unless an admin
# explicitly changes their ProfessionalProfile.plan_tier.
REPROOT_DEFAULT_PLAN = os.environ.get('REPROOT_DEFAULT_PLAN', 'starter_free').strip().lower()

# Storage quotas are still being tuned against real usage data, so the
# Starter Free byte limit stays a single env-configurable knob; Pro and
# Premium Unlimited are derived as multiples of it (5x, 50x respectively —
# i.e. Premium Unlimited is also 10x Pro) unless explicitly overridden.
REPROOT_STARTER_FREE_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_STARTER_FREE_STORAGE_LIMIT_BYTES', str(100 * 1024 * 1024))
)
REPROOT_PRO_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_PRO_STORAGE_LIMIT_BYTES', str(1024 * 1024 * 1024))
)
REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES = int(
  os.environ.get('REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES', str(5 * 1024 * 1024 * 1024))
)

# 3-Tier Billing System: Starter Free / Pro / Premium Unlimited
REPROOT_PLAN_TIERS = {
  'starter_free': {
    'name': 'Starter Free',
    'lead_forms': int(os.environ.get('REPROOT_STARTER_FREE_LEAD_FORM_LIMIT', '1')),
    'groups': int(os.environ.get('REPROOT_STARTER_FREE_GROUP_LIMIT', '3')),
    'clients': None,
    'templates': int(os.environ.get('REPROOT_STARTER_FREE_TEMPLATE_LIMIT', '5')),
    'references': int(os.environ.get('REPROOT_STARTER_FREE_REFERENCE_LIMIT', '30')),
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
    'references': int(os.environ.get('REPROOT_PRO_REFERENCE_LIMIT', '100')),
    'categories': int(os.environ.get('REPROOT_PRO_CATEGORY_LIMIT', '20')),
    'subcategories_per_category': int(os.environ.get('REPROOT_PRO_SUBCATEGORY_LIMIT', '10')),
    'professional_storage_bytes': REPROOT_PRO_STORAGE_LIMIT_BYTES,
    'client_data_retention_days': int(os.environ.get('REPROOT_PRO_DATA_RETENTION_DAYS', '90')),
  },
  'premium_unlimited': {
    'name': 'Premium Unlimited',
    'lead_forms': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_LEAD_FORM_LIMIT', '3')),
    'groups': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_GROUP_LIMIT', '999')),
    'clients': None,
    'templates': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_TEMPLATE_LIMIT', '50')),
    'references': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_REFERENCE_LIMIT', '1000')),
    'categories': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_CATEGORY_LIMIT', '50')),
    'subcategories_per_category': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_SUBCATEGORY_LIMIT', '20')),
    'professional_storage_bytes': REPROOT_PREMIUM_UNLIMITED_STORAGE_LIMIT_BYTES,
    'client_data_retention_days': int(os.environ.get('REPROOT_PREMIUM_UNLIMITED_DATA_RETENTION_DAYS', '180')),
  },
  # Legacy tiers (for backward compatibility during migration)
  'starter': {
    'name': 'Starter (Legacy)',
    'lead_forms': 1, 'groups': 5, 'clients': None, 'templates': 5,
    'references': 100, 'categories': 10, 'subcategories_per_category': 5,
    'professional_storage_bytes': 50 * 1024 * 1024,
    'client_data_retention_days': 60,
  },
  'premium': {
    'name': 'Premium (Legacy)',
    'lead_forms': 3, 'groups': 25, 'clients': None, 'templates': 50,
    'references': 1000, 'categories': 50, 'subcategories_per_category': 20,
    'professional_storage_bytes': 1024 * 1024 * 1024,
    'client_data_retention_days': 180,
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
REPROOT_OPERATIONAL_DATA_MAX_DAYS = int(os.environ.get('REPROOT_OPERATIONAL_DATA_MAX_DAYS', '180'))

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
REPROOT_BILLING_TEST_MODE = os.environ.get('REPROOT_BILLING_TEST_MODE', 'True' if DEBUG else 'False').lower() == 'true'

# Base URL used when building links inside notification emails (Client Payments).
REPROOT_FRONTEND_URL = os.environ.get('REPROOT_FRONTEND_URL', 'http://localhost:4300')
