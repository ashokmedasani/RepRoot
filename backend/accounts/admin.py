from django.contrib import admin

from .models import (
  ClientAccess,
  ClientRegistrationForm,
  LeadSubmission,
  RecycledTrainerAccount,
  TrainerGroup,
  TrainerLeadForm,
  TrainerProfile,
)


@admin.register(TrainerProfile)
class TrainerProfileAdmin(admin.ModelAdmin):
  list_display = ('user', 'profile_setup_completed', 'country', 'state', 'gender', 'created_at')
  search_fields = ('user__username', 'user__email', 'user__first_name', 'user__last_name', 'professional_headline')
  list_filter = ('profile_setup_completed', 'country', 'gender')


@admin.register(RecycledTrainerAccount)
class RecycledTrainerAccountAdmin(admin.ModelAdmin):
  list_display = ('email', 'username', 'original_user_id', 'deleted_at')
  search_fields = ('email', 'username', 'first_name', 'last_name')
  readonly_fields = ('original_user_id', 'email', 'username', 'first_name', 'last_name', 'account_snapshot', 'deleted_at')


@admin.register(TrainerLeadForm)
class TrainerLeadFormAdmin(admin.ModelAdmin):
  list_display = ('trainer', 'public_slug', 'title', 'is_active', 'created_at', 'updated_at')
  search_fields = ('trainer__username', 'trainer__email', 'public_slug', 'title')
  list_filter = ('is_active',)


@admin.register(TrainerGroup)
class TrainerGroupAdmin(admin.ModelAdmin):
  list_display = ('name', 'trainer', 'is_active', 'created_at', 'updated_at')
  search_fields = ('name', 'trainer__username', 'trainer__email')
  list_filter = ('is_active',)


@admin.register(ClientRegistrationForm)
class ClientRegistrationFormAdmin(admin.ModelAdmin):
  list_display = ('group', 'is_active', 'created_at', 'updated_at')
  search_fields = ('group__name', 'group__trainer__username')
  list_filter = ('is_active',)


@admin.register(LeadSubmission)
class LeadSubmissionAdmin(admin.ModelAdmin):
  list_display = ('reference_id', 'status', 'is_active', 'submitted_at', 'converted_at', 'deleted_at')
  search_fields = ('reference_id', 'first_name', 'last_name', 'email')
  list_filter = ('status', 'is_active')


@admin.register(ClientAccess)
class ClientAccessAdmin(admin.ModelAdmin):
  list_display = ('username', 'trainer', 'group', 'is_active', 'must_change_password', 'created_at', 'updated_at')
  search_fields = ('username', 'email', 'trainer__username', 'group__name')
  list_filter = ('is_active', 'must_change_password')
