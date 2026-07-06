import { Component, OnDestroy, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';

import { TrainerAuthApiService, TrainerSignupPayload } from '../../core/api/trainer-auth-api.service';

type EmailOtpStatus = 'idle' | 'sent' | 'verified' | 'failed';
type UsernameStatus = 'idle' | 'available' | 'taken' | 'failed';

@Component({
  selector: 'app-trainer-signup',
  standalone: true,
  imports: [FormsModule, RouterLink],
  templateUrl: './trainer-signup.component.html',
  styleUrl: './trainer-signup.component.scss'
})
export class TrainerSignupComponent implements OnDestroy {
  private readonly trainerAuthApi = inject(TrainerAuthApiService);
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
  emailOtpStatus: EmailOtpStatus = 'idle';
  usernameStatus: UsernameStatus = 'idle';
  verifiedUsername = '';
  isEmailAlreadyRegistered = false;
  resendCountdown = 0;

  readonly signupForm = {
    email: '',
    emailOtp: '',
    password: '',
    confirmPassword: '',
    firstName: '',
    middleName: '',
    lastName: '',
    username: ''
  };

  fieldErrors = {
    username: '',
    email: '',
    otp: '',
    password: '',
    confirmPassword: '',
    firstName: '',
    lastName: '',
    general: ''
  };

  get emailOtpHelpText(): string {
    if (this.emailOtpStatus === 'verified') {
      return 'Email verified successfully.';
    }

    if (this.emailOtpStatus === 'failed') {
      return '';
    }

    if (this.emailOtpStatus === 'sent') {
      return 'OTP sent to your email. Please submit your OTP and verify.';
    }

    return '';
  }

  get sendOtpButtonText(): string {
    return this.isCheckingEmail ? 'Sending...' : 'Send OTP';
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
    return !this.isCheckingEmail && this.emailOtpStatus !== 'sent' && this.emailOtpStatus !== 'verified';
  }

  get canResendOtp(): boolean {
    return !this.isCheckingEmail && this.resendCountdown === 0 && this.emailOtpStatus === 'sent';
  }

  get canVerifyOtp(): boolean {
    return !this.isVerifyingOtp && this.emailOtpStatus !== 'verified' && this.emailOtpStatus !== 'idle';
  }

  ngOnDestroy(): void {
    this.clearResendTimer();
  }

  handleUsernameChange(): void {
    this.usernameStatus = 'idle';
    this.verifiedUsername = '';
    this.usernameCheckMessage = '';
    this.fieldErrors.username = '';
  }

  handleEmailChange(): void {
    this.emailVerificationToken = '';
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
    this.isEmailAlreadyRegistered = false;
    this.emailOtpStatus = isResend ? 'sent' : 'idle';
    this.fieldErrors.email = '';
    this.fieldErrors.otp = '';
    this.emailCheckMessage = isResend ? 'Sending verification code...' : 'Checking email...';

    if (isResend) {
      this.sendOtpToAvailableEmail(email);
      return;
    }

    this.trainerAuthApi.checkEmail(email).subscribe({
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
        this.emailCheckMessage = this.formatApiError(
          error,
          'Could not check email. Start Django on port 8000 and try again.'
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

    this.trainerAuthApi.verifyEmailOtp(email, otp).subscribe({
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
        this.emailOtpStatus = 'failed';
        this.fieldErrors.otp = 'OTP is not verified. Please try again.';
        this.emailCheckMessage = '';
        this.isVerifyingOtp = false;
      }
    });
  }

  verifyUsername(): void {
    const username = this.signupForm.username.trim().toLowerCase();

    if (!username) {
      this.fieldErrors.username = 'Username is required.';
      return;
    }

    this.isCheckingUsername = true;
    this.fieldErrors.username = '';
    this.usernameStatus = 'idle';
    this.usernameCheckMessage = 'Checking username...';

    this.trainerAuthApi.checkUsername(username).subscribe({
      next: (response) => {
        this.usernameStatus = response.available ? 'available' : 'taken';
        this.verifiedUsername = response.available ? username : '';
        this.usernameCheckMessage = response.available
          ? `${username} is available.`
          : '';
        this.fieldErrors.username = response.available ? '' : response.message;
        this.isCheckingUsername = false;
      },
      error: () => {
        this.usernameStatus = 'failed';
        this.fieldErrors.username = 'Could not verify username. Please refresh and try again.';
        this.usernameCheckMessage = '';
        this.isCheckingUsername = false;
      }
    });
  }

  createTrainerAccount(): void {
    this.clearFieldErrors();
    const form = this.signupForm;
    const username = form.username.trim().toLowerCase();

    if (!this.validateSignupFields(username)) {
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

    const payload: TrainerSignupPayload = {
      email: form.email.trim().toLowerCase(),
      username,
      first_name: form.firstName.trim(),
      middle_name: form.middleName.trim(),
      last_name: form.lastName.trim(),
      password: form.password,
      confirm_password: form.confirmPassword,
      email_verification_token: this.emailVerificationToken
    };

    this.isSubmitting = true;
    this.signupMessage = 'Creating trainer account...';

    this.trainerAuthApi.signup(payload).subscribe({
      next: (response) => {
        window.localStorage.removeItem('trainer-auth-token');
        window.sessionStorage.setItem('trainer-login-notice', `${response.message} Please login now.`);
        this.clearSignupState();
        this.isSubmitting = false;
        void this.router.navigate(['/trainer/login']);
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

    this.trainerAuthApi.requestEmailOtp(email).subscribe({
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
        this.emailOtpStatus = 'sent';
        this.signupForm.emailOtp = '';
        this.startResendCountdown();
        this.isCheckingEmail = false;
      },
      error: (error: unknown) => {
        this.emailOtpStatus = 'failed';
        const message = this.formatApiError(
          error,
          'Could not send OTP. Start Django on port 8000 and try again.'
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
    this.signupForm.firstName = '';
    this.signupForm.middleName = '';
    this.signupForm.lastName = '';
    this.signupForm.username = '';
    this.signupMessage = '';
    this.emailCheckMessage = '';
    this.usernameCheckMessage = '';
    this.clearFieldErrors();
    this.emailVerificationToken = '';
    this.emailOtpStatus = 'idle';
    this.usernameStatus = 'idle';
    this.verifiedUsername = '';
    this.isEmailAlreadyRegistered = false;
    this.resendCountdown = 0;
    this.clearResendTimer();
  }

  private validateSignupFields(username: string): boolean {
    let isValid = true;
    const form = this.signupForm;

    if (!username) {
      this.fieldErrors.username = 'Username is required.';
      isValid = false;
    }

    if (!form.email.trim()) {
      this.fieldErrors.email = 'Email is required.';
      isValid = false;
    }

    if (!form.firstName.trim()) {
      this.fieldErrors.firstName = 'First name is required.';
      isValid = false;
    }

    if (!form.lastName.trim()) {
      this.fieldErrors.lastName = 'Last name is required.';
      isValid = false;
    }

    if (!this.isPasswordStrong(form.password)) {
      this.fieldErrors.password = 'Password must be at least 8 characters and include 1 special character.';
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

  private isPasswordStrong(password: string): boolean {
    return password.length >= 8 && /[^A-Za-z0-9]/.test(password);
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
      first_name: 'firstName',
      last_name: 'lastName',
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
    this.fieldErrors.firstName = '';
    this.fieldErrors.lastName = '';
    this.fieldErrors.general = '';
  }

  private clearResendTimer(): void {
    if (this.resendTimerId !== undefined) {
      window.clearInterval(this.resendTimerId);
      this.resendTimerId = undefined;
    }
  }
}
