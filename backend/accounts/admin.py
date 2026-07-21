from django.contrib import admin

from .models import (
  ChatMessage,
  ClientAccess,
  ClientAuthToken,
  ClientRegistrationForm,
  LeadSubmission,
  RecycledProfessionalAccount,
  ReferenceCategory,
  TemplateAssignment,
  TrackingEntry,
  TrackingTemplate,
  ProfessionalGroup,
  ProfessionalLeadForm,
  ProfessionalProfile,
  ProfessionalReference,
)


@admin.register(ProfessionalProfile)
class ProfessionalProfileAdmin(admin.ModelAdmin):
  list_display = ('user', 'professional_id', 'profile_setup_completed', 'country', 'state', 'gender', 'created_at')
  search_fields = ('professional_id', 'user__username', 'user__email', 'user__first_name', 'user__last_name', 'professional_headline')
  list_filter = ('profile_setup_completed', 'country', 'gender')


@admin.register(RecycledProfessionalAccount)
class RecycledProfessionalAccountAdmin(admin.ModelAdmin):
  list_display = ('email', 'username', 'original_user_id', 'deleted_at')
  search_fields = ('email', 'username', 'first_name', 'last_name')
  readonly_fields = ('original_user_id', 'email', 'username', 'first_name', 'last_name', 'account_snapshot', 'deleted_at')


@admin.register(ProfessionalLeadForm)
class ProfessionalLeadFormAdmin(admin.ModelAdmin):
  list_display = ('professional', 'public_slug', 'title', 'is_active', 'created_at', 'updated_at')
  search_fields = ('professional__username', 'professional__email', 'public_slug', 'title')
  list_filter = ('is_active',)


@admin.register(ProfessionalGroup)
class ProfessionalGroupAdmin(admin.ModelAdmin):
  list_display = ('name', 'professional', 'is_active', 'created_at', 'updated_at')
  search_fields = ('name', 'professional__username', 'professional__email')
  list_filter = ('is_active',)


@admin.register(ClientRegistrationForm)
class ClientRegistrationFormAdmin(admin.ModelAdmin):
  list_display = ('group', 'is_active', 'created_at', 'updated_at')
  search_fields = ('group__name', 'group__professional__username')
  list_filter = ('is_active',)


@admin.register(LeadSubmission)
class LeadSubmissionAdmin(admin.ModelAdmin):
  list_display = ('reference_id', 'status', 'is_active', 'submitted_at', 'converted_at', 'deleted_at')
  search_fields = ('reference_id', 'first_name', 'last_name', 'email')
  list_filter = ('status', 'is_active')


@admin.register(ClientAccess)
class ClientAccessAdmin(admin.ModelAdmin):
  list_display = ('username', 'professional', 'group', 'is_active', 'must_change_password', 'created_at', 'updated_at')
  search_fields = ('username', 'email', 'professional__username', 'group__name')
  list_filter = ('is_active', 'must_change_password')


@admin.register(ReferenceCategory)
class ReferenceCategoryAdmin(admin.ModelAdmin):
  list_display = ('name', 'professional', 'created_at', 'updated_at')
  search_fields = ('name', 'professional__username', 'professional__email')


@admin.register(ProfessionalReference)
class ProfessionalReferenceAdmin(admin.ModelAdmin):
  list_display = ('title', 'professional', 'category', 'reference_type', 'created_at')
  search_fields = ('title', 'professional__username', 'category__name', 'subcategory')
  list_filter = ('reference_type',)


@admin.register(TrackingTemplate)
class TrackingTemplateAdmin(admin.ModelAdmin):
  list_display = ('name', 'professional', 'cadence', 'standard_key', 'is_active', 'created_at')
  search_fields = ('name', 'professional__username', 'professional__email')
  list_filter = ('cadence', 'is_active')


@admin.register(TemplateAssignment)
class TemplateAssignmentAdmin(admin.ModelAdmin):
  list_display = ('template', 'client', 'assigned_at')
  search_fields = ('template__name', 'client__username', 'client__email')


@admin.register(TrackingEntry)
class TrackingEntryAdmin(admin.ModelAdmin):
  list_display = ('client', 'template_name', 'entry_date', 'edited_by_professional', 'updated_at')
  search_fields = ('client__username', 'client__email', 'template_name')
  list_filter = ('edited_by_professional',)


@admin.register(ChatMessage)
class ChatMessageAdmin(admin.ModelAdmin):
  list_display = ('client', 'professional', 'sender', 'is_read', 'created_at')
  search_fields = ('client__username', 'professional__username', 'text')
  list_filter = ('sender', 'is_read')


@admin.register(ClientAuthToken)
class ClientAuthTokenAdmin(admin.ModelAdmin):
  list_display = ('client', 'created_at')
  search_fields = ('client__username', 'client__email')
  readonly_fields = ('key', 'created_at')
