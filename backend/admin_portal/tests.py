from django.contrib.auth import get_user_model
from django.test import TestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient

from accounts.models import ClientAccess, ProfessionalGroup, ProfessionalProfile

from .audit import client_log_identity, professional_log_identity
from .models import AdminAuditLog, AdminRole, AdminStaffProfile, FinanceLedgerEntry, PlatformExpense, SupportAccessGrant


class AdminPortalPhaseOneTests(TestCase):
  def setUp(self):
    User = get_user_model()
    self.super_user = User.objects.create_user('internaladmin', 'admin@reproot.test', 'StrongAdmin!42')
    self.super_staff = AdminStaffProfile.objects.create(
      user=self.super_user, role=AdminRole.objects.get(slug='super-admin'),
      department='OWNER', authority_level=100, is_owner=True, must_change_password=False,
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
    self.assertIn('revenue_by_currency', response.data['summary'])
    self.assertIn('expense_by_currency', response.data['summary'])

  def test_private_client_payment_volume_is_excluded_from_business_finance(self):
    from django.utils import timezone
    FinanceLedgerEntry.objects.create(entry_type='PAYMENT', status='COMPLETED', amount='999.00', currency='USD', source='client_payment', occurred_at=timezone.now())
    self.authenticate_super()
    response = self.api.get('/api/admin/finance/?range=lifetime')
    self.assertEqual(response.data['summary']['revenue_by_currency'], {})

  def test_super_admin_can_record_multicurrency_platform_expense(self):
    self.authenticate_super()
    response = self.api.post('/api/admin/finance/', {'amount':'1250.50','currency':'INR','category':'SOFTWARE','expense_date':'2026-07-21','description':'Monitoring tools'}, format='json')
    self.assertEqual(response.status_code, 201)
    self.assertTrue(PlatformExpense.objects.filter(currency='INR', amount='1250.50').exists())

  def test_super_admin_can_list_team_permission_matrix(self):
    self.authenticate_super()
    response = self.api.get('/api/admin/team/')
    self.assertEqual(response.status_code, 200)
    self.assertTrue(any(item['code'] == 'admin.finance.edit' for item in response.data['permissions']))

  def test_support_agent_cannot_access_finance_or_audit_logs(self):
    User = get_user_model()
    user = User.objects.create_user('supporter', 'support@example.test', 'SupportPass!42')
    staff = AdminStaffProfile.objects.create(user=user, role=AdminRole.objects.get(slug='support-agent'), must_change_password=False)
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

  def test_owner_account_cannot_be_modified_from_team_management(self):
    self.authenticate_super()
    response = self.api.put(
      f'/api/admin/team/{self.super_staff.staff_id}/',
      {'status': 'DISABLED'}, format='json',
    )
    self.assertEqual(response.status_code, 403)
    self.super_staff.refresh_from_db()
    self.assertEqual(self.super_staff.status, AdminStaffProfile.STATUS_ACTIVE)

  def test_temporary_staff_must_change_password_before_admin_access(self):
    User = get_user_model()
    user = User.objects.create_user('newstaff', 'newstaff@example.test', 'Temporary!42')
    staff = AdminStaffProfile.objects.create(
      user=user, role=AdminRole.objects.get(slug='support-agent'),
      department='SUPPORT', authority_level=10, must_change_password=True,
    )
    token = Token.objects.create(user=user)
    self.api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
    self.assertEqual(self.api.get('/api/admin/dashboard/').status_code, 403)
    changed = self.api.post('/api/admin/change-password/', {
      'current_password': 'Temporary!42', 'password': 'PrivateNew!42',
      'confirm_password': 'PrivateNew!42',
    }, format='json')
    self.assertEqual(changed.status_code, 200)
    staff.refresh_from_db()
    self.assertFalse(staff.must_change_password)
    self.assertFalse(Token.objects.filter(user=user).exists())

  def test_department_admin_cannot_manage_another_department(self):
    User = get_user_model()
    manager_user = User.objects.create_user('supportmanager', 'manager@example.test', 'ManagerPass!42')
    manager = AdminStaffProfile.objects.create(
      user=manager_user, role=AdminRole.objects.get(slug='support-admin'),
      department='SUPPORT', authority_level=50, must_change_password=False,
    )
    finance_user = User.objects.create_user('financestaff', 'finance@example.test', 'FinancePass!42')
    finance_staff = AdminStaffProfile.objects.create(
      user=finance_user, role=AdminRole.objects.get(slug='read-only-analyst'),
      department='FINANCE', authority_level=10, must_change_password=False,
    )
    token = Token.objects.create(user=manager_user)
    self.api.credentials(HTTP_AUTHORIZATION=f'Token {token.key}')
    response = self.api.put(
      f'/api/admin/team/{finance_staff.staff_id}/', {'status': 'DISABLED'}, format='json'
    )
    self.assertEqual(response.status_code, 403)

  def test_owner_can_view_all_operations_surfaces_without_private_content(self):
    self.authenticate_super()
    for url in ('/api/admin/operations/','/api/admin/users/','/api/admin/communications/','/api/admin/health/'):
      response=self.api.get(url)
      self.assertEqual(response.status_code,200,url)
    directory=self.api.get('/api/admin/users/?search=riya')
    self.assertEqual(directory.data['results'][0]['type'],'client')
    self.assertNotIn('professional_notes',directory.data['results'][0])
    self.assertNotIn('registration_answers',directory.data['results'][0])

  def test_controlled_support_action_requires_active_consent_grant(self):
    incident = __import__('accounts.models',fromlist=['SupportIncident']).SupportIncident.objects.create(
      reporter_role='professional', reporter_professional=self.professional,
      reporter_name='Coach Lee', reporter_email='coach@example.test', category='account_issue',
      subject='Locked out', description='Cannot access account.'
    )
    self.authenticate_super()
    denied=self.api.post(f'/api/admin/support/incidents/{incident.incident_id}/controlled-action/',{'action':'unlock_account','reason':'Verified ticket'},format='json')
    self.assertEqual(denied.status_code,403)
    access=self.api.post(f'/api/admin/support/incidents/{incident.incident_id}/access/',{'scope':'metadata','reason':'Investigate lockout','consent_reference':'USER-REPLY-1'},format='json')
    self.assertEqual(access.status_code,201)
    self.assertEqual(SupportAccessGrant.objects.get(access_id=access.data['access_id']).status,'approved')
    allowed=self.api.post(f'/api/admin/support/incidents/{incident.incident_id}/controlled-action/',{'action':'unlock_account','reason':'User requested recovery','access_id':access.data['access_id']},format='json')
    self.assertEqual(allowed.status_code,200)
    self.assertTrue(AdminAuditLog.objects.filter(action='SUPPORT_UNLOCK_ACCOUNT').exists())
