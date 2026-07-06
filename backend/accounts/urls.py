from django.urls import path

from .views import (
  EmailAvailabilityView,
  EmailOtpRequestView,
  EmailOtpVerifyView,
  PasswordResetConfirmView,
  PasswordResetOtpRequestView,
  PasswordResetOtpVerifyView,
  TrainerAccountView,
  TrainerLoginView,
  TrainerLogoutView,
  TrainerPasswordChangeView,
  TrainerProfileStatusView,
  TrainerProfileView,
  TrainerSignupView,
  UsernameAvailabilityView,
)

urlpatterns = [
  path('trainer/check-email/', EmailAvailabilityView.as_view(), name='trainer-check-email'),
  path('trainer/request-email-otp/', EmailOtpRequestView.as_view(), name='trainer-request-email-otp'),
  path('trainer/verify-email-otp/', EmailOtpVerifyView.as_view(), name='trainer-verify-email-otp'),
  path('trainer/check-username/', UsernameAvailabilityView.as_view(), name='trainer-check-username'),
  path('trainer/signup/', TrainerSignupView.as_view(), name='trainer-signup'),
  path('trainer/login/', TrainerLoginView.as_view(), name='trainer-login'),
  path('trainer/logout/', TrainerLogoutView.as_view(), name='trainer-logout'),
  path('trainer/account/', TrainerAccountView.as_view(), name='trainer-account'),
  path('trainer/account/change-password/', TrainerPasswordChangeView.as_view(), name='trainer-change-password'),
  path('trainer/profile/status/', TrainerProfileStatusView.as_view(), name='trainer-profile-status'),
  path('trainer/profile/', TrainerProfileView.as_view(), name='trainer-profile'),
  path('trainer/password-reset/request-otp/', PasswordResetOtpRequestView.as_view(), name='trainer-password-reset-request-otp'),
  path('trainer/password-reset/verify-otp/', PasswordResetOtpVerifyView.as_view(), name='trainer-password-reset-verify-otp'),
  path('trainer/password-reset/confirm/', PasswordResetConfirmView.as_view(), name='trainer-password-reset-confirm'),
]
