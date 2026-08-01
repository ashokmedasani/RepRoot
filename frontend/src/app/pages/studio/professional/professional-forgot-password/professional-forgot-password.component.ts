import { Component, OnDestroy, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';

import { ProfessionalAuthApiService } from '@core/api/professional-auth-api.service';
import { AuthPageShellComponent } from '@studio-shared/auth-page-shell/auth-page-shell.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { PasswordRequirementsComponent } from '@studio-shared/password-requirements/password-requirements.component';
import { isPasswordStrong } from '@studio-shared/password-requirements/password-requirements.util';

type ResetOtpStatus = 'idle' | 'sent' | 'verified' | 'failed';

@Component({
  selector: 'app-professional-forgot-password',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent, PasswordRequirementsComponent, AuthPageShellComponent],
  templateUrl: './professional-forgot-password.component.html',
  styleUrl: './professional-forgot-password.component.scss'
})
export class ProfessionalForgotPasswordComponent implements OnDestroy {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);
  private resendTimerId: number | undefined;

  resetMessage = '';
  resetOtpMessage = '';
  resetToken = '';
  isRequestingOtp = false;
  isVerifyingOtp = false;
  isResettingPassword = false;
  resetOtpStatus: ResetOtpStatus = 'idle';
  isEmailMissing = false;
  resendCountdown = 0;

  readonly resetForm = {
    email: '',
    otp: '',
    password: '',
    confirmPassword: ''
  };

  resetFieldErrors = {
    email: '',
    otp: '',
    password: '',
    confirmPassword: '',
    general: ''
  };

  get resetOtpHelpText(): string {
    if (this.resetOtpStatus === 'verified') {
      return 'Email verified successfully.';
    }

    if (this.resetOtpStatus === 'failed') {
      return '';
    }

    if (this.resetOtpStatus === 'sent') {
      return 'OTP sent to your email. Please submit your OTP and verify.';
    }

    return '';
  }

  get sendOtpButtonText(): string {
    return this.isRequestingOtp ? 'Sending...' : 'Send OTP';
  }

  get verifyOtpButtonText(): string {
    if (this.resetOtpStatus === 'verified') {
      return 'Verified';
    }

    if (this.isVerifyingOtp) {
      return 'Verifying...';
    }

    if (this.resetOtpStatus === 'failed') {
      return 'Not verified. Try again';
    }

    return 'Verify Email';
  }

  get canSendOtp(): boolean {
    return !this.isRequestingOtp && this.resetOtpStatus !== 'sent' && this.resetOtpStatus !== 'verified';
  }

  get canResendOtp(): boolean {
    return !this.isRequestingOtp && this.resendCountdown === 0 && this.resetOtpStatus === 'sent';
  }

  get canVerifyOtp(): boolean {
    return !this.isVerifyingOtp && this.resetOtpStatus !== 'verified' && this.resetOtpStatus !== 'idle' && /^\d{6}$/.test(this.resetForm.otp.trim());
  }

  ngOnDestroy(): void {
    this.clearResendTimer();
  }

  handleResetOtpChange(): void {
    this.resetFieldErrors.otp = '';

    if (this.resetOtpStatus === 'failed') {
      this.resetOtpStatus = 'sent';
    }
  }

  handleResetPasswordChange(): void {
    this.resetFieldErrors.password = '';

    if (this.resetForm.confirmPassword && this.resetForm.password !== this.resetForm.confirmPassword) {
      this.resetFieldErrors.confirmPassword = 'Confirm password must match Password.';
      return;
    }

    this.resetFieldErrors.confirmPassword = '';
  }

  handleResetConfirmPasswordChange(): void {
    this.resetFieldErrors.confirmPassword =
      this.resetForm.confirmPassword && this.resetForm.password !== this.resetForm.confirmPassword
        ? 'Confirm password must match Password.'
        : '';
  }

  requestOtp(isResend = false): void {
    const email = this.resetForm.email.trim().toLowerCase();

    if (!email) {
      this.resetFieldErrors.email = 'Email is required.';
      return;
    }

    if ((!isResend && !this.canSendOtp) || (isResend && !this.canResendOtp)) {
      return;
    }

    this.resetToken = '';
    this.isRequestingOtp = true;
    this.isEmailMissing = false;
    this.resetOtpStatus = isResend ? 'sent' : 'idle';
    this.resetMessage = '';
    this.clearResetFieldErrors();
    this.resetOtpMessage = isResend ? 'Sending password reset code...' : 'Checking email...';

    if (isResend) {
      this.sendResetOtpToExistingEmail(email);
      return;
    }

    this.professionalAuthApi.checkEmail(email).subscribe({
      next: (response) => {
        if (response.available) {
          this.isEmailMissing = true;
          this.resetOtpMessage = 'No professional account found for this email.';
          this.resetOtpStatus = 'idle';
          this.isRequestingOtp = false;
          return;
        }

        this.sendResetOtpToExistingEmail(email);
      },
      error: (error: unknown) => {
        this.resetOtpStatus = 'failed';
        this.resetOtpMessage = this.formatApiError(error, 'We could not check this email right now. Please try again shortly.');
        this.isRequestingOtp = false;
      }
    });
  }

  verifyOtp(): void {
    const email = this.resetForm.email.trim().toLowerCase();
    const otp = this.resetForm.otp.trim();

    if (!email || !/^\d{6}$/.test(otp)) {
      this.resetFieldErrors.otp = 'Enter the complete 6-digit verification code.';
      return;
    }

    this.isVerifyingOtp = true;
    this.resetFieldErrors.otp = '';
    this.resetOtpMessage = 'Verifying reset code...';

    this.professionalAuthApi.verifyPasswordResetOtp(email, otp).subscribe({
      next: (response) => {
        this.resetToken = response.reset_token;
        this.resetOtpStatus = 'verified';
        this.resetOtpMessage = response.message;
        this.resetFieldErrors.otp = '';
        this.clearResendTimer();
        this.isVerifyingOtp = false;
      },
      error: () => {
        this.resetToken = '';
        this.resetOtpStatus = 'failed';
        this.resetFieldErrors.otp = 'OTP is not verified. Please try again.';
        this.resetOtpMessage = '';
        this.isVerifyingOtp = false;
      }
    });
  }

  resetPassword(): void {
    const email = this.resetForm.email.trim().toLowerCase();
    this.clearResetPasswordErrors();

    if (!email || !this.resetToken || !this.resetForm.password || !this.resetForm.confirmPassword) {
      if (!this.resetToken) {
        this.resetFieldErrors.otp = 'Please verify OTP before resetting password.';
      }

      if (!this.resetForm.password) {
        this.resetFieldErrors.password = 'Password is required.';
      }

      if (!this.resetForm.confirmPassword) {
        this.resetFieldErrors.confirmPassword = 'Confirm password is required.';
      }
      return;
    }

    if (!isPasswordStrong(this.resetForm.password)) {
      this.resetFieldErrors.password = 'Password does not meet all requirements below.';
      return;
    }

    if (this.resetForm.password !== this.resetForm.confirmPassword) {
      this.resetFieldErrors.confirmPassword = 'Confirm password must match Password.';
      return;
    }

    this.isResettingPassword = true;
    this.resetMessage = 'Resetting password...';

    this.professionalAuthApi
      .confirmPasswordReset(email, this.resetToken, this.resetForm.password, this.resetForm.confirmPassword)
      .subscribe({
        next: (response) => {
          window.sessionStorage.setItem('professional-login-notice', `${response.message} Please login now.`);
          this.clearResetState();
          this.isResettingPassword = false;
          void this.router.navigate(['/professional/login']);
        },
        error: (error: unknown) => {
          this.applyResetApiErrors(error);
          this.isResettingPassword = false;
        }
      });
  }

  private sendResetOtpToExistingEmail(email: string): void {
    this.resetOtpMessage = 'Sending password reset code...';

    this.professionalAuthApi.requestPasswordResetOtp(email).subscribe({
      next: (response) => {
        if (response.available === true) {
          this.isEmailMissing = true;
          this.resetOtpMessage = 'No professional account found for this email.';
          this.resetOtpStatus = 'idle';
          this.isRequestingOtp = false;
          return;
        }

        this.resetOtpMessage = response.message;
        this.resetOtpStatus = 'sent';
        this.resetForm.otp = '';
        this.startResendCountdown();
        this.isRequestingOtp = false;
      },
      error: (error: unknown) => {
        this.resetOtpStatus = 'failed';
        this.resetOtpMessage = this.formatApiError(error, 'Could not send reset code.');
        this.isRequestingOtp = false;
      }
    });
  }

  private formatApiError(error: unknown, fallbackMessage: string): string {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (apiError.message) {
      return apiError.message;
    }

    if (!apiError.error || typeof apiError.error === 'string') {
      return apiError.error || fallbackMessage;
    }

    const firstError = Object.values(apiError.error)[0];
    return Array.isArray(firstError) ? firstError[0] : firstError || fallbackMessage;
  }

  private startResendCountdown(): void {
    this.clearResendTimer();
    this.resendCountdown = 30;
    this.resendTimerId = window.setInterval(() => {
      this.resendCountdown = Math.max(0, this.resendCountdown - 1);

      if (this.resendCountdown === 0) {
        this.clearResendTimer();
      }
    }, 1000);
  }

  private clearResetState(): void {
    this.resetForm.email = '';
    this.resetForm.otp = '';
    this.resetForm.password = '';
    this.resetForm.confirmPassword = '';
    this.resetMessage = '';
    this.resetOtpMessage = '';
    this.clearResetFieldErrors();
    this.resetToken = '';
    this.resetOtpStatus = 'idle';
    this.isEmailMissing = false;
    this.resendCountdown = 0;
    this.clearResendTimer();
  }

  private clearResendTimer(): void {
    if (this.resendTimerId !== undefined) {
      window.clearInterval(this.resendTimerId);
      this.resendTimerId = undefined;
    }
  }

  get isResetPasswordRequirementsMet(): boolean {
    return isPasswordStrong(this.resetForm.password);
  }

  private applyResetApiErrors(error: unknown): void {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (!apiError.error || typeof apiError.error === 'string') {
      this.resetFieldErrors.general = apiError.message || apiError.error || 'Please refresh and try again.';
      this.resetMessage = '';
      return;
    }

    const errorMap: Record<string, keyof typeof this.resetFieldErrors> = {
      email: 'email',
      reset_token: 'otp',
      password: 'password',
      confirm_password: 'confirmPassword',
      non_field_errors: 'general'
    };

    for (const [apiField, messages] of Object.entries(apiError.error)) {
      const localField = errorMap[apiField] || 'general';
      const message = Array.isArray(messages) ? messages[0] : messages;
      this.resetFieldErrors[localField] = message || 'Please refresh and try again.';
    }

    this.resetMessage = '';
  }

  private clearResetFieldErrors(): void {
    this.resetFieldErrors.email = '';
    this.resetFieldErrors.otp = '';
    this.resetFieldErrors.password = '';
    this.resetFieldErrors.confirmPassword = '';
    this.resetFieldErrors.general = '';
  }

  private clearResetPasswordErrors(): void {
    this.resetFieldErrors.password = '';
    this.resetFieldErrors.confirmPassword = '';
    this.resetFieldErrors.general = '';
  }
}
