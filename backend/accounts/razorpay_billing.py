"""Backend-only Razorpay payment-link integration."""

import hashlib
import hmac
from datetime import timedelta
from decimal import Decimal

import requests
from django.conf import settings
from django.utils import timezone


PLAN_PRICES = {
  'pro': {
    'monthly': {'INR': Decimal('299'), 'USD': Decimal('5.99'), 'months': 1},
    'six_months': {'INR': Decimal('1495'), 'USD': Decimal('29.95'), 'months': 6},
    'yearly': {'INR': Decimal('2990'), 'USD': Decimal('59.90'), 'months': 12},
  },
  'premium_unlimited': {
    'monthly': {'INR': Decimal('999'), 'USD': Decimal('14.99'), 'months': 1},
    'six_months': {'INR': Decimal('4995'), 'USD': Decimal('74.95'), 'months': 6},
    'yearly': {'INR': Decimal('9990'), 'USD': Decimal('149.90'), 'months': 12},
  },
}

CLIENT_AD_FREE_PRICES = {
  'monthly': {'INR': Decimal('49'), 'USD': Decimal('2.99'), 'months': 1},
}


class RazorpayError(RuntimeError):
  pass


def is_configured():
  return bool(settings.RAZORPAY_KEY_ID and settings.RAZORPAY_KEY_SECRET and settings.RAZORPAY_WEBHOOK_SECRET)


def public_catalog():
  def serialize(prices):
    return {
      cycle: {
        'months': values['months'],
        'INR': str(values['INR']),
        'USD': str(values['USD']),
      }
      for cycle, values in prices.items()
    }

  return {
    'provider': 'razorpay',
    'trainer': {tier: serialize(prices) for tier, prices in PLAN_PRICES.items()},
    'client_ad_free': serialize(CLIENT_AD_FREE_PRICES),
    'cycles': [
      {'code': 'monthly', 'name': 'Monthly', 'charged_months': 1},
      {'code': 'six_months', 'name': '6 Months', 'charged_months': 5},
      {'code': 'yearly', 'name': 'Yearly', 'charged_months': 10},
    ],
  }


def create_payment_link(profile, target_tier, billing_cycle, currency):
  price = PLAN_PRICES.get(target_tier, {}).get(billing_cycle)
  currency = currency.upper()
  if not price or currency not in ('INR', 'USD'):
    raise ValueError('Unsupported plan, billing cycle, or currency.')
  if not is_configured():
    raise RazorpayError('Razorpay billing is not configured.')

  user = profile.user
  payload = {
    'amount': int(price[currency] * 100),
    'currency': currency,
    'accept_partial': False,
    'description': f'RepRoot {target_tier} - {billing_cycle}',
    'customer': {
      'name': user.get_full_name() or user.username,
      'email': user.email,
    },
    'notify': {'email': True, 'sms': False},
    'callback_url': settings.REPROOT_BILLING_SUCCESS_URL,
    'callback_method': 'get',
    'notes': {
      'professional_user_id': str(user.id),
      'target_tier': target_tier,
      'billing_cycle': billing_cycle,
      'months': str(price['months']),
    },
  }
  response = requests.post(
    f'{settings.RAZORPAY_BASE_URL}/v1/payment_links',
    json=payload,
    auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET),
    timeout=15,
  )
  if not response.ok:
    raise RazorpayError('Razorpay could not create the checkout link.')
  return response.json()


def verify_webhook(raw_body, signature):
  expected = hmac.new(
    settings.RAZORPAY_WEBHOOK_SECRET.encode('utf-8'),
    raw_body,
    hashlib.sha256,
  ).hexdigest()
  return bool(signature) and hmac.compare_digest(expected, signature)


def renewal_date(months):
  # Razorpay payment links are prepaid terms. Thirty-day units keep expiry
  # deterministic without requiring database/provider plan IDs.
  return timezone.now() + timedelta(days=int(months) * 30)
