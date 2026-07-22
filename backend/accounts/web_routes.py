"""Canonical frontend destinations used by backend-generated notifications."""

PROFESSIONAL_FORMS_GROUPS = '/professional/forms-groups'
PROFESSIONAL_CLIENTS = '/professional/clients'
CLIENT_PROGRAMS = '/client/profile?tab=templates'
CLIENT_PROGRESS = '/client/dashboard'
CLIENT_MEETINGS = '/client/meetings'
CLIENT_PROFESSIONAL = '/client/profile?tab=professional&professionalTab=profile'
CLIENT_PAYMENTS = '/client/payments'


def professional_client(client_id):
  return f'/professional/clients/{client_id}'


def professional_form_request(submission_id):
  return f'/professional/forms-groups/requests/{submission_id}'


def client_payment_request(request_id):
  return f'/client/payments/requests/{request_id}'
