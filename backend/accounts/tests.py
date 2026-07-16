from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core import mail
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from .models import (
  ChatMessage,
  ClientAccess,
  ClientDetailChangeRequest,
  ClientRegistrationForm,
  ClientReminder,
  ReferenceCategory,
  SupportIncident,
  SupportIncidentMessage,
  TemplateAssignment,
  TrackingTemplate,
  TrainerGroup,
  TrainerProfile,
  UNIVERSAL_CORE_FIELDS,
)


@override_settings(EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend')
class WorkflowRefinementTests(APITestCase):
  def setUp(self):
    self.user = get_user_model().objects.create_user(
      username='trainer-one',
      email='trainer@example.com',
      password='Trainer!123',
      first_name='Taylor',
      last_name='Coach',
    )
    self.profile = TrainerProfile.objects.create(
      user=self.user,
      trainer_id='coach-taylor',
      profile_setup_completed=True,
    )
    self.group = TrainerGroup.objects.create(trainer=self.user, name='Strength Group')
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
    response = self.client.get('/api/accounts/trainer/profile/status/')
    self.assertEqual(response.status_code, 200)
    self.assertTrue(response.data['profile_setup_completed'])

    self.profile.profile_setup_completed = False
    self.profile.save(update_fields=['profile_setup_completed'])
    response = self.client.get('/api/accounts/trainer/profile/status/')
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
      response = self.client.post('/api/accounts/trainer/support/incidents/', {**payload, 'subject': f'{payload["subject"]} {index}'}, format='json')
      self.assertEqual(response.status_code, 201, response.data)
      created.append(response.data['incident']['incident_id'])

    limited = self.client.post('/api/accounts/trainer/support/incidents/', payload, format='json')
    self.assertEqual(limited.status_code, 400)
    self.assertIn('maximum of three', limited.data['message'])

    incident = SupportIncident.objects.get(incident_id=created[0])
    incident.status = SupportIncident.STATUS_WAITING
    incident.save(update_fields=['status', 'updated_at'])
    follow_up = self.client.post(
      f'/api/accounts/trainer/support/incidents/{incident.incident_id}/',
      {'action': 'follow_up', 'body': 'I can reproduce this every time.'},
      format='json',
    )
    self.assertEqual(follow_up.status_code, 200, follow_up.data)
    self.assertEqual(follow_up.data['incident']['status'], SupportIncident.STATUS_REVIEW)
    self.assertTrue(SupportIncidentMessage.objects.filter(incident=incident, body__icontains='reproduce').exists())

    incident.status = SupportIncident.STATUS_RESOLVED
    incident.save(update_fields=['status', 'updated_at'])
    reopened = self.client.post(
      f'/api/accounts/trainer/support/incidents/{incident.incident_id}/',
      {'action': 'reopen'},
      format='json',
    )
    self.assertEqual(reopened.status_code, 200, reopened.data)
    self.assertEqual(reopened.data['incident']['status'], SupportIncident.STATUS_REOPENED)

  def test_trainer_data_usage_counts_owned_client_content(self):
    photo = 'data:image/png;base64,' + ('A' * 2048)
    ClientAccess.objects.create(
      trainer=self.user,
      group=self.group,
      first_name='Usage',
      last_name='Client',
      email='usage@example.com',
      username='usage-client',
      temporary_password='hashed-value',
      photo=photo,
      registration_answers={'goal': 'Strength'},
    )

    response = self.client.get('/api/accounts/trainer/data-usage/')

    self.assertEqual(response.status_code, 200, response.data)
    self.assertGreater(response.data['database_bytes'], len(photo))
    self.assertEqual(response.data['total_bytes'], response.data['database_bytes'] + response.data['file_bytes'])
    self.assertEqual(response.data['quota_bytes'], 50 * 1024 * 1024)
    self.assertEqual(response.data['plan_name'], 'Starter')
    self.assertGreaterEqual(response.data['usage_percent'], 0)
    self.assertIn('trainer_profile', response.data['sections'])
    self.assertIn('clients', response.data['sections'])
    self.assertEqual(response.data['sections']['clients']['record_count'], 1)
    self.assertEqual(response.data['featured_client']['username'], 'usage-client')
    self.assertGreater(response.data['featured_client']['sections']['profile_intake']['total_bytes'], len(photo))

  def test_manual_client_gets_reference_credentials_and_first_login_change(self):
    response = self.client.post('/api/accounts/trainer/forms-groups/clients/manual/', self.manual_payload(), format='json')
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
      {'trainer_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
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
    group_response = self.client.get(f'/api/accounts/trainer/forms-groups/groups/{self.group.id}/clients/')
    submission = group_response.data['registration_submissions'][0]
    self.assertEqual(submission['reference_id'], reference_id)

    payload = self.manual_payload(
      username='ava.stone',
      registration_answers={'first_name': 'ignored', 'last_name': 'ignored', 'email': 'ignored@example.com'},
      registration_submission_id=submission['id'],
    )
    converted = self.client.post('/api/accounts/trainer/forms-groups/clients/manual/', payload, format='json')
    self.assertEqual(converted.status_code, 201, converted.data)
    self.assertEqual(converted.data['client_access']['onboarding_method'], ClientAccess.ONBOARDING_GROUP_REGISTRATION)
    self.assertEqual(converted.data['client_access']['reference_id'], reference_id)

  def test_schedule_summary_includes_required_pending_and_completed_kpis(self):
    response = self.client.post(
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=response.data['client_access']['id'])
    now = timezone.localtime()
    overdue_at = now - timedelta(days=1)
    due_soon_at = now + timedelta(hours=2)
    next_week_at = now + timedelta(days=6)
    ClientReminder.objects.create(
      trainer=self.user,
      client=client_access,
      title='Overdue check-in',
      date=overdue_at.date(),
      time=overdue_at.time(),
    )
    ClientReminder.objects.create(
      trainer=self.user,
      client=client_access,
      title='Today check-in',
      date=due_soon_at.date(),
      time=due_soon_at.time(),
    )
    ClientReminder.objects.create(
      trainer=self.user,
      client=client_access,
      title='Next week',
      date=next_week_at.date(),
      time=next_week_at.time(),
    )
    ClientReminder.objects.create(
      trainer=self.user,
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

    summary_response = self.client.get('/api/accounts/trainer/reminders/upcoming/')
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
      {'trainer_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
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

  @override_settings(COACHFLOW_PLAN_LIMITS={'references': 1, 'categories': 10, 'subcategories_per_category': 5})
  def test_reference_limit_is_reported_and_enforced(self):
    category = ReferenceCategory.objects.create(trainer=self.user, name='Exercises', subcategories=['Back'])
    first = self.client.post(
      '/api/accounts/trainer/references/',
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
    listing = self.client.get('/api/accounts/trainer/references/')
    self.assertEqual(listing.data['usage'], {'used': 1, 'limit': 1})
    second = self.client.post(
      '/api/accounts/trainer/references/',
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

  def test_client_deletion_request_reaches_trainer_and_deactivates_on_approval(self):
    created = self.client.post(
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])

    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'trainer_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
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
    queue = self.client.get('/api/accounts/trainer/reminders/upcoming/')
    action = next(item for item in queue.data['profile_edits'] if item['request_type'] == 'account_deletion')
    approved = self.client.post(
      f'/api/accounts/trainer/forms-groups/clients/{client_access.id}/change-requests/{action["id"]}/',
      {'action': 'approve'},
      format='json',
    )
    self.assertEqual(approved.status_code, 200, approved.data)
    client_access.refresh_from_db()
    self.assertFalse(client_access.is_active)

  def test_legacy_additional_information_is_normalized_and_removable(self):
    created = self.client.post(
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])
    client_access.additional_info = [
      {'label': 'Emergency Contact', 'value': 'Mia, 555-2010'},
      {'label': 'Training Days', 'value': 'Monday and Friday'},
    ]
    client_access.save(update_fields=['additional_info'])

    detail = self.client.get(f'/api/accounts/trainer/forms-groups/clients/{client_access.id}/')
    items = detail.data['client']['additional_info']
    self.assertEqual([item['title'] for item in items], ['Emergency Contact', 'Training Days'])
    self.assertTrue(all(item['id'] for item in items))

    updated = self.client.put(
      f'/api/accounts/trainer/forms-groups/clients/{client_access.id}/additional-info/',
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
      '/api/accounts/trainer/profile/visibility/',
      {'visibility': visibility},
      format='json',
    )
    self.assertEqual(response.status_code, 200, response.data)
    self.assertEqual(response.data['profile_visibility'], visibility)

    self.profile.refresh_from_db()
    self.assertEqual(self.profile.profile_visibility, visibility)

  def test_client_logout_revokes_the_current_token(self):
    created = self.client.post(
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'trainer_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
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
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(send_credentials=False),
      format='json',
    )
    self.assertEqual(created.status_code, 201, created.data)
    client_access = ClientAccess.objects.get(pk=created.data['client_access']['id'])

    ChatMessage.objects.create(
      trainer=self.user,
      client=client_access,
      sender=ChatMessage.SENDER_CLIENT,
      text='Can you review my workout?',
    )
    trainer_unread = self.client.get('/api/accounts/trainer/chat/unread/')
    self.assertEqual(trainer_unread.status_code, 200, trainer_unread.data)
    self.assertEqual(trainer_unread.data['unread_count'], 1)
    self.assertEqual(trainer_unread.data['by_client'][str(client_access.id)], 1)

    opened_by_trainer = self.client.get(f'/api/accounts/trainer/clients/{client_access.id}/chat/')
    self.assertEqual(opened_by_trainer.status_code, 200, opened_by_trainer.data)
    self.assertEqual(self.client.get('/api/accounts/trainer/chat/unread/').data['unread_count'], 0)

    self.client.post(
      f'/api/accounts/trainer/clients/{client_access.id}/chat/',
      {'text': 'I reviewed it and left feedback.'},
      format='json',
    )
    self.client.force_authenticate(user=None)
    login = self.client.post(
      '/api/accounts/client/login/',
      {'trainer_id': 'coach-taylor', 'username': 'rahul.kumar', 'password': 'Temp!Pass7'},
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
      '/api/accounts/trainer/templates/',
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
      '/api/accounts/trainer/forms-groups/clients/manual/',
      self.manual_payload(),
      format='json',
    )
    self.assertEqual(made_client.status_code, 201, made_client.data)
    client_id = made_client.data['client_access']['id']

    assigned = self.client.post(
      f'/api/accounts/trainer/forms-groups/clients/{client_id}/assignments/',
      {'template_id': template_id, 'reference_ids': []},
      format='json',
    )
    self.assertEqual(assigned.status_code, 201, assigned.data)
    assignment_id = assigned.data['assignment']['id']

    # Assigned: the delete must be refused and the template must survive.
    refused = self.client.delete(f'/api/accounts/trainer/templates/{template_id}/')
    self.assertEqual(refused.status_code, 400, refused.data)
    self.assertEqual(refused.data['assigned_count'], 1)
    self.assertIn('Remove it from every client', refused.data['message'])
    self.assertTrue(TrackingTemplate.objects.filter(id=template_id).exists())
    self.assertTrue(TemplateAssignment.objects.filter(id=assignment_id).exists())

    # Unassigned: the delete now goes through.
    unassigned = self.client.delete(
      f'/api/accounts/trainer/forms-groups/clients/{client_id}/assignments/{assignment_id}/'
    )
    self.assertEqual(unassigned.status_code, 200, unassigned.data)

    deleted = self.client.delete(f'/api/accounts/trainer/templates/{template_id}/')
    self.assertEqual(deleted.status_code, 200, deleted.data)
    self.assertFalse(TrackingTemplate.objects.filter(id=template_id).exists())
