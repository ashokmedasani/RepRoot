export interface PasswordRequirement {
  key: string;
  label: string;
  test: (password: string) => boolean;
}

export interface PasswordRequirementStatus {
  key: string;
  label: string;
  met: boolean;
}

/**
 * Single source of truth for the professional-account password policy on the
 * frontend. Must stay in sync with `validate_strong_password` in
 * backend/accounts/serializers.py.
 */
export const PASSWORD_REQUIREMENTS: PasswordRequirement[] = [
  { key: 'length', label: 'At least 8 characters', test: (password) => password.length >= 8 },
  { key: 'uppercase', label: 'One uppercase letter', test: (password) => /[A-Z]/.test(password) },
  { key: 'lowercase', label: 'One lowercase letter', test: (password) => /[a-z]/.test(password) },
  { key: 'number', label: 'One number', test: (password) => /[0-9]/.test(password) },
  { key: 'special', label: 'One special character', test: (password) => /[^A-Za-z0-9]/.test(password) }
];

export function getPasswordRequirementStatus(password: string): PasswordRequirementStatus[] {
  const value = password || '';
  return PASSWORD_REQUIREMENTS.map((requirement) => ({
    key: requirement.key,
    label: requirement.label,
    met: requirement.test(value)
  }));
}

export function isPasswordStrong(password: string): boolean {
  const value = password || '';
  return PASSWORD_REQUIREMENTS.every((requirement) => requirement.test(value));
}
