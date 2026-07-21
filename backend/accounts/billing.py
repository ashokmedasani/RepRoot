"""Stripe Billing — self-serve Starter -> Premium upgrade.

The only thing that ever writes ``ProfessionalProfile.plan_tier`` is the webhook
in views.py, driven by events Stripe sends after a real payment state
change. Checkout/Portal session creation here never touches plan_tier
itself, so an abandoned checkout leaves no partial state to reconcile.
"""

import stripe
from django.conf import settings


def _configured_client():
  stripe.api_key = settings.STRIPE_SECRET_KEY
  return stripe


def get_or_create_customer(profile) -> str:
  if profile.stripe_customer_id:
    return profile.stripe_customer_id

  client = _configured_client()
  user = profile.user
  full_name = f'{user.first_name} {user.last_name}'.strip() or user.username
  customer = client.Customer.create(
    email=user.email,
    name=full_name,
    metadata={
      'professional_user_id': str(user.id),
      'professional_reference': profile.internal_reference_code,
    },
  )
  profile.stripe_customer_id = customer.id
  profile.save(update_fields=['stripe_customer_id'])
  return customer.id


# Maps the tier a professional picks in the UI to the Stripe Price they're
# actually charged. Keeping this here (rather than in views.py) means the
# webhook and the checkout-session creator agree on the same price->tier
# mapping in both directions — see resolve_tier_from_price() below.
TARGET_TIER_PRICE_IDS = {
  'pro': settings.STRIPE_PRO_PRICE_ID,
  'premium_unlimited': settings.STRIPE_PREMIUM_UNLIMITED_PRICE_ID,
}


def price_id_for_tier(target_tier: str) -> str:
  return TARGET_TIER_PRICE_IDS.get(target_tier, '')


def resolve_tier_from_price(price_id: str) -> str | None:
  """Reverse lookup used by the webhook to find which tier a Stripe
  subscription price corresponds to, including the legacy Premium price."""
  from .models import ProfessionalProfile

  if not price_id:
    return None
  if price_id == settings.STRIPE_PRO_PRICE_ID:
    return ProfessionalProfile.PLAN_PRO
  if price_id == settings.STRIPE_PREMIUM_UNLIMITED_PRICE_ID:
    return ProfessionalProfile.PLAN_PREMIUM_UNLIMITED
  if price_id == settings.STRIPE_PREMIUM_PRICE_ID:
    return ProfessionalProfile.PLAN_PREMIUM
  return None


def create_checkout_session(profile, target_tier: str) -> str:
  price_id = price_id_for_tier(target_tier)
  if not price_id:
    raise ValueError(f'No Stripe price configured for tier "{target_tier}".')

  client = _configured_client()
  customer_id = get_or_create_customer(profile)
  session = client.checkout.Session.create(
    customer=customer_id,
    mode='subscription',
    line_items=[{'price': price_id, 'quantity': 1}],
    success_url=settings.REPROOT_BILLING_SUCCESS_URL,
    cancel_url=settings.REPROOT_BILLING_CANCEL_URL,
    client_reference_id=str(profile.user_id),
    metadata={'professional_user_id': str(profile.user_id), 'target_tier': target_tier},
  )
  return session.url


def cancel_subscription(profile) -> None:
  """Cancels the professional's active Stripe subscription immediately.
  The subscription.deleted webhook then routes the plan back to Starter Free
  through account_lifecycle.process_downgrade — this function only talks to
  Stripe, it never touches plan_tier itself."""
  if not profile.stripe_subscription_id:
    return
  client = _configured_client()
  client.Subscription.delete(profile.stripe_subscription_id)


def create_portal_session(profile) -> str | None:
  if not profile.stripe_customer_id:
    return None
  client = _configured_client()
  session = client.billing_portal.Session.create(
    customer=profile.stripe_customer_id,
    return_url=settings.REPROOT_BILLING_CANCEL_URL,
  )
  return session.url
