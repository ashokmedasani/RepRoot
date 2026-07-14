from pathlib import Path
import os

import dj_database_url
from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

DEVELOPMENT_SECRET_KEY = 'local-development-only-secret-key'
SECRET_KEY = os.environ.get('DJANGO_SECRET_KEY', DEVELOPMENT_SECRET_KEY)
DEBUG = os.environ.get('DJANGO_DEBUG', 'True').lower() == 'true'

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
      'NAME': os.environ.get('POSTGRES_DB', 'trainer_platform'),
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
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', EMAIL_HOST_USER or 'no-reply@coachflow.local')

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
      'LOCATION': 'coachflow-local-cache',
    }
  }

# 4300 = web frontend. 4400 = mobile app browser preview (only while you run it).
# http://localhost + capacitor://localhost = the native Android app's WebView origin.
CORS_ALLOWED_ORIGINS = [
  origin.strip()
  for origin in os.environ.get(
    'CORS_ALLOWED_ORIGINS',
    'http://localhost:4300,http://127.0.0.1:4300,http://localhost:4400,http://127.0.0.1:4400,http://localhost:4401,http://127.0.0.1:4401,http://localhost,https://localhost,capacitor://localhost',
  ).split(',')
  if origin.strip()
]

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
  },
}

# Limits are tier-aware so premium capacity can change without rewriting API
# views or Angular pages. Existing trainers remain on Starter unless an admin
# explicitly changes their TrainerProfile.plan_tier.
COACHFLOW_DEFAULT_PLAN = os.environ.get('COACHFLOW_DEFAULT_PLAN', 'starter').strip().lower()
COACHFLOW_PLAN_TIERS = {
  'starter': {
    'name': 'Starter',
    'lead_forms': int(os.environ.get('COACHFLOW_STARTER_LEAD_FORM_LIMIT', '1')),
    'groups': int(os.environ.get('COACHFLOW_STARTER_GROUP_LIMIT', '5')),
    'clients': int(os.environ.get('COACHFLOW_STARTER_CLIENT_LIMIT', '100')),
    'templates': int(os.environ.get('COACHFLOW_STARTER_TEMPLATE_LIMIT', '5')),
    'references': int(os.environ.get('COACHFLOW_STARTER_REFERENCE_LIMIT', '100')),
    'categories': int(os.environ.get('COACHFLOW_STARTER_CATEGORY_LIMIT', '10')),
    'subcategories_per_category': int(os.environ.get('COACHFLOW_STARTER_SUBCATEGORY_LIMIT', '5')),
    'trainer_storage_bytes': int(os.environ.get('COACHFLOW_STARTER_STORAGE_LIMIT_BYTES', str(50 * 1024 * 1024))),
  },
  'premium': {
    'name': 'Premium',
    'lead_forms': int(os.environ.get('COACHFLOW_PREMIUM_LEAD_FORM_LIMIT', '3')),
    'groups': int(os.environ.get('COACHFLOW_PREMIUM_GROUP_LIMIT', '25')),
    'clients': int(os.environ.get('COACHFLOW_PREMIUM_CLIENT_LIMIT', '1000')),
    'templates': int(os.environ.get('COACHFLOW_PREMIUM_TEMPLATE_LIMIT', '50')),
    'references': int(os.environ.get('COACHFLOW_PREMIUM_REFERENCE_LIMIT', '1000')),
    'categories': int(os.environ.get('COACHFLOW_PREMIUM_CATEGORY_LIMIT', '50')),
    'subcategories_per_category': int(os.environ.get('COACHFLOW_PREMIUM_SUBCATEGORY_LIMIT', '20')),
    'trainer_storage_bytes': int(os.environ.get('COACHFLOW_PREMIUM_STORAGE_LIMIT_BYTES', str(1024 * 1024 * 1024))),
  },
}

# Storage usage is intentionally a calm operational indicator, not a live
# counter that changes while the trainer navigates between pages.
COACHFLOW_DATA_USAGE_CACHE_SECONDS = int(os.environ.get('COACHFLOW_DATA_USAGE_CACHE_SECONDS', '900'))
