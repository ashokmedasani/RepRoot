"""Shared constants for the Client Payments module.

Client Payments tracks money professionals collect from their own clients.
It is fully separate from RepRoot Billing (billing.py), which handles
professionals paying RepRoot for their subscription tier.
"""

from decimal import Decimal

from .upload_limits import IMAGE_MAX_BYTES, PDF_MAX_BYTES

# Currencies a professional can pick for reporting or attach to a request.
# ISO 4217 alpha-3 codes only.
ISO_4217_CODES = frozenset({
  'AED', 'AUD', 'BDT', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP',
  'HKD', 'IDR', 'ILS', 'INR', 'JPY', 'KRW', 'LKR', 'MXN', 'MYR', 'NOK',
  'NPR', 'NZD', 'PHP', 'PKR', 'PLN', 'SAR', 'SEK', 'SGD', 'THB', 'TRY',
  'USD', 'VND', 'ZAR',
})

# Currencies surfaced first in dropdowns; the rest are listed alphabetically.
FEATURED_CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'CAD', 'AUD']

# Per-category client-visible keys that must be present before a manual
# payment profile can be shared with anyone. Categories not listed only need
# a display label (e.g. cash).
CATEGORY_REQUIRED_CLIENT_FIELDS = {
  'upi': ['upi_id'],
  'google_pay': ['upi_id'],
  'phonepe': ['upi_id'],
  'paytm': ['upi_id'],
  'bank_transfer': ['account_holder_name', 'bank_name'],
  'zelle': ['recipient_name', 'contact'],
  'venmo': ['handle'],
  'cash_app': ['handle'],
  'paypal_manual': ['contact'],
  'cash': [],
  'other': [],
}

# Payment uploads follow the same product-wide ceilings as every other upload
# (see upload_limits.py). A proof can be a PDF receipt or a photo, so it is
# sized by what the bytes actually turn out to be rather than by one number.
PAYMENT_PROOF_MAX_BYTES = PDF_MAX_BYTES
PAYMENT_PROOF_IMAGE_MAX_BYTES = IMAGE_MAX_BYTES
PAYMENT_QR_MAX_BYTES = IMAGE_MAX_BYTES

PAYMENT_QR_CONTENT_TYPES = frozenset({'image/png', 'image/jpeg', 'image/webp'})
PAYMENT_PROOF_CONTENT_TYPES = frozenset({'image/png', 'image/jpeg', 'image/webp', 'application/pdf'})

# Static, manually maintained estimates used ONLY to pre-fill the reporting
# amount field; the professional always confirms or overrides the value.
# Never treat these as settlement rates.
ESTIMATED_RATES_TO_USD = {
  'AED': Decimal('0.27'), 'AUD': Decimal('0.66'), 'BDT': Decimal('0.0084'),
  'BRL': Decimal('0.18'), 'CAD': Decimal('0.73'), 'CHF': Decimal('1.12'),
  'CNY': Decimal('0.14'), 'DKK': Decimal('0.145'), 'EUR': Decimal('1.08'),
  'GBP': Decimal('1.27'), 'HKD': Decimal('0.128'), 'IDR': Decimal('0.000063'),
  'ILS': Decimal('0.27'), 'INR': Decimal('0.0120'), 'JPY': Decimal('0.0067'),
  'KRW': Decimal('0.00073'), 'LKR': Decimal('0.0033'), 'MXN': Decimal('0.055'),
  'MYR': Decimal('0.21'), 'NOK': Decimal('0.092'), 'NPR': Decimal('0.0075'),
  'NZD': Decimal('0.60'), 'PHP': Decimal('0.017'), 'PKR': Decimal('0.0036'),
  'PLN': Decimal('0.25'), 'SAR': Decimal('0.27'), 'SEK': Decimal('0.094'),
  'SGD': Decimal('0.74'), 'THB': Decimal('0.028'), 'TRY': Decimal('0.030'),
  'USD': Decimal('1'), 'VND': Decimal('0.000040'), 'ZAR': Decimal('0.053'),
}


def estimate_reporting_amount(amount, from_currency, to_currency):
  """Rough pre-fill estimate between two currencies via USD. Returns None
  when either currency is unknown so callers fall back to manual entry."""
  if from_currency == to_currency:
    return amount
  from_rate = ESTIMATED_RATES_TO_USD.get(from_currency)
  to_rate = ESTIMATED_RATES_TO_USD.get(to_currency)
  if not from_rate or not to_rate:
    return None
  return (amount * from_rate / to_rate).quantize(Decimal('0.01'))
