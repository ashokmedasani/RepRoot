from django.urls import path

from .views import (
  AdminAuditLogListView, AdminDashboardView, AdminErrorLogActionView, AdminErrorLogDetailView,
  AdminErrorLogListView, AdminFinanceView, AdminLoginView, AdminLogoutView, AdminMeView,
  AdminSupportIncidentActionView, AdminSupportIncidentDetailView, AdminSupportIncidentListView,
)

urlpatterns = [
  path('login/', AdminLoginView.as_view(), name='admin-portal-login'),
  path('logout/', AdminLogoutView.as_view(), name='admin-portal-logout'),
  path('me/', AdminMeView.as_view(), name='admin-portal-me'),
  path('dashboard/', AdminDashboardView.as_view(), name='admin-portal-dashboard'),
  path('finance/', AdminFinanceView.as_view(), name='admin-portal-finance'),
  path('audit-logs/', AdminAuditLogListView.as_view(), name='admin-portal-audit-logs'),
  path('support/incidents/', AdminSupportIncidentListView.as_view(), name='admin-support-incidents'),
  path('support/incidents/<str:incident_id>/', AdminSupportIncidentDetailView.as_view(), name='admin-support-incident-detail'),
  path('support/incidents/<str:incident_id>/action/', AdminSupportIncidentActionView.as_view(), name='admin-support-incident-action'),
  path('errors/', AdminErrorLogListView.as_view(), name='admin-error-logs'),
  path('errors/<str:error_id>/', AdminErrorLogDetailView.as_view(), name='admin-error-log-detail'),
  path('errors/<str:error_id>/action/', AdminErrorLogActionView.as_view(), name='admin-error-log-action'),
]
