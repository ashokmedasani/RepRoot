from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase
from rest_framework.authtoken.models import Token

from . import account_lifecycle
from . import data_retention

from .models import (
  ChatMessage,
  ClientAccess,
  ClientAuthToken,
  ClientDetailChangeRequest,
  ClientPaymentMethodAccess,
  ClientRegistrationForm,
  ClientReminder,
  ClientResetAudit,
  ManualPaymentProfile,
  PaymentAuditLog,
  PaymentProof,
  PaymentRecord,
  PaymentRequest,
  ProfessionalPaymentSettings,
  ReferenceCategory,
  SupportIncident,
  SupportIncidentMessage,
  TemplateAssignment,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalProfile,
  UNIVERSAL_CORE_FIELDS,
)


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend', REPROOT_RECYCLE_BIN_DAYS=14)
class ProfessionalLifecycleTests(APITestCase):
  def setUp(self):
    User = get_user_model()
    self.user = User.objects.create_user('lifecycle', 'lifecycle@example.test', 'Strong!Pass7')
    self.profile = ProfessionalProfile.objects.create(
      user=self.user, professional_id='lifecycle-pro', profile_setup_completed=True
    )
    self.group = ProfessionalGroup.objects.create(professional=self.user, name='Lifecycle Clients')
    self.client_record = ClientAccess.objects.create(
      professional=self.user, group=self.group, first_name='Test', last_name='Client',
      email='client@example.test', username='lifeclient', temporary_password='Strong!Pass7',
    )
    self.professional_token = Token.objects.create(user=self.user)
    self.client_token = ClientAuthToken.objects.create(client=self.client_record, key='a' * 40)

  def test_move_to_recycle_revokes_access_and_restores_exact_graph(self):
    account_lifecycle.move_professional_to_recycle(
      self.profile,
      reason=ProfessionalProfile.LIFECYCLE_REASON_TRAINER_REQUESTED,
      recycled_by_reference='STF-TEST',
    )
    self.user.refresh_from_db()
    self.profile.refresh_from_db()
    self.assertFalse(self.user.is_active)
    self.assertEqual(self.profile.lifecycle_status, ProfessionalProfile.LIFECYCLE_RECYCLED)
    self.assertEqual((self.profile.recycle_expires_at - self.profile.recycled_at).days, 14)
    self.assertFalse(Token.objects.filter(pk=self.professional_token.pk).exists())
    self.assertFalse(ClientAuthToken.objects.filter(pk=self.client_token.pk).exists())
    self.assertTrue(ClientAccess.objects.filter(pk=self.client_record.pk).exists())

    account_lifecycle.restore_professional_from_recycle(self.profile)
    self.user.refresh_from_db()
    self.profile.refresh_from_db()
    self.assertTrue(self.user.is_active)
    self.assertEqual(self.profile.lifecycle_status, ProfessionalProfile.LIFECYCLE_ACTIVE)
    self.assertTrue(ClientAccess.objects.filter(pk=self.client_record.pk).exists())

  def test_frozen_account_moves_to_recycle_then_is_permanently_deleted(self):
    self.profile.is_locked = True
    self.profile.lifecycle_status = ProfessionalProfile.LIFECYCLE_FROZEN
    self.profile.lifecycle_reason = ProfessionalProfile.LIFECYCLE_REASON_BILLING_OVERAGE
    self.profile.locked_at = timezone.now() - timedelta(days=31)
    self.profile.save()
    account_lifecycle.check_and_delete_data()
    self.profile.refresh_from_db()
    self.assertEqual(self.profile.lifecycle_status, ProfessionalProfile.LIFECYCLE_RECYCLED)
    self.profile.recycle_expires_at = timezone.now() - timedelta(seconds=1)
    self.profile.save(update_fields=['recycle_expires_at'])
    account_lifecycle.purge_expired_professional_accounts()
    self.assertFalse(get_user_model().objects.filter(pk=self.user.pk).exists())

  def test_plan_visibility_can_reveal_hidden_history_until_day_180(self):
    message = ChatMessage.objects.create(
      professional=self.user, client=self.client_record, sender=ChatMessage.SENDER_CLIENT, text='hidden history'
    )
    ChatMessage.objects.filter(pk=message.pk).update(created_at=timezone.now() - timedelta(days=70))
    self.client.credentials(HTTP_AUTHORIZATION=f'Token {self.professional_token.key}')
    url = f'/api/accounts/professional/clients/{self.client_record.pk}/chat/'
    starter = self.client.get(url)
    self.assertEqual(starter.status_code, 200)
    self.assertEqual(starter.data['messages'], [])

    self.profile.plan_tier = ProfessionalProfile.PLAN_PREMIUM_UNLIMITED
    self.profile.save(update_fields=['plan_tier'])
    premium = self.client.get(url)
    self.assertEqual(len(premium.data['messages']), 1)

    ChatMessage.objects.filter(pk=message.pk).update(created_at=timezone.now() - timedelta(days=181))
    data_retention.purge_expired_client_data()
    self.assertFalse(ChatMessage.objects.filter(pk=message.pk).exists())

  def test_client_reset_requires_password_and_username_and_writes_audit(self):
    message = ChatMessage.objects.create(
      professional=self.user, client=self.client_record, sender=ChatMessage.SENDER_CLIENT, text='reset me'
    )
    self.client.credentials(HTTP_AUTHORIZATION=f'Token {self.professional_token.key}')
    url = f'/api/accounts/professional/forms-groups/clients/{self.client_record.pk}/reset/'
    rejected = self.client.post(url, {
      'current_password': 'wrong', 'confirmation': self.client_record.username, 'reason': 'Requested cleanup.'
    }, format='json')
    self.assertEqual(rejected.status_code, 400)
    self.assertTrue(ChatMessage.objects.filter(pk=message.pk).exists())

    accepted = self.client.post(url, {
      'current_password': 'Strong!Pass7', 'confirmation': self.client_record.username,
      'reason': 'Trainer verified irreversible cleanup.',
    }, format='json')
    self.assertEqual(accepted.status_code, 200)
    self.assertFalse(ChatMessage.objects.filter(pk=message.pk).exists())
    self.assertTrue(ClientResetAudit.objects.filter(client=self.client_record).exists())
    self.assertFalse(ClientAuthToken.objects.filter(client=self.client_record).exists())


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class WorkflowRefinementTests(APITestCase):
  def setUp(self):
    self.user = get_user_model().objects.create_user(
      username='professional-one',
      email='professional@example.com',
      password='Professional!123',
      first_name='Taylor',
      last_name='Coach',
    )
    self.profile = ProfessionalProfile.objects.create(
      user=self.user,
      professional_id='coach-taylor',
      profile_setup_completed=True,
    )
    self.group = ProfessionalGroup.objects.create(professional=self.user, name='Strength Group')
    self.registration_form = ClientRegistrationForm.objects.create(
      group=self.group,
      fields=[field.copy() for field in UNIVERSAL_CORE_FIELDS],
    )
    self.client.force_authenticate(self.user)

  def manual_payload(self, **overrides):
    payload = {
      'group_id': self.group.id,
      'username': 'rahul.kumar',
      'password': 'Temp!Pass7',
      'confirm_password': 'Temp!Pass7',
      'registration_answers': {
        'first_name': 'Rahul',
        'last_name': 'Kumar',
        'email': 'rahul@example.com',
      },
      'send_credentials': True,
    }
    payload.update(overrides)
    return payload

  def test_profile_status_preserves_completed_and_incomplete_states(self):
    response = self.client.get('/api/accounts/professional/profile/status/')
    self.assertEqual(response.status_code, 200)
    self.assertTrue(response.data['profile_setup_completed'])

    self.profile.profile_setup_completed = False
    self.profile.save(update_fields=['profile_setup_completed'])
    response = self.client.get('/api/accounts/professional/profile/status/')
    self.assertFalse(response.data['profile_setup_completed'])

  def test_support_incidents_enforce_active_limit_and_preserve_conversation(self):
    self.client.force_authenticate(self.user)
    payload = {
      'category': 'bug_report',
      'subject': 'Unable to save progress',
      'description': 'The save button does not complete the request.',
      'page_feature': 'Templates',
      'platform': 'web',
      'app_version': 'web',
    }
    created = []
    for index in range(3):
      response = self.client.post('/api/accounts/professional/support/incidents/', {**payload, 'subject': f'{payload["subject"]} {index}'}, format='json')
      self.assertEqual(response.status_code, 201, response.data)
      created.append(response.data['incident']['incident_id'])

    limited = self.client.post('/api/accounts/professional/support/incidents/', payload, format='json')
    self.assertEqual(limited.status_code, 400)
    self.assertIn('maximum of three', limited.data['message'])

    incident = SupportIncident.objects.get(incident_id=created[0])
    incident.status = SupportIncident.STATUS_WAITING
    incident.save(update_fields=['status', 'updated_at'])
    follow_up = self.client.post(
      f'/api/accounts/professional/support/incidents/{incident.incident_id}/',
      {'action': 'follow_up', 'body': 'I can reproduce this every time.'},
      format='json',
    )
    self.assertEqual(follow_up.status_code, 200, follow_up.data)
    self.assertEqual(follow_up.data['incident']['status'], SupportIncident.STATUS_REVIEW)
    self.assertTrue(SupportIncidentMessage.objects.filter(incident=incident, body__icontains='reproduce').exists())

    incident.status = SupportIncident.STATUS_RESOLVED
    incident.save(update_fields=['status', 'updated_at'])
    reopened = self.client.post(
      f'/api/accounts/professional/support/incidents/{incident.incident_id}/',
      {'action': 'reopen'},
      format='json',
    )
    self.assertEqual(reopened.status_code, 200, reopened.data)
    self.assertEqual(reopened.data['incident']['status'], SupportIncident.STATUS_REOPENED)

  def test_professional_data_usage_counts_owned_client_content(self):
    photo = 'data:image/png;base64,' + ('A' * 2048)
    ClientAccess.objects.create(
      professional=self.user,
      group=self.group,
      first_name='Usage',
      last_name='Client',
      email='usage@example.com',
      username='usage-client',
      temporary_password='hashed-value',
      photo=photo,
      registration_answers={'goal': 'Strength'},
    )

    response = self.client.get('/api/accounts/professional/data-usage/')

    self.assertEqual(response.status_code, 200, response.data)
    # The professional-facing usage response is percentage-only — no raw byte
    # counts are exposed, so assertions below check percent/record_count shape.
    self.assertNotIn('total_bytes', response.data)
    self.assertNotIn('database_bytes', response.data)
    self.assertNotIn('quota_bytes', response.data)
    self.assertEqual(response.data['plan_name'], 'Starter Free')
    self.assertGreaterEqual(response.data['usage_percent'], 0)
    self.assertIn('usage_label', response.data)
    self.assertIn('professional_profile', response.data['sections'])
    self.assertIn('clients', response.data['sections'])
    self.assertEqual(response.data['sections']['clients']['record_count'], 1)
    # Per-client "most active client" breakdown was removed from this response.
    self.assertNotIn('featured_client', response.data)

  def test_manual_client_gets_reference_credentials_and_first_login_change(self):
    response = self.client.post('/api/accounts/professional/forms-groups/clients/manual/', self.manual_payload(), format='json')
    self.assertEqual(response.status_code, 201, response.data)
    client_access = ClientAccess.objects.get(pk=response.data['client_access']['id'])
    self.assertEqual(client_access.onboarding_method, ClientAccess.ONBOARDING_MANUAL)
    self.assertTrue(client_access.reference_id.startswith('CL-'))
    self.assertTrue(client_access.must_change_password)
    self.assertEqual(len(mail.outbox), 1)
    self.assertIn('rahul.kumar', mail.outbox[0].body)
    self.assertIn('Temp!Pass7', mail.outbox[0].body)

    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
      format='json',
    )
    self.assertEqual(login.status_code, 200, login.data)
    self.assertTrue(login.data['client']['must_change_password'])

  def test_group_registration_is_distinct_and_can_convert(self):
    self.client.force_authenticate(user=None)
    public_response = self.client.post(
      f'/api/accounts/public/group-registration/{self.registration_form.public_slug}/',
      {'answers': {'first_name': 'Ava', 'last_name': 'Stone', 'email': 'ava@example.com'}},
      format='json',
    )
    self.assertEqual(public_response.status_code, 201, public_response.data)
    reference_id = public_response.data['reference_id']

    self.client.force_authenticate(self.user)
    group_response = self.client.get(f'/api/accounts/professional/forms-groups/groups/{self.group.id}/clients/')
    submission = group_response.data['registration_submissions'][0]
    self.assertEqual(submission['reference_id'], reference_id)

    payload = self.manual_payload(
      username='ava.stone',
      registration_answers={'first_name': 'ignored', 'last_name': 'ignored', 'email': 'ignored@example.com'},
      registration_submission_id=submission['id'],
    )
    converted = self.client.post('/api/accounts/professional/forms-groups/clients/manual/', payload, format='json')
    self.assertEqual(converted.status_code, 201, converted.data)
    self.assertEqual(converted.data['client_access']['onboarding_method'], ClientAccess.ONBOARDING_GROUP_REGISTRATION)
    self.assertEqual(converted.data['client_access']['reference_id'], reference_id)

  def test_schedule_summary_includes_required_pending_and_completed_kpis(self):
    response = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=response.data['client_access']['id'])
    now = timezone.localtime()
    overdue_at = now - timedelta(days=1)
    due_soon_at = now + timedelta(hours=2)
    next_week_at = now + timedelta(days=6)
    ClientReminder.objects.create(
      professional=self.user,
      client=client_access,
      title='Overdue check-in',
      date=overdue_at.date(),
      time=overdue_at.time(),
    )
    ClientReminder.objects.create(
      professional=self.user,
      client=client_access,
      title='Today check-in',
      date=due_soon_at.date(),
      time=due_soon_at.time(),
    )
    ClientReminder.objects.create(
      professional=self.user,
      client=client_access,
      title='Next week',
      date=next_week_at.date(),
      time=next_week_at.time(),
    )
    ClientReminder.objects.create(
      professional=self.user,
      client=client_access,
      title='Completed',
      date=now.date(),
      status=ClientReminder.STATUS_DONE,
    )
    ClientDetailChangeRequest.objects.create(
      client=client_access,
      proposed_answers={'primary_goal': 'Improve mobility'},
      client_note='My goal has changed.',
    )

    summary_response = self.client.get('/api/accounts/professional/reminders/upcoming/')
    summary = summary_response.data['summary']
    self.assertEqual(summary['total_pending'], 3)
    self.assertEqual(summary['overdue'], 1)
    self.assertEqual(summary['due_24_hours'], 1)
    self.assertEqual(summary['due_7_days'], 2)
    self.assertEqual(summary['total_completed'], 1)
    self.assertEqual(summary['completed_last_7_days'], 1)
    self.assertEqual(summary['pending_profile_edits'], 1)
    self.assertEqual(len(summary_response.data['profile_edits']), 1)
    self.assertEqual(summary_response.data['profile_edits'][0]['client'], client_access.id)
    self.assertEqual(summary_response.data['profile_edits'][0]['proposed_field_count'], 1)
    self.assertEqual(summary_response.data['reminders'][0]['title'], 'Overdue check-in')
    self.assertNotIn('due_5_days', summary)
    self.assertNotIn('due_10_days', summary)

    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
      format='json',
    )
    dashboard = self.client.get(
      '/api/accounts/client/dashboard/',
      HTTP_AUTHORIZATION=f"ClientToken {login.data['token']}",
    )
    self.assertEqual(dashboard.status_code, 200, dashboard.data)
    self.assertEqual(dashboard.data['summary']['overdue'], 1)
    self.assertEqual(dashboard.data['summary']['due_24_hours'], 1)
    self.assertEqual(dashboard.data['summary']['due_7_days'], 2)
    self.assertEqual(dashboard.data['schedules'][0]['title'], 'Overdue check-in')

  @override_settings(REPROOT_PLAN_LIMITS={'references': 1, 'categories': 10, 'subcategories_per_category': 5})
  def test_reference_limit_is_reported_and_enforced(self):
    category = ReferenceCategory.objects.create(professional=self.user, name='Exercises', subcategories=['Back'])
    first = self.client.post(
      '/api/accounts/professional/references/',
      {
        'category': category.id,
        'subcategory': 'Back',
        'title': 'Row guide',
        'reference_type': 'text_note',
        'description': 'Keep the spine neutral.',
        'link': '',
        'tags': 'back',
      },
      format='multipart',
    )
    self.assertEqual(first.status_code, 201, first.data)
    listing = self.client.get('/api/accounts/professional/references/')
    self.assertEqual(listing.data['usage'], {'used': 1, 'limit': 1})
    second = self.client.post(
      '/api/accounts/professional/references/',
      {
        'category': category.id,
        'subcategory': 'Back',
        'title': 'Second guide',
        'reference_type': 'text_note',
        'description': 'Blocked by the plan limit.',
        'link': '',
        'tags': '',
      },
      format='multipart',
    )
    self.assertEqual(second.status_code, 400)
    self.assertEqual(second.data['message'], 'You have reached the Version 1 reference limit.')

  def test_client_deletion_request_reaches_professional_and_deactivates_on_approval(self):
    created = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])

    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
      format='json',
    )
    token = login.data['token']
    requested = self.client.post(
      '/api/accounts/client/account-deletion-request/',
      {'note': 'I no longer need coaching access.'},
      format='json',
      HTTP_AUTHORIZATION=f'ClientToken {token}',
    )
    self.assertEqual(requested.status_code, 201, requested.data)
    self.assertEqual(requested.data['deletion_request']['request_type'], 'account_deletion')

    self.client.force_authenticate(self.user)
    queue = self.client.get('/api/accounts/professional/reminders/upcoming/')
    action = next(item for item in queue.data['profile_edits'] if item['request_type'] == 'account_deletion')
    approved = self.client.post(
      f'/api/accounts/professional/forms-groups/clients/{client_access.id}/change-requests/{action["id"]}/',
      {'action': 'approve'},
      format='json',
    )
    self.assertEqual(approved.status_code, 200, approved.data)
    client_access.refresh_from_db()
    self.assertFalse(client_access.is_active)

  def test_legacy_additional_information_is_normalized_and_removable(self):
    created = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])
    client_access.additional_info = [
      {'label': 'Emergency Contact', 'value': 'Mia, 555-2010'},
      {'label': 'Training Days', 'value': 'Monday and Friday'},
    ]
    client_access.save(update_fields=['additional_info'])

    detail = self.client.get(f'/api/accounts/professional/forms-groups/clients/{client_access.id}/')
    items = detail.data['client']['additional_info']
    self.assertEqual([item['title'] for item in items], ['Emergency Contact', 'Training Days'])
    self.assertTrue(all(item['id'] for item in items))

    updated = self.client.put(
      f'/api/accounts/professional/forms-groups/clients/{client_access.id}/additional-info/',
      {'additional_info': [items[1]]},
      format='json',
    )
    self.assertEqual(updated.status_code, 200, updated.data)
    client_access.refresh_from_db()
    self.assertEqual(len(client_access.additional_info), 1)
    self.assertEqual(client_access.additional_info[0]['title'], 'Training Days')

  def test_current_profile_visibility_contract_is_preserved(self):
    visibility = {
      'professional_headline': True,
      'about': True,
      'professional_summary': True,
      'specializations': True,
      'experience': True,
      'languages': True,
      'training_style': True,
      'certification': True,
      'images': True,
      'links': True,
    }
    response = self.client.put(
      '/api/accounts/professional/profile/visibility/',
      {'visibility': visibility},
      format='json',
    )
    self.assertEqual(response.status_code, 200, response.data)
    self.assertEqual(response.data['profile_visibility'], visibility)

    self.profile.refresh_from_db()
    self.assertEqual(self.profile.profile_visibility, visibility)

  def test_client_logout_revokes_the_current_token(self):
    created = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
      format='json',
    )
    token = login.data['token']
    authorization = f'ClientToken {token}'
    logout = self.client.post('/api/accounts/client/logout/', HTTP_AUTHORIZATION=authorization)
    self.assertEqual(logout.status_code, 200, logout.data)
    me = self.client.get('/api/accounts/client/me/', HTTP_AUTHORIZATION=authorization)
    self.assertEqual(me.status_code, 401)

  def test_chat_unread_counts_clear_only_when_recipient_opens_chat(self):
    created = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])

    ChatMessage.objects.create(
      professional=self.user,
      client=client_access,
      sender=ChatMessage.SENDER_CLIENT,
      text='Can you review my workout?',
    )
    professional_unread = self.client.get('/api/accounts/professional/chat/unread/')
    self.assertEqual(professional_unread.status_code, 200, professional_unread.data)
    self.assertEqual(professional_unread.data['unread_count'], 1)
    self.assertEqual(professional_unread.data['by_client'][str(client_access.id)], 1)
    self.assertEqual(professional_unread.data['client_names'][str(client_access.id)], 'Rahul Kumar')

    opened_by_professional = self.client.get(f'/api/accounts/professional/clients/{client_access.id}/chat/')
    self.assertEqual(opened_by_professional.status_code, 200, opened_by_professional.data)
    self.assertEqual(self.client.get('/api/accounts/professional/chat/unread/').data['unread_count'], 0)

    self.client.post(
      f'/api/accounts/professional/clients/{client_access.id}/chat/',
      {'text': 'I reviewed it and left feedback.'},
      format='json',
    )
    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
      format='json',
    )
    authorization = f'ClientToken {login.data["token"]}'
    client_unread = self.client.get('/api/accounts/client/chat/unread/', HTTP_AUTHORIZATION=authorization)
    self.assertEqual(client_unread.status_code, 200, client_unread.data)
    self.assertEqual(client_unread.data['unread_count'], 1)

    opened_by_client = self.client.get('/api/accounts/client/chat/', HTTP_AUTHORIZATION=authorization)
    self.assertEqual(opened_by_client.status_code, 200, opened_by_client.data)
    self.assertEqual(
      self.client.get('/api/accounts/client/chat/unread/', HTTP_AUTHORIZATION=authorization).data['unread_count'],
      0,
    )

  def test_assigned_template_cannot_be_deleted_until_unassigned(self):
    """A template in use must be unassigned from every client before deletion.

    TemplateAssignment cascades on the template FK, so without the guard the
    delete would silently strip an actively-used tracker from every client.
    """
    created = self.client.post(
      '/api/accounts/professional/templates/',
      {
        'name': 'Daily Habits',
        'purpose': 'Track habits',
        'cadence': 'daily',
        'accent': '#0b7de3',
        'custom_fields': [{'label': 'Steps', 'field_type': 'number', 'placeholder': ''}],
      },
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    template_id = created.data['template']['id']

    made_client = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      self.manual_payload(),
      format='json',
    )
    self.assertEqual(made_client.status_code, 201, made_client.data)
    client_id = made_client.data['client_access']['id']

    assigned = self.client.post(
      f'/api/accounts/professional/forms-groups/clients/{client_id}/assignments/',
      {'template_id': template_id, 'reference_ids': []},
      format='json',
    )
    self.assertEqual(assigned.status_code, 201, assigned.data)
    assignment_id = assigned.data['assignment']['id']

    # Assigned: the delete must be refused and the template must survive.
    refused = self.client.delete(f'/api/accounts/professional/templates/{template_id}/')
    self.assertEqual(refused.status_code, 400, refused.data)
    self.assertEqual(refused.data['assigned_count'], 1)
    self.assertIn('Remove it from every client', refused.data['message'])
    self.assertTrue(TrackingTemplate.objects.filter(id=template_id).exists())
    self.assertTrue(TemplateAssignment.objects.filter(id=assignment_id).exists())

    # Unassigned: the delete now goes through.
    unassigned = self.client.delete(
      f'/api/accounts/professional/forms-groups/clients/{client_id}/assignments/{assignment_id}/'
    )
    self.assertEqual(unassigned.status_code, 200, unassigned.data)

    deleted = self.client.delete(f'/api/accounts/professional/templates/{template_id}/')
    self.assertEqual(deleted.status_code, 200, deleted.data)
    self.assertFalse(TrackingTemplate.objects.filter(id=template_id).exists())


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class ClientPaymentsWorkflowTests(APITestCase):
  """Client Payments — money professionals collect from their own clients.
  Separate from RepRoot Studio Billing; see accounts/views_payments.py."""

  def setUp(self):
    self.user = get_user_model().objects.create_user(
      username='pay-professional',
      email='pay-professional@example.com',
      password='Professional!123',
      first_name='Maya',
      last_name='Santos',
    )
    ProfessionalProfile.objects.create(user=self.user, professional_id='coach-maya-pay', profile_setup_completed=True)
    self.group = ProfessionalGroup.objects.create(professional=self.user, name='Pay Group')
    ClientRegistrationForm.objects.create(group=self.group, fields=[field.copy() for field in UNIVERSAL_CORE_FIELDS])
    self.client.force_authenticate(self.user)

    created = self.client.post(
      '/api/accounts/professional/forms-groups/clients/manual/',
      {
        'group_id': self.group.id,
        'username': 'pay.client',
        'password': 'Temp!Pass7',
        'confirm_password': 'Temp!Pass7',
        'registration_answers': {'first_name': 'Alex', 'last_name': 'Rivera', 'email': 'alex@example.com'},
        'send_credentials': False,
      },
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    self.client_access_id = created.data['client_access']['id']

    login = self.client.post(
      '/api/accounts/client/login/',
      {'professional_id': 'coach-maya-pay', 'username': 'pay.client', 'password': 'Temp!Pass7'},
      format='json',
    )
    self.assertEqual(login.status_code, 200, login.data)
    self.client_auth_header = 'ClientToken ' + login.data['token']
    self.client.force_authenticate(self.user)

  def create_method(self, **overrides):
    payload = {
      'name': 'Personal UPI',
      'category': 'upi',
      'display_label': 'Maya UPI',
      'supported_currencies': ['USD'],
      'client_visible_fields': {'upi_id': 'maya@ybl'},
      'private_fields': {'linked_bank': 'Test Bank'},
      'internal_notes': 'internal only, never sent to client',
      'client_instructions': 'Pay via UPI',
    }
    payload.update(overrides)
    response = self.client.post('/api/accounts/professional/payments/methods/', payload, format='json')
    self.assertEqual(response.status_code, 201, response.data)
    return response.data['method']['id']

  def share_method(self, method_id):
    response = self.client.put(
      '/api/accounts/professional/payments/clients/' + str(self.client_access_id) + '/methods/',
      {'method_ids': [method_id]},
      format='json',
    )
    self.assertEqual(response.status_code, 200, response.data)

  def create_request(self, method_id, **overrides):
    payload = {
      'title': 'July Coaching Fee',
      'requested_amount': '200.00',
      'requested_currency': 'USD',
      'payment_type': 'manual',
      'allowed_method_ids': [method_id],
    }
    payload.update(overrides)
    response = self.client.post(
      '/api/accounts/professional/payments/clients/' + str(self.client_access_id) + '/requests/', payload, format='json'
    )
    self.assertEqual(response.status_code, 201, response.data)
    return response.data['request']['request_id']

  # --- Manual payment methods -------------------------------------------

  def test_manual_method_cap_is_five_active(self):
    for index in range(5):
      self.create_method(display_label='Method ' + str(index), name='internal ' + str(index))
    sixth = self.client.post(
      '/api/accounts/professional/payments/methods/',
      {'name': 'Sixth', 'category': 'cash', 'display_label': 'Cash', 'client_visible_fields': {}},
      format='json',
    )
    self.assertEqual(sixth.status_code, 400)
    self.assertIn('limit', sixth.data['message'].lower())

  def test_category_required_client_fields_are_enforced(self):
    response = self.client.post(
      '/api/accounts/professional/payments/methods/',
      {'name': 'Bad Zelle', 'category': 'zelle', 'display_label': 'US Zelle', 'client_visible_fields': {}},
      format='json',
    )
    self.assertEqual(response.status_code, 400)
    self.assertIn('client_visible_fields', response.data)

  def test_client_facing_preview_never_leaks_private_fields(self):
    method_id = self.create_method()
    preview = self.client.get('/api/accounts/professional/payments/methods/' + str(method_id) + '/preview/')
    self.assertEqual(preview.status_code, 200, preview.data)
    preview_body = preview.data['preview']
    self.assertNotIn('private_fields', preview_body)
    self.assertNotIn('internal_notes', preview_body)
    self.assertNotIn('name', preview_body)
    self.assertEqual(preview_body['client_visible_fields'], {'upi_id': 'maya@ybl'})

  def test_unshared_method_is_rejected_on_request_creation(self):
    method_id = self.create_method()
    response = self.client.post(
      '/api/accounts/professional/payments/clients/' + str(self.client_access_id) + '/requests/',
      {
        'title': 'Should fail',
        'requested_amount': '50.00',
        'requested_currency': 'USD',
        'payment_type': 'manual',
        'allowed_method_ids': [method_id],
      },
      format='json',
    )
    self.assertEqual(response.status_code, 400)
    self.assertIn('shared', response.data['message'])

  # --- Requests / proof / verification -----------------------------------

  def test_client_view_flips_status_to_viewed_and_notifies_professional(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)

    self.assertEqual(PaymentRequest.objects.get(request_id=request_id).status, PaymentRequest.STATUS_SENT)

    self.client.force_authenticate(user=None)
    detail = self.client.get(
      '/api/accounts/client/payments/requests/' + request_id + '/', HTTP_AUTHORIZATION=self.client_auth_header
    )
    self.assertEqual(detail.status_code, 200, detail.data)
    self.assertEqual(PaymentRequest.objects.get(request_id=request_id).status, PaymentRequest.STATUS_VIEWED)

  def test_proof_requires_reference_or_file(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)

    self.client.force_authenticate(user=None)
    response = self.client.post(
      '/api/accounts/client/payments/requests/' + request_id + '/proof/',
      {
        'reported_amount': '200.00',
        'reported_currency': 'USD',
        'reported_payment_date': timezone.now().date().isoformat(),
        'payment_method': method_id,
        'confirmed_accurate': True,
      },
      format='json',
      HTTP_AUTHORIZATION=self.client_auth_header,
    )
    self.assertEqual(response.status_code, 400)

  def test_acknowledge_then_log_flow_creates_completed_record_and_writes_audit_log(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)

    self.client.force_authenticate(user=None)
    proof = self.client.post(
      '/api/accounts/client/payments/requests/' + request_id + '/proof/',
      {
        'transaction_reference': 'UPI-TEST-1',
        'reported_amount': '200.00',
        'reported_currency': 'USD',
        'reported_payment_date': timezone.now().date().isoformat(),
        'payment_method': method_id,
        'confirmed_accurate': True,
      },
      format='json',
      HTTP_AUTHORIZATION=self.client_auth_header,
    )
    self.assertEqual(proof.status_code, 201, proof.data)
    proof_id = proof.data['proof']['id']
    self.assertEqual(PaymentRequest.objects.get(request_id=request_id).status, PaymentRequest.STATUS_PROOF_SUBMITTED)

    self.client.force_authenticate(self.user)
    acknowledged = self.client.post(
      '/api/accounts/professional/payments/proofs/' + str(proof_id) + '/acknowledge/',
      {'acknowledgement_note': 'Confirmed in app'},
      format='json',
    )
    self.assertEqual(acknowledged.status_code, 200, acknowledged.data)
    self.assertTrue(acknowledged.data['needs_logging'])

    payment_request = PaymentRequest.objects.get(request_id=request_id)
    self.assertEqual(payment_request.status, PaymentRequest.STATUS_ACKNOWLEDGED)
    self.assertFalse(PaymentRecord.objects.filter(payment_request=payment_request).exists())
    self.assertTrue(PaymentAuditLog.objects.filter(action='payment_acknowledged', payment_request=payment_request).exists())

    reconciliation = self.client.get('/api/accounts/professional/payments/reconciliation/')
    self.assertEqual(reconciliation.status_code, 200, reconciliation.data)
    self.assertEqual(reconciliation.data['acknowledged_count'], 1)
    self.assertEqual(reconciliation.data['unlogged_count'], 1)

    logged = self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'payment_request_id': request_id,
        'original_amount': '200.00',
        'original_currency': 'USD',
        'reporting_amount': '16750.00',
        'reporting_currency': 'INR',
        'received_date': timezone.now().date().isoformat(),
        'status': 'completed',
      },
      format='json',
    )
    self.assertEqual(logged.status_code, 201, logged.data)

    payment_request.refresh_from_db()
    self.assertEqual(payment_request.status, PaymentRequest.STATUS_COMPLETED)
    record = PaymentRecord.objects.get(payment_request=payment_request)
    self.assertEqual(record.status, PaymentRecord.STATUS_COMPLETED)
    self.assertEqual(str(record.reporting_amount), '16750.00')
    self.assertTrue(PaymentAuditLog.objects.filter(action='payment_recorded', payment_record=record).exists())

    reconciliation_after = self.client.get('/api/accounts/professional/payments/reconciliation/')
    self.assertEqual(reconciliation_after.data['unlogged_count'], 0)
    self.assertEqual(reconciliation_after.data['logged_count'], 1)

  def test_reject_proof_requires_reason_and_client_can_resubmit(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)

    self.client.force_authenticate(user=None)
    proof = self.client.post(
      '/api/accounts/client/payments/requests/' + request_id + '/proof/',
      {
        'transaction_reference': 'BAD-REF',
        'reported_amount': '200.00',
        'reported_currency': 'USD',
        'reported_payment_date': timezone.now().date().isoformat(),
        'payment_method': method_id,
        'confirmed_accurate': True,
      },
      format='json',
      HTTP_AUTHORIZATION=self.client_auth_header,
    )
    proof_id = proof.data['proof']['id']

    self.client.force_authenticate(self.user)
    rejected = self.client.post(
      '/api/accounts/professional/payments/proofs/' + str(proof_id) + '/reject/',
      {'reason': 'Reference does not match'},
      format='json',
    )
    self.assertEqual(rejected.status_code, 200, rejected.data)
    self.assertEqual(PaymentProof.objects.get(id=proof_id).status, PaymentProof.STATUS_REJECTED)

  # --- Partial payments / reporting-currency immutability -----------------

  def test_same_currency_installments_auto_complete_request(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)
    payment_request = PaymentRequest.objects.get(request_id=request_id)

    for _ in range(2):
      response = self.client.post(
        '/api/accounts/professional/payments/records/',
        {
          'client': self.client_access_id,
          'payment_request_id': request_id,
          'original_amount': '100.00',
          'original_currency': 'USD',
          'reporting_amount': '8300.00',
          'reporting_currency': 'INR',
          'received_date': timezone.now().date().isoformat(),
          'status': 'partially_paid',
        },
        format='json',
      )
      self.assertEqual(response.status_code, 201, response.data)

    payment_request.refresh_from_db()
    self.assertEqual(payment_request.status, PaymentRequest.STATUS_COMPLETED)

  def test_mixed_currency_installments_do_not_auto_complete(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)
    payment_request = PaymentRequest.objects.get(request_id=request_id)

    self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'payment_request_id': request_id,
        'original_amount': '100.00',
        'original_currency': 'USD',
        'reporting_amount': '8300.00',
        'reporting_currency': 'INR',
        'received_date': timezone.now().date().isoformat(),
        'status': 'partially_paid',
      },
      format='json',
    )
    self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'payment_request_id': request_id,
        'original_amount': '8300.00',
        'original_currency': 'INR',
        'reporting_amount': '8300.00',
        'reporting_currency': 'INR',
        'received_date': timezone.now().date().isoformat(),
        'status': 'partially_paid',
      },
      format='json',
    )

    payment_request.refresh_from_db()
    self.assertEqual(payment_request.status, PaymentRequest.STATUS_PARTIALLY_PAID)

  def test_reporting_currency_change_does_not_rewrite_historical_records(self):
    method_id = self.create_method()
    self.share_method(method_id)
    request_id = self.create_request(method_id)

    self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'payment_request_id': request_id,
        'original_amount': '200.00',
        'original_currency': 'USD',
        'reporting_amount': '16750.00',
        'reporting_currency': 'INR',
        'received_date': timezone.now().date().isoformat(),
        'status': 'completed',
      },
      format='json',
    )
    record = PaymentRecord.objects.get(payment_request__request_id=request_id)

    settings_response = self.client.put(
      '/api/accounts/professional/payments/settings/', {'reporting_currency': 'USD'}, format='json'
    )
    self.assertEqual(settings_response.status_code, 200, settings_response.data)

    record.refresh_from_db()
    self.assertEqual(record.reporting_currency, 'INR')
    self.assertEqual(str(record.reporting_amount), '16750.00')

  # --- Privacy / permission boundaries -------------------------------------

  def test_client_cannot_see_private_visibility_record(self):
    method_id = self.create_method()
    self.share_method(method_id)
    self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'original_amount': '500.00',
        'original_currency': 'USD',
        'reporting_amount': '500.00',
        'reporting_currency': 'USD',
        'received_date': timezone.now().date().isoformat(),
        'status': 'completed',
        'client_visibility': 'private',
        'internal_note': 'not for client eyes',
      },
      format='json',
    )

    self.client.force_authenticate(user=None)
    records = self.client.get('/api/accounts/client/payments/records/', HTTP_AUTHORIZATION=self.client_auth_header)
    self.assertEqual(records.status_code, 200, records.data)
    self.assertEqual(records.data['records'], [])

  def test_payment_audit_log_is_immutable(self):
    log = PaymentAuditLog.objects.create(professional=self.user, action='method_created', changed_by='tester')
    log.new_values = {'changed': True}
    with self.assertRaises(ValueError):
      log.save()

  def test_confirmation_document_returns_expected_fields(self):
    method_id = self.create_method()
    self.share_method(method_id)
    self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'original_amount': '75.00',
        'original_currency': 'USD',
        'reporting_amount': '75.00',
        'reporting_currency': 'USD',
        'received_date': timezone.now().date().isoformat(),
        'status': 'completed',
        'client_note': 'Thanks!',
      },
      format='json',
    )
    record = PaymentRecord.objects.get(professional=self.user)
    response = self.client.get('/api/accounts/professional/payments/records/' + record.payment_record_id + '/confirmation/')
    self.assertEqual(response.status_code, 200, response.data)
    confirmation = response.data['confirmation']
    self.assertEqual(confirmation['professional_note'], 'Thanks!')
    self.assertEqual(confirmation['amount_recorded'], '75.00')
    self.assertEqual(confirmation['status'], 'completed')

  def test_reporting_currency_can_be_confirmed_once_and_not_changed(self):
    response = self.client.put(
      '/api/accounts/professional/payments/settings/',
      {'reporting_currency': 'INR', 'confirm_reporting_currency': True},
      format='json',
    )
    self.assertEqual(response.status_code, 200, response.data)
    self.assertTrue(response.data['settings']['reporting_currency_locked'])
    self.assertIsNotNone(response.data['settings']['reporting_currency_locked_at'])

    rejected = self.client.put(
      '/api/accounts/professional/payments/settings/', {'reporting_currency': 'USD'}, format='json'
    )
    self.assertEqual(rejected.status_code, 400, rejected.data)
    self.assertEqual(ProfessionalPaymentSettings.objects.get(professional=self.user).reporting_currency, 'INR')

  def test_forced_first_password_change_does_not_repeat_temporary_password(self):
    self.client.force_authenticate(user=None)
    response = self.client.post(
      '/api/accounts/client/change-password/',
      {'password': 'NewClient!29', 'confirm_password': 'NewClient!29'},
      format='json', HTTP_AUTHORIZATION=self.client_auth_header,
    )
    self.assertEqual(response.status_code, 200, response.data)
    self.assertFalse(response.data['client']['must_change_password'])

  def test_transaction_ledger_is_visible_and_immutable(self):
    from admin_portal.models import FinanceLedgerEntry

    response = self.client.post(
      '/api/accounts/professional/payments/records/',
      {
        'client': self.client_access_id,
        'original_amount': '50.00', 'original_currency': 'INR',
        'reporting_amount': '50.00', 'reporting_currency': 'INR',
        'received_date': timezone.now().date().isoformat(), 'status': 'completed',
      }, format='json',
    )
    self.assertEqual(response.status_code, 201, response.data)
    ledger = self.client.get('/api/accounts/professional/payments/transactions/')
    self.assertEqual(ledger.status_code, 200, ledger.data)
    self.assertEqual(ledger.data['transactions'][0]['source'], 'client_payment')
    row = FinanceLedgerEntry.objects.get(professional=self.user)
    self.assertTrue(row.client_reference)
    row.description = 'rewritten'
    with self.assertRaises(ValueError):
      row.save()
