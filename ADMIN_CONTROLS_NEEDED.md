# Admin Controls Needed — Plan-Limit Lock System

This is a documentation-only note, written as instructed while building the plan-limit lock
system (see `DOWNGRADE_LOCK_SYSTEM_PLAN.md`). No admin-portal code has been changed as part of
this — everything below is a list of admin-facing actions that would be useful once someone
picks up admin-side work, plus where they'd naturally live.

The existing consent-gated support-action infrastructure is the right home for all three:
`accounts.SupportIncident` (a human-reported ticket) + `admin_portal.SupportAccessGrant` (a
time-boxed, consent-approved grant tied to an incident) + `admin_portal.views.
AdminSupportControlledActionView` (the endpoint that actually performs an action once a valid
grant + reason are present, and logs it via `admin_portal.audit.record_admin_action`). That view
already supports two actions (`end_sessions`, `unlock_account`) gated the same way these three
would need to be — extending its `if action == ...` chain is the natural, minimal-footprint way
to add them, rather than building new plumbing.

## 1. Temporary unfreeze for login

**Why it's needed:** `accounts/account_lifecycle.py`'s `check_and_lock_overages()` sets
`ProfessionalProfile.is_locked = True` and deletes the professional's auth tokens, but does not
set `User.is_active = False`. Meanwhile `ProfessionalLoginSerializer.validate()` now correctly
rejects login for any profile with `is_locked=True` (this was a real bug, fixed as part of this
work — previously a frozen professional could still log back in and use the app). The
consequence: once frozen, a professional genuinely cannot log in at all, even to see why, pay,
or ask for help. Support currently has no way to get them back in temporarily to sort out billing
without fully reactivating the account (which would undo the intentional freeze).

**Suggested action:** `temporary_unfreeze_for_login`, added to `AdminSupportControlledActionView`.
Sets `is_locked = False` for a bounded window (e.g. tied to the same grant's `expires_at`) without
touching `lock_reason`, `locked_at`, or the underlying overage — so the professional can log in,
see their own Data Usage / Billing page, and act (upgrade, pay, delete data), but a background
job should re-freeze automatically at the grant's expiry if the underlying overage is still
unresolved. This is different from `unlock_account`, which is a full, permanent reactivation.

## 2. Manual recycle-bin move

**Why it's needed:** `account_lifecycle.check_and_delete_data()` automatically moves a
professional frozen for `REPROOT_DATA_DELETION_DAYS` (30 days) into the recycle bin, ahead of a
14-day purge window. That's the automatic path for genuine abandonment. Support sometimes needs
to do this manually and sooner — e.g. a professional explicitly asks to be moved into the
recycle-bin/cancellation path outside the normal timer, or a compliance/support decision requires
it. There's currently no admin-triggered equivalent of `move_professional_to_recycle` outside the
daily batch job.

**Suggested action:** `move_to_recycle_now`, calling the existing
`account_lifecycle.move_professional_to_recycle(profile)` directly instead of waiting for the
scheduled job to reach that profile. Should require the same consent-grant + reason pattern as
the other actions here, since it starts the clock on a real deletion window.

## 3. Grace-period reset

**Why it's needed:** downgrade grace periods (`REPROOT_DOWNGRADE_GRACE_PERIOD_DAYS`, 14 days) and
the storage-overage grace window are both fixed, professional-triggered clocks
(`ProfessionalProfile.grace_period_ends_at`). There's no discretionary admin override today —
if a professional has a good-faith reason for needing more time (payment method issue on their
end, a support ticket that took days to resolve, etc.), support can't currently extend or reset
the clock; the only paths are "wait it out" or the professional upgrading/paying.

**Suggested action:** `reset_grace_period`, setting a new `grace_period_ends_at` (e.g. +14 days
from the action's timestamp, or an admin-specified date) on the professional's profile. Given
this is the one action here that could plausibly be repeated indefinitely to indefinitely stall
an overage, it's worth deciding up front whether to cap how many times this can be used per
professional (a raw count on `ProfessionalProfile`, or derived from
`record_admin_action`'s audit log for that professional) — flagged here as an open question, not
a recommendation either way.

## Not included here

Nothing about the plan-limit lock system's core behavior (which groups/lead forms/templates/
resources/categories lock, cascade rules, reordering, cold storage, the cancellation flow) needs
an admin control — it's fully automatic and self-service by design, and none of the above should
be read as suggesting otherwise. These three are specifically the "someone needs to intervene
outside the normal automatic flow" cases that came up while building it.
