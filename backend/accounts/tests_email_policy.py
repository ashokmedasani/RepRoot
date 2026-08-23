from django.test import SimpleTestCase, override_settings

from .serializers import EmailAvailabilitySerializer, EmailOtpRequestSerializer, get_public_form_link


class SignupEmailPolicyTests(SimpleTestCase):
  @override_settings(
    REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS={'gmail.com', 'outlook.com'},
    REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS={'mailinator.com'},
  )
  def test_allowlist_rejects_unapproved_domain_before_otp_delivery(self):
    serializer = EmailOtpRequestSerializer(data={'email': 'person@expedia.com'})

    self.assertFalse(serializer.is_valid())
    self.assertIn('approved providers', str(serializer.errors['email'][0]))

  @override_settings(
    REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS={'gmail.com'},
    REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS={'mailinator.com'},
  )
  def test_allowlist_accepts_approved_domain(self):
    serializer = EmailAvailabilitySerializer(data={'email': 'Person@Gmail.com'})

    self.assertTrue(serializer.is_valid(), serializer.errors)
    self.assertEqual(serializer.validated_data['email'], 'person@gmail.com')

  @override_settings(
    REPROOT_SIGNUP_ALLOWED_EMAIL_DOMAINS=set(),
    REPROOT_SIGNUP_BLOCKED_EMAIL_DOMAINS={'mailinator.com'},
  )
  def test_empty_allowlist_still_blocks_disposable_domain(self):
    serializer = EmailOtpRequestSerializer(data={'email': 'person@mailinator.com'})

    self.assertFalse(serializer.is_valid())


class PublicLeadFormLinkTests(SimpleTestCase):
  @override_settings(REPROOT_FRONTEND_URL='https://rep-root.com/')
  def test_link_uses_canonical_studio_origin_without_request_origin(self):
    self.assertEqual(
      get_public_form_link(None, 'professional-intake'),
      'https://rep-root.com/public/forms/professional-intake',
    )
