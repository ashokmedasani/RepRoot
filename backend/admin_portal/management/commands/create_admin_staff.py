from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from admin_portal.models import AdminRole, AdminStaffProfile


class Command(BaseCommand):
  help = 'Create an internal Admin Portal staff account. There is no public staff signup.'

  def add_arguments(self, parser):
    parser.add_argument('--username', required=True)
    parser.add_argument('--email', required=True)
    parser.add_argument('--role', default='super-admin')
    parser.add_argument('--password', required=True)
    parser.add_argument('--first-name', default='')
    parser.add_argument('--last-name', default='')

  def handle(self, *args, **options):
    User = get_user_model()
    if User.objects.filter(username__iexact=options['username']).exists():
      raise CommandError('Username already exists.')
    role = AdminRole.objects.filter(slug=options['role']).first()
    if not role:
      raise CommandError('Unknown admin role.')
    validate_password(options['password'])
    with transaction.atomic():
      user = User.objects.create_user(
        username=options['username'].lower(), email=options['email'].lower(), password=options['password'],
        first_name=options['first_name'], last_name=options['last_name'], is_staff=True,
      )
      staff = AdminStaffProfile.objects.create(user=user, role=role)
    self.stdout.write(self.style.SUCCESS(f'Created {staff.staff_id} with role {role.name}.'))
