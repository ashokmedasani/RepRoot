"""Canonical frontend destinations used by backend-generated notifications."""

PROFESSIONAL_FORMS_GROUPS = '/professional/forms-groups'
PROFESSIONAL_CLIENTS = '/professional/clients'
PROFESSIONAL_SCHEDULE = '/professional/schedule'
CLIENT_PROGRAMS = '/client/profile?tab=templates'
CLIENT_PROGRESS = '/client/dashboard'
CLIENT_MEETINGS = '/client/meetings'
CLIENT_PROFESSIONAL = '/client/profile?tab=professional&professionalTab=profile'
CLIENT_PAYMENTS = '/client/payments'


def professional_client(client_id):
  return f'/professional/clients/{client_id}?section=overview'


def professional_form_request(submission_id):
  return f'/professional/forms-groups/requests/{submission_id}'


def client_payment_request(request_id):
  return f'/client/payments/requests/{request_id}'


def professional_meeting(meeting_id):
  return f'{PROFESSIONAL_SCHEDULE}?meeting={meeting_id}'


def client_meeting(meeting_id):
  return f'{CLIENT_MEETINGS}?meeting={meeting_id}'


def professional_payment_request(client_id, request_id):
  return f'/professional/clients/{client_id}?tab=payments&paymentTab=requests&request={request_id}'
