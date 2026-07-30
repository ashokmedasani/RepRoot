import { Component, OnDestroy, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';

import { ProfessionalAuthApiService, ProfessionalSignupPayload } from '@core/api/professional-auth-api.service';
import { AuthPageShellComponent } from '@studio-shared/auth-page-shell/auth-page-shell.component';
import { PasswordInputComponent } from '@studio-shared/password-input/password-input.component';
import { PasswordRequirementsComponent } from '@studio-shared/password-requirements/password-requirements.component';
import { isPasswordStrong } from '@studio-shared/password-requirements/password-requirements.util';
import { GoogleSigninButtonComponent } from '@studio-shared/google-signin-button/google-signin-button.component';

type EmailOtpStatus = 'idle' | 'sending' | 'sent' | 'verified' | 'failed';
type UsernameStatus = 'idle' | 'available' | 'taken' | 'failed';

@Component({
  selector: 'app-professional-signup',
  standalone: true,
  imports: [FormsModule, RouterLink, PasswordInputComponent, PasswordRequirementsComponent, GoogleSigninButtonComponent, AuthPageShellComponent],
  templateUrl: './professional-signup.component.html',
  styleUrl: './professional-signup.component.scss'
})
export class ProfessionalSignupComponent implements OnDestroy {
  private readonly professionalAuthApi = inject(ProfessionalAuthApiService);
  private readonly router = inject(Router);
  private resendTimerId: number | undefined;

  signupMessage = '';
  emailCheckMessage = '';
  usernameCheckMessage = '';
  isCheckingEmail = false;
  isVerifyingOtp = false;
  isCheckingUsername = false;
  isSubmitting = false;
  emailVerificationToken = '';
  localDebugOtp = '';
  emailOtpStatus: EmailOtpStatus = 'idle';
  usernameStatus: UsernameStatus = 'idle';
  usernameSuggestions: string[] = [];
  verifiedUsername = '';
  isEmailAlreadyRegistered = false;
  resendCountdown = 0;
  agreedToTerms = false;
  isGoogleAvailable = true;
  isGoogleSubmitting = false;

  readonly signupForm = {
    email: '',
    emailOtp: '',
    password: '',
    confirmPassword: '',
    username: ''
  };

  fieldErrors = {
    username: '',
    email: '',
    otp: '',
    password: '',
    confirmPassword: '',
    general: ''
  };

  get emailOtpHelpText(): string {
    if (this.emailOtpStatus === 'verified') {
      return 'Email verified successfully.';
    }

    if (this.emailOtpStatus === 'failed') {
      return '';
    }

    if (this.emailOtpStatus === 'sending') {
      return 'Sending verification code...';
    }

    if (this.emailOtpStatus === 'sent') {
      return 'OTP sent to your email. Please submit your OTP and verify.';
    }

    return '';
  }

  get sendOtpButtonText(): string {
    return this.isCheckingEmail || this.emailOtpStatus === 'sending' ? 'Sending...' : 'Send OTP';
  }

  get verifyOtpButtonText(): string {
    if (this.emailOtpStatus === 'verified') {
      return 'Verified';
    }

    if (this.isVerifyingOtp) {
      return 'Verifying...';
    }

    if (this.emailOtpStatus === 'failed') {
      return 'Not verified. Try again';
    }

    return 'Verify Email';
  }

  get canSendOtp(): boolean {
    return (
      !this.isCheckingEmail &&
      this.emailOtpStatus !== 'sending' &&
      this.emailOtpStatus !== 'sent' &&
      this.emailOtpStatus !== 'verified'
    );
  }

  get canResendOtp(): boolean {
    return !this.isCheckingEmail && this.resendCountdown === 0 && this.emailOtpStatus === 'sent';
  }

  get canVerifyOtp(): boolean {
    return (
      !this.isVerifyingOtp &&
      this.emailOtpStatus !== 'verified' &&
      this.emailOtpStatus !== 'idle' &&
      this.emailOtpStatus !== 'sending'
    );
  }

  ngOnDestroy(): void {
    this.clearResendTimer();
  }

  handleUsernameChange(): void {
    this.usernameStatus = 'idle';
    this.verifiedUsername = '';
    this.usernameCheckMessage = '';
    this.usernameSuggestions = [];
    this.fieldErrors.username = '';
  }

  applyUsernameSuggestion(suggestion: string): void {
    this.signupForm.username = suggestion;
    this.usernameSuggestions = [];
    this.verifyUsername();
  }

  handleEmailChange(): void {
    this.emailVerificationToken = '';
    this.localDebugOtp = '';
    this.emailOtpStatus = 'idle';
    this.isEmailAlreadyRegistered = false;
    this.emailCheckMessage = '';
    this.fieldErrors.email = '';
    this.fieldErrors.otp = '';
    this.clearResendTimer();
    this.resendCountdown = 0;
  }

  handleOtpChange(): void {
    this.fieldErrors.otp = '';

    if (this.emailOtpStatus === 'failed') {
      this.emailOtpStatus = 'sent';
    }
  }

  handlePasswordChange(): void {
    this.fieldErrors.password = '';

    if (this.signupForm.confirmPassword && this.signupForm.password !== this.signupForm.confirmPassword) {
      this.fieldErrors.confirmPassword = 'Confirm password must match Password.';
      return;
    }

    this.fieldErrors.confirmPassword = '';
  }

  handleConfirmPasswordChange(): void {
    this.fieldErrors.confirmPassword =
      this.signupForm.confirmPassword && this.signupForm.password !== this.signupForm.confirmPassword
        ? 'Confirm password must match Password.'
        : '';
  }

  requestEmailOtp(isResend = false): void {
    const email = this.signupForm.email.trim().toLowerCase();

    if (!email) {
      this.fieldErrors.email = 'Email is required.';
      return;
    }

    if ((!isResend && !this.canSendOtp) || (isResend && !this.canResendOtp)) {
      return;
    }

    this.isCheckingEmail = true;
    this.emailVerificationToken = '';
    this.localDebugOtp = '';
    this.isEmailAlreadyRegistered = false;
    this.emailOtpStatus = 'sending';
    this.fieldErrors.email = '';
    this.fieldErrors.otp = '';
    this.emailCheckMessage = isResend ? 'Sending verification code...' : 'Checking email...';

    if (isResend) {
      this.sendOtpToAvailableEmail(email);
      return;
    }

    this.professionalAuthApi.checkEmail(email).subscribe({
      next: (response) => {
        if (!response.available) {
          this.isEmailAlreadyRegistered = true;
          this.emailCheckMessage = 'Email exists already.';
          this.fieldErrors.email = '';
          this.emailOtpStatus = 'idle';
          this.isCheckingEmail = false;
          return;
        }

        this.sendOtpToAvailableEmail(email);
      },
      error: (error: unknown) => {
        this.emailOtpStatus = 'failed';
        this.localDebugOtp = '';
        this.emailCheckMessage = this.formatApiError(
          error,
          'We could not check this email right now. Please try again shortly.'
        );
        this.isCheckingEmail = false;
      }
    });
  }

  verifyEmailOtp(): void {
    const email = this.signupForm.email.trim().toLowerCase();
    const otp = this.signupForm.emailOtp.trim();

    if (!email || !otp) {
      this.fieldErrors.otp = 'OTP is required.';
      return;
    }

    this.isVerifyingOtp = true;
    this.fieldErrors.otp = '';
    this.emailCheckMessage = 'Verifying email code...';

    this.professionalAuthApi.verifyEmailOtp(email, otp).subscribe({
      next: (response) => {
        this.emailVerificationToken = response.email_verification_token;
        this.emailOtpStatus = 'verified';
        this.emailCheckMessage = response.message;
        this.fieldErrors.otp = '';
        this.clearResendTimer();
        this.isVerifyingOtp = false;
      },
      error: () => {
        this.emailVerificationToken = '';
        this.localDebugOtp = '';
        this.emailOtpStatus = 'failed';
        this.fieldErrors.otp = 'OTP is not verified. Please try again.';
        this.emailCheckMessage = '';
        this.isVerifyingOtp = false;
      }
    });
  }

  verifyUsername(): void {
    const username = this.signupForm.username.trim().toLowerCase();

    const usernameLengthError = this.getUsernameLengthError(username);

    if (usernameLengthError) {
      this.fieldErrors.username = usernameLengthError;
      return;
    }

    this.isCheckingUsername = true;
    this.fieldErrors.username = '';
    this.usernameStatus = 'idle';
    this.usernameCheckMessage = 'Checking username...';

    this.professionalAuthApi.checkUsername(username).subscribe({
      next: (response) => {
        this.usernameStatus = response.available ? 'available' : 'taken';
        this.verifiedUsername = response.available ? username : '';
        this.usernameCheckMessage = response.available
          ? `${username} is available.`
          : '';
        this.fieldErrors.username = response.available ? '' : response.message;
        this.usernameSuggestions = response.available ? [] : response.suggestions || [];
        this.isCheckingUsername = false;
      },
      error: () => {
        this.usernameStatus = 'failed';
        this.fieldErrors.username = 'Could not verify username. Please refresh and try again.';
        this.usernameCheckMessage = '';
        this.usernameSuggestions = [];
        this.isCheckingUsername = false;
      }
    });
  }

  handleGoogleUnavailable(): void {
    this.isGoogleAvailable = false;
  }

  handleGoogleLoadError(message: string): void {
    this.signupMessage = '';
    this.fieldErrors.general = message;
  }

  handleGoogleCredential(credential: string): void {
    this.isGoogleSubmitting = true;
    this.fieldErrors.general = '';
    this.signupMessage = 'Verifying with Google...';

    this.professionalAuthApi.googleAuth(credential).subscribe({
      next: (response) => {
        window.localStorage.setItem('professional-auth-token', response.token);
        window.localStorage.setItem('professional-account-id', String(response.professional.id));
        window.localStorage.setItem('professional-account-username', response.professional.username);
        this.isGoogleSubmitting = false;
        // New Google signups always need Profile Setup; existing Google
        // logins from this page follow the same profile-completion check as
        // the regular login flow. Either way we never send the user back to
        // the login screen.
        void this.router.navigate([
          response.professional.profile_setup_completed ? '/professional/dashboard' : '/professional/profile-setup'
        ]);
      },
      error: (error: unknown) => {
        this.signupMessage = '';
        this.fieldErrors.general = this.formatApiError(error, 'Google sign-up failed. Please try again.');
        this.isGoogleSubmitting = false;
      }
    });
  }

  createProfessionalAccount(): void {
    this.clearFieldErrors();
    const form = this.signupForm;
    const username = form.username.trim().toLowerCase();

    if (!this.validateSignupFields(username)) {
      this.signupMessage = '';
      return;
    }

    if (!this.agreedToTerms) {
      this.fieldErrors.general = 'Please accept the Terms & Conditions and Privacy Policy to continue.';
      this.signupMessage = '';
      return;
    }

    if (!this.emailVerificationToken || this.emailOtpStatus !== 'verified') {
      this.fieldErrors.otp = 'Please verify your email with OTP before creating the account.';
      this.signupMessage = '';
      return;
    }

    if (this.usernameStatus !== 'available' || this.verifiedUsername !== username) {
      this.fieldErrors.username = 'Please verify username availability before creating the account.';
      this.signupMessage = '';
      return;
    }

    const payload: ProfessionalSignupPayload = {
      email: form.email.trim().toLowerCase(),
      username,
      password: form.password,
      confirm_password: form.confirmPassword,
      email_verification_token: this.emailVerificationToken
    };

    this.isSubmitting = true;
    this.signupMessage = 'Creating professional account...';

    this.professionalAuthApi.signup(payload).subscribe({
      next: (response) => {
        window.localStorage.removeItem('professional-auth-token');
        window.sessionStorage.setItem('professional-login-notice', `${response.message} Please login now.`);
        this.clearSignupState();
        this.isSubmitting = false;
        void this.router.navigate(['/professional/login']);
      },
      error: (error: unknown) => {
        this.applySignupApiErrors(error);
        this.isSubmitting = false;
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

  private sendOtpToAvailableEmail(email: string): void {
    this.emailCheckMessage = 'Sending verification code...';

    this.professionalAuthApi.requestEmailOtp(email).subscribe({
      next: (response) => {
        if (response.available === false) {
          this.isEmailAlreadyRegistered = true;
          this.emailCheckMessage = 'Email exists already.';
          this.fieldErrors.email = '';
          this.emailOtpStatus = 'idle';
          this.isCheckingEmail = false;
          return;
        }

        this.emailCheckMessage = response.message;
        this.localDebugOtp = response.dev_otp || '';
        this.emailOtpStatus = 'sent';
        this.signupForm.emailOtp = '';
        this.startResendCountdown();
        this.isCheckingEmail = false;
      },
      error: (error: unknown) => {
        this.emailOtpStatus = 'failed';
        this.localDebugOtp = '';
        const message = this.formatApiError(
          error,
          'We could not send the verification code right now. Please try again shortly.'
        );
        this.isEmailAlreadyRegistered = message.toLowerCase().includes('already registered');
        this.emailCheckMessage = this.isEmailAlreadyRegistered ? 'Email exists already.' : message;
        this.fieldErrors.email = this.isEmailAlreadyRegistered ? '' : message;
        this.isCheckingEmail = false;
      }
    });
  }

  private clearSignupState(): void {
    this.signupForm.email = '';
    this.signupForm.emailOtp = '';
    this.signupForm.password = '';
    this.signupForm.confirmPassword = '';
    this.signupForm.username = '';
    this.signupMessage = '';
    this.emailCheckMessage = '';
    this.usernameCheckMessage = '';
    this.clearFieldErrors();
    this.emailVerificationToken = '';
    this.localDebugOtp = '';
    this.emailOtpStatus = 'idle';
    this.usernameStatus = 'idle';
    this.usernameSuggestions = [];
    this.verifiedUsername = '';
    this.isEmailAlreadyRegistered = false;
    this.resendCountdown = 0;
    this.clearResendTimer();
  }

  private validateSignupFields(username: string): boolean {
    let isValid = true;
    const form = this.signupForm;

    const usernameLengthError = this.getUsernameLengthError(username);

    if (usernameLengthError) {
      this.fieldErrors.username = usernameLengthError;
      isValid = false;
    }

    if (!form.email.trim()) {
      this.fieldErrors.email = 'Email is required.';
      isValid = false;
    }

    if (!isPasswordStrong(form.password)) {
      this.fieldErrors.password = 'Password does not meet all requirements below.';
      isValid = false;
    }

    if (!form.confirmPassword) {
      this.fieldErrors.confirmPassword = 'Confirm password is required.';
      isValid = false;
    } else if (form.password !== form.confirmPassword) {
      this.fieldErrors.confirmPassword = 'Confirm password must match Password.';
      isValid = false;
    }

    return isValid;
  }

  get isPasswordRequirementsMet(): boolean {
    return isPasswordStrong(this.signupForm.password);
  }

  private applySignupApiErrors(error: unknown): void {
    const responseError = error instanceof HttpErrorResponse ? error.error : error;
    const apiError = responseError as { error?: Record<string, string[] | string> | string; message?: string };

    if (!apiError.error || typeof apiError.error === 'string') {
      this.fieldErrors.general = apiError.message || apiError.error || 'Please refresh and try again.';
      this.signupMessage = '';
      return;
    }

    const errorMap: Record<string, keyof typeof this.fieldErrors> = {
      username: 'username',
      email: 'email',
      email_verification_token: 'otp',
      password: 'password',
      confirm_password: 'confirmPassword',
      non_field_errors: 'general'
    };

    for (const [apiField, messages] of Object.entries(apiError.error)) {
      const localField = errorMap[apiField] || 'general';
      const message = Array.isArray(messages) ? messages[0] : messages;
      this.fieldErrors[localField] = message || 'Please refresh and try again.';
    }

    this.signupMessage = '';
  }

  private clearFieldErrors(): void {
    this.fieldErrors.username = '';
    this.fieldErrors.email = '';
    this.fieldErrors.otp = '';
    this.fieldErrors.password = '';
    this.fieldErrors.confirmPassword = '';
    this.fieldErrors.general = '';
  }

  private getUsernameLengthError(username: string): string {
    if (!username) {
      return 'Username is required.';
    }

    if (username.length < 5) {
      return 'Username must be at least 5 characters.';
    }

    if (username.length > 30) {
      return 'Username must be no more than 30 characters.';
    }

    if (/\s/.test(username) || !/^[A-Za-z0-9.-]+$/.test(username)) {
      return "Only letters, numbers, '.' and '-' are allowed.";
    }

    return '';
  }

  private clearResendTimer(): void {
    if (this.resendTimerId !== undefined) {
      window.clearInterval(this.resendTimerId);
      this.resendTimerId = undefined;
    }
  }
}
