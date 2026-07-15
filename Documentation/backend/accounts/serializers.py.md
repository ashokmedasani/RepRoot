# backend/accounts/serializers.py

## 2026-07-15 UI, workflow, and bug fixes

Usernames (trainer signup, availability check, and client creation) now allow only letters, numbers, '.' and '-' via `validate_username_charset`. Any other character (including spaces) returns "Only letters, numbers, '.' and '-' are allowed."

## 2026-07-13 targeted refinement

Validates manual and known-client group registration, trainer-scoped username uniqueness, credential options, current-password changes, and public registration payloads.

Cross-cutting behavior and verification are recorded in `Documentation/CHANGELOG-refinements-2026-07-13.md`.

## What this file does

Defines Django REST Framework serializers for trainer authentication, OTP flows, password reset, profile status, profile setup, Profile / Portfolio data, and Forms & Groups data.

## Why this file exists

Serializers validate API input, convert model data to API responses, and keep view classes thin.

## Page or module

Backend accounts module for Page 2 trainer access, trainer profile pages, public lead forms, groups, submitted leads, and client access creation.

## Important functions/classes/components

- `TrainerSignupSerializer`: creates Django `User` and linked `TrainerProfile`.
- `TrainerLoginSerializer`: authenticates by username or email.
- `PasswordResetConfirmSerializer`: validates reset token and updates password.
- `TrainerProfileStatusSerializer`: returns `profile_setup_completed`.
- `TrainerProfileSerializer`: reads and writes setup/Profile fields, updates first and last name on the linked user, and returns media URLs.
- `normalize_dynamic_fields`: prepends universal First Name, Last Name, and Email Address fields to custom form fields.
- `TrainerLeadFormSerializer`: saves Form 1 and returns the generated public link.
- `TrainerGroupSerializer`: returns group details and registration form status.
- `ClientRegistrationFormSerializer`: saves a group's client registration form.
- `PublicLeadSubmissionSerializer`: validates public applicant submissions.
- `ClientAccessCreateSerializer`: validates conversion payloads.
- Dynamic field metadata supports text, phone, choice, date, location, and address field types. Choice options are preserved in the JSON field metadata.
- Reporting fields such as `status`, `is_active`, `created_at`, `updated_at`, `converted_at`, and `deleted_at` are exposed where future aggregate views need them.

## Data flow

Frontend sends auth/profile/forms data to the API. Serializers validate the request, update the matching models, then return normalized response data.

## Business logic

Profile setup requires first name, last name, gender, birth month, birth year, country, and state. Forms & Groups serializers keep universal core fields required and non-removable while preserving aggregate-friendly lifecycle fields.

## Connected files

- `backend/accounts/models.py`
- `backend/accounts/views.py`
- `frontend/src/app/core/api/trainer-auth-api.service.ts`
- `frontend/src/app/core/api/forms-groups-api.service.ts`

## Future improvement notes

Split portfolio media and certifications into nested serializers when they become multi-record features.

## 2026-07-13 production audit

- Normalizes legacy and current trainer section-visibility keys without dropping Training Style, Certifications, Images, or Links.
- Normalizes legacy client additional-information rows into stable, removable items with generated IDs.
- Validates trainer uploads, certification files, and client data-image photos with explicit type and size limits.
- Adds validated payload contracts for client photos and trainer-managed Additional Details.

## Update: templates, references, and client portal

- `normalize_template_fields` + `TEMPLATE_FIELD_TYPES`: template field whitelist (number, short_text, long_text, yes_no, image); no required flags - template fields are never mandatory.
- `is_youtube_link`: enforces the YouTube-only rule for video references.
- `ReferenceCategorySerializer`, `TrainerReferenceSerializer` (multipart file upload, tags as comma string), `TrackingTemplateReferenceSerializer` (compact nested form).
- `TrackingTemplateSerializer`: accepts `custom_fields` and `reference_ids`, exposes nested references and assigned count.
- `TemplateAssignmentSerializer`, `TrackingEntrySerializer`, `ClientTrackingEntrySubmitSerializer` (client upsert payload).
- `ChatMessageSerializer` and `ClientPasswordChangeSerializer` (verifies current password, clears `must_change_password`).

## Update 2: references shared per assignment

`TrackingTemplateSerializer` dropped `references`/`reference_ids`. `TemplateAssignmentSerializer` now nests the shared `references` (compact form with absolute file URLs).

## Update 4: trainer code

- `normalize_trainer_code` validates format (4-20 chars, alphanumeric/-/_, uppercased).
- `TrainerProfileSerializer` requires `trainer_code` at profile setup (unique per trainer).
- `ClientLoginSerializer` now requires `trainer_code`, resolves the trainer by code, then matches the client username/password within that trainer.
- `TrainerCodeSerializer` backs the Settings update; `TrainerAccountSerializer`/`TrainerProfileSerializer` expose the code.
