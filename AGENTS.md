# Repository Rules for All Agents

Every agent, sub-agent, automation, and tool operating in this repository must
read and follow this file before inspecting files, running commands, or making
changes.

## Strict Environment-File Restriction

- Real environment files and secret stores are exclusively user-managed and
  are outside the agent-editable and agent-readable workspace.
- Never open, read, search, parse, print, summarize, compare, copy, modify,
  create, rename, delete, stage, commit, upload, or transmit a real environment
  file or any part of its contents.
- This restriction applies to every agent, sub-agent, automation, plugin, tool,
  and future session without exception unless the user explicitly replaces
  this rule before real secrets are present.
- Protected files include `.env`, `.env.*`, `*.env`, `*.env.*`, local override
  files, deployment secret exports, credential files, SMTP credentials, API
  keys, tokens, passwords, private keys, database URLs, production email
  settings, calendar credentials, and equivalent secret configuration wherever
  it appears.
- Do not run broad searches, directory dumps, diagnostic commands, tests, or
  scripts that could read or reveal protected environment files or values.
- Never place secrets in source code, frontend/mobile bundles, tests, fixtures,
  logs, screenshots, documentation, examples, shell history, commits, pull
  requests, chat messages, build output, or external services.
- If work requires a secret or a real environment-file change, complete all
  non-secret code changes and give the user exact manual instructions. Never
  request that the user paste the secret into chat.

## Canonical Environment Layout

- `backend/.env.example` is the single canonical, agent-readable environment
  layout for this repository.
- Agents may read or update `backend/.env.example` only when a task requires
  configuration changes.
- The example must contain variable names, safe defaults, comments, and
  obviously fake placeholders only. It must never receive a value copied from
  a real environment file or secret store.
- Configuration documentation may reference the variable names defined in
  `backend/.env.example`, but must not duplicate or contain real values.
- Agents must understand the environment layout exclusively from
  `backend/.env.example` and must never consult the real `.env` to compare,
  validate, troubleshoot, or complete it.

## Backend-Only Secrets

- SMTP credentials, database credentials, Django secrets, Stripe secret keys,
  webhook secrets, Google OAuth client secrets, OAuth refresh/access tokens,
  AWS secret keys, private API keys, and equivalent credentials must exist only
  in the Django backend environment or an approved deployment secret manager.
- Angular and Flutter are public/recoverable artifacts. They must never contain
  backend secrets in environment files, source code, JavaScript, Dart defines,
  assets, source maps, logs, or compiled builds.
- Frontend/mobile code may contain only intentionally public configuration such
  as the backend HTTPS URL or an explicitly publishable provider key.
- Sensitive provider operations must run through authenticated backend
  endpoints. Backend API responses must never return secret configuration.

## Adding Environment Variables

When a feature requires a new environment variable, agents must update the
backend loader, validation, `backend/.env.example`, and relevant documentation
without touching the real environment file.

For every new variable, tell the user:

1. The exact variable name.
2. Whether it is secret or non-secret.
3. The provider and exact credential/value type.
4. A placeholder-formatted example.
5. Required format, scopes, permissions, restrictions, and test/production
   distinction.
6. Where the user must add it manually: `backend/.env` locally or the hosting
   provider's environment/secret dashboard in production.
7. Whether the backend must be restarted or redeployed.

Application code must fail safely when required production configuration is
missing and must never use a real credential as a source-code fallback.

## Git and Delivery Safety

- Real environment files must remain ignored and untracked.
- Before staging, committing, or pushing, inspect the candidate filename list
  without reading protected environment files.
- Verify that no environment file, secret, credential, private key, or
  secret-bearing generated log is included.
- Support, meeting, SMTP, calendar, payment, storage, and database production
  values are always entered manually by the user after code delivery.
