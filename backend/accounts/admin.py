from django.contrib import admin

from .models import RecycledTrainerAccount, TrainerProfile


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
