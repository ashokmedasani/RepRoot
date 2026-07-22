from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from accounts.models import ClientAccess, ProfessionalGroup, ProfessionalProfile

from .audit import client_log_identity, professional_log_identity
from .models import AdminAuditLog, AdminRole, AdminStaffProfile


class AdminPortalPhaseOneTests(TestCase):
  def setUp(self):
    User = get_user_model()
    self.super_user = User.objects.create_user('internaladmin', 'admin@reproot.test', 'StrongAdmin!42')
    self.super_staff = AdminStaffProfile.objects.create(
      user=self.super_user, role=AdminRole.objects.get(slug='super-admin')
    )
    self.super_token = Token.objects.create(user=self.super_user)
    self.professional = User.objects.create_user('coachlee', 'coach@example.test', 'ProfessionalPass!42')
    self.profile = ProfessionalProfile.objects.create(
      user=self.professional, professional_id='coach-lee', profile_setup_completed=True
    )
    self.group = ProfessionalGroup.objects.create(professional=self.professional, name='Core Group')
    self.client_record = ClientAccess.objects.create(
      professional=self.professional, group=self.group, first_name='Riya', last_name='K',
      email='riya@example.test', username='riya', temporary_password='not-a-real-password',
    )
    self.api = APIClient()

  def authenticate_super(self):
    self.api.credentials(HTTP_AUTHORIZATION=f'Token {self.super_token.key}')

  def test_unauthorized_user_cannot_access_admin_dashboard(self):
    self.assertEqual(self.api.get('/api/admin/dashboard/').status_code, 401)

  def test_super_admin_can_recycle_and_restore_verified_professional(self):
    self.authenticate_super()
    reference = self.profile.internal_reference_code
    recycle = self.api.post(
      f'/api/admin/account-lifecycle/{reference}/action/',
      {
        'action': 'move_to_recycle', 'reason': 'Identity and consent verified in support case.',
        'confirmed_identity': True, 'confirmed_consent': True,
      },
      format='json',
    )
    self.assertEqual(recycle.status_code, 200)
    self.profile.refresh_from_db()
    self.assertEqual(self.profile.lifecycle_status, ProfessionalProfile.LIFECYCLE_RECYCLED)

    restore = self.api.post(
      f'/api/admin/account-lifecycle/{reference}/action/',
      {'action': 'restore', 'reason': 'Trainer requested restoration inside 14 days.'},
      format='json',
    )
    self.assertEqual(restore.status_code, 200)
    self.profile.refresh_from_db()
    self.assertEqual(self.profile.lifecycle_status, ProfessionalProfile.LIFECYCLE_ACTIVE)

  def test_professional_token_cannot_access_admin_dashboard(self):
    token = Token.objects.create(user=self.professional)
    self.api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
    self.assertEqual(self.api.get('/api/admin/dashboard/').status_code, 403)

  def test_admin_login_and_dashboard_create_audit_history(self):
    response = self.api.post('/api/admin/login/', {'identifier': 'internaladmin', 'password': 'StrongAdmin!42'})
    self.assertEqual(response.status_code, 200)
    self.assertIn('admin.finance.view', response.data['staff']['permissions'])
    self.api.credentials(HTTP_AUTHORIZATION=f"Token {response.data['token']}")
    dashboard = self.api.get('/api/admin/dashboard/')
    self.assertEqual(dashboard.status_code, 200)
    self.assertEqual(dashboard.data['accounts']['total_professionals'], 1)
    self.assertTrue(AdminAuditLog.objects.filter(action='VIEW_ADMIN_DASHBOARD').exists())

  def test_finance_is_a_separate_permission_controlled_endpoint(self):
    self.authenticate_super()
    response = self.api.get('/api/admin/finance/')
    self.assertEqual(response.status_code, 200)
    self.assertEqual(response.data['billing_provider'], 'Not configured')
    self.assertIn('gross_revenue', response.data['summary'])

  def test_support_agent_cannot_access_finance_or_audit_logs(self):
    User = get_user_model()
    user = User.objects.create_user('supporter', 'support@example.test', 'SupportPass!42')
    staff = AdminStaffProfile.objects.create(user=user, role=AdminRole.objects.get(slug='support-agent'))
    token = Token.objects.create(user=user)
    self.api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
    self.assertEqual(self.api.get('/api/admin/finance/').status_code, 403)
    self.assertEqual(self.api.get('/api/admin/audit-logs/').status_code, 403)

  def test_log_identities_use_immutable_professional_and_client_references(self):
    self.assertEqual(professional_log_identity(self.professional), f'coachlee · {self.profile.internal_reference_code}')
    self.assertEqual(client_log_identity(self.client_record), f'coachlee:{self.client_record.reference_id}')

  def test_audit_log_cannot_be_edited(self):
    log = AdminAuditLog.objects.create(
      staff=self.super_staff, action='TEST', correlation_id='ADM-TEST-1', target_display='Test target'
    )
    log.reason = 'changed'
    with self.assertRaises(ValueError):
      log.save()
