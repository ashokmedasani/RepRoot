# backend/accounts/email_verification.py

## What this file does

Generates email OTP codes, sends them through Django email, verifies submitted OTP codes, and issues temporary verification tokens for signup and password reset flows.

## Why this file exists

Trainer signup needs a free local email verification flow for testing without paying for an email provider.

## Page or module

Backend accounts module for trainer authentication testing.

## Important functions/classes/components

- `send_email_otp`: generates a six-digit OTP, stores it in cache by purpose, and sends it through Django email.
- `verify_email_otp`: validates an OTP for the requested purpose and returns a temporary verification token.
- `consume_verified_email_token`: consumes the temporary token during signup or password reset.
- `OtpCooldownError`: reports when an OTP is requested before the resend cooldown expires.

## Data flow

The signup or password reset page requests an OTP. Django stores the OTP in local cache and prints the email through the console email backend. The user enters the OTP, receives a purpose-specific verification token, and the matching final action consumes that token.

## Connected files

- `backend/accounts/views.py`
- `backend/accounts/serializers.py`
- `backend/config/settings.py`

## Business logic

OTPs expire after 10 minutes. Verification tokens expire after 30 minutes and are consumed during signup or password reset. Signup and password reset tokens are separated by purpose so they cannot be reused across flows. OTP resend is blocked for 30 seconds, and an OTP is invalidated after five failed verification attempts.

## Assumptions made

The console email backend is acceptable for local testing.

## Future improvement notes

Replace console email with a real provider such as Mailtrap, Resend, Brevo, SES, or SendGrid before production.
