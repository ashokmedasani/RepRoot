# Plan-Limit Lock System — Design Plan (Pending Validation)

**Status:** Planning only — no code changed yet. This document is the output of a full design discussion; it needs your sign-off before any implementation begins.

---

## 1. Why this exists

Today, when a professional downgrades (or lapses) from Pro/Premium back to Free, nothing happens to their groups, lead forms, templates, resources, or categories beyond the new tier's limits — they just sit there, fully usable, forever, only blocked from *adding new ones*. The only thing that has real teeth today is storage: crossing the byte quota triggers a 14-day grace period, then an account freeze, then a 14-day recycle bin, then permanent deletion.

This plan adds an equivalent (but much gentler) enforcement layer for the five *counted* things — groups, lead forms, templates, resources, categories — without ever risking a professional's actual content or client relationships.

---

## 2. What we found while auditing the current code (read this before the new plan — one item below is a direct contradiction)

An audit of the live Plan & Billing UI and cancellation flow turned up a few things worth fixing regardless of this new plan, and one that **must** change as part of it:

- **Contradicts the new plan — must change.** The current cancellation confirm-dialog says: *"At the end of the billing period, excess forms, unused groups, unused templates, resources, and empty categories **may be deleted**. Client records are preserved."* — and requires the professional to type `DELETE EXCESS PLAN DATA` to confirm. The backend genuinely does delete this data today (`cleanup_excess_non_client_resources` in `subscription_cancellation.py`). This is the exact opposite of what we designed: nothing counted should ever be deleted on downgrade, only locked. **This entire flow — copy, confirmation phrase, and the deletion function backing it — needs to be replaced with the lock system**, not left alongside it.
- **Correction to something I told you earlier.** I said plan numbers are single-sourced from `settings.py` with nothing hardcoded elsewhere — that's true for the main plan comparison grid, but **not fully true**: `professional-account-settings.component.ts` has a hardcoded prose blurb (`upgradeTierCopy`) describing Pro/Premium in plain English ("1 GB included storage...", "5 GB storage, 25 groups, 250 resources..."). It happens to match `settings.py` right now, but it's a plain string, not pulled from the API — so if you ever change a number in `settings.py` (like the storage discussion earlier), this blurb will silently go stale and start lying to users. This needs to be fixed to interpolate from the live plan data, regardless of the lock system work.
- **Dead code found.** A whole "plan summary" block in the same component is wrapped in `hidden` and unreachable, and its "Update Plan" modal has become orphaned as a result (the only button that opened it lives inside the hidden block). Worth deleting as cleanup.
- **Not shown anywhere today:** `subcategories_per_category` and `client_data_retention_days`, even though they're real plan limits. Given the "everything should be visible" principle from this whole discussion, these should probably be added to the plan comparison display.
- **Minor:** a code comment in `settings.py` claims Premium storage is "10x Pro" — it's actually 5x (5GB vs 1GB). Just a stale comment, no functional impact.
- **Confirmed clean:** the Data Usage page, the grace-period messaging (consistently 14 days everywhere), and the main plan-comparison grid are all already correctly data-driven with no drift risk.
- **Confirmed reusable:** the client suspend/reactivate toggle (`ClientAccessStatusView`) is a simple, already-working `is_active` flip with UI copy that already says *"Reversible — none of these touch the client's data"* — exactly what the new plan needs for auto-suspending clients in a locked group.
- **Confirmed dead/unused:** `feature_access.py`'s `can_manage_*`/`check_feature_limits` functions are defined but never called anywhere — the real enforcement today is `plan_limit()` calls directly in `views.py`. Worth deciding whether the new lock system revives this module properly or replaces it outright, rather than leaving two unused parallel systems.

---

## 3. The new design

### 3.1 Scope: the five counted things
Groups, lead forms, templates, resources, categories. (Clients themselves are never counted or limited — that stays as-is.)

### 3.2 Ranking and locking
Each item is ranked, by default in creation order (oldest first). Whichever items fall within the current tier's allowed count stay **active**; everything beyond that count is **locked**.

- **Categories lock as a whole tier first.** If a category is beyond the category limit, it locks — and *every resource inside it locks too, regardless of that resource's own individual count-rank*. Resources are only evaluated against the resource-count limit within categories that are themselves still active.
- **A locked group suspends every client inside it** — reusing the existing `is_active` toggle, not deleting anything. Clients keep all their data; they just can't log in until the group unlocks.
- **A locked resource that's shared with any client via a template assignment** shows the professional exactly how many clients are affected, with a manual "unassign" action per client and a bulk "unassign all" button.

### 3.3 Visibility
- **Professional side:** locked items show a lock icon and a clear reason. Their *content* does not render while locked (no preview of a locked resource, no client roster of a locked group) — just enough identifying info (name/title) to know what it is and why it's locked.
- **Client side:** locked items simply don't exist. No error, no "this is unavailable" message — they're invisible, exactly as if never created.

### 3.4 Reordering
Full reordering freedom at any time **before the current paid subscription period actually ends** — there is no separate grace-period window for this, it's just whatever time remains on the clock. The moment the paid period ends, if still over the new tier's limits, the freeze is instant, based on whatever order existed at that exact moment.

After the freeze:
- No reordering, and locked items cannot be directly manipulated.
- Deleting an active (unlocked) item automatically promotes the next-ranked locked item into the freed slot — pure rank order, no professional choice involved.
- Upgrading the plan unlocks everything at once, automatically.

### 3.5 Retention — locked data is never deleted on a timer
This is a deliberate departure from the existing storage-overage pipeline. Locked groups/categories/templates/resources/lead-forms are:
- Held indefinitely, hidden from the professional's active view and counts.
- Restored automatically the moment the plan unlocks (upgrade, or a freed slot via deletion).
- Never subject to any recycle-bin-then-delete timer — that mechanism stays exactly as it is today, but reserved exclusively for genuine account abandonment (unpaid **and** unengaged **and** over the storage byte quota for the existing 30-day-frozen / 14-day-recycled window). This is a fundamentally different, much harsher scenario than a professional simply having more groups than their current tier allows.

Rationale: this is a professional's own client relationships and created content (their groups, their resources, their forms) — not disposable clutter. Deleting any of it risks a professional returning after an upgrade to find their own work gone, which is a trust problem, not a storage-savings win.

### 3.6 Storage cost handling for locked heavy files
Since "never delete" doesn't mean "cost is now zero," locked resources containing PDFs/images (not `text_note` resources, which cost nothing meaningful to hold) get moved to a cheaper/cold storage tier the instant they lock — a pure infrastructure change, invisible to the professional, no data loss, and it reverses automatically on unlock. Compression of locked heavy files is a possible second-phase optimization, held until there's real cost data to justify it.

### 3.7 Interaction with the existing storage-quota system
Locked items' bytes must be **excluded** from the live storage-quota calculation (`calculate_professional_data_usage`) — otherwise a professional could get storage-frozen partly because of data that's already locked and inaccessible to them, which would be double jeopardy. The existing grace → freeze → recycle → delete pipeline keeps applying, unmodified, but only against bytes that are genuinely still active and in use.

### 3.8 Explicit warning copy required at cancellation
The cancellation flow needs distinct, plainly-worded rules shown up front — not just a generic warning. At minimum:
- How many groups/templates/resources/categories/lead-forms would lock, by name where practical.
- The category cascade rule stated on its own: *"N of your categories will lock, and every resource inside those categories will lock too, regardless of how many resources they contain."*
- How many clients (and in which groups) would lose portal access — replacing today's blanket "client records are preserved" with a real, specific number (the current `downgrade_assessment` response already has a `clients_preserved: true` field that's never surfaced with real numbers — this needs to become concrete).
- Confirmation that nothing is deleted — replacing the current "may be deleted" / `DELETE EXCESS PLAN DATA` copy entirely.

---

## 4. Data Usage page: MB/GB for paid tiers

Independent of everything above, and lower-risk/effort:
- **Free tier:** unchanged — percentage of quota and record count per section, exactly as today.
- **Pro/Premium tiers:** add an additional column per section showing actual consumption in MB or GB (unit switches sensibly as the number grows), alongside the existing percentage — so a paying professional can see both "you're at 12%" and "that's 340MB" and identify which section is actually driving usage.

This can be built and shipped independently of the lock system whenever convenient.

---

## 5. Explicitly deferred / out of scope for now

- **Group-to-group client transfer.** Confirmed technically feasible — `registration_answers` is a schemaless JSON field and `group` is a freely reassignable foreign key, so nothing else in the system (templates, payments, chat, progress entries) is actually scoped to the group. But it's its own UI flow (professional fills the target group's registration form on the client's behalf) and its own branch — not part of this plan.
- **Subscription timing delay + pre-downgrade warnings (Phase 3, last priority).** Staying on the current paid tier until the billing period's actual end date (`plan_renews_at`), plus proactive warnings before that date, rather than downgrading immediately on cancellation. Held until you've finished testing how the current immediate-downgrade behavior actually behaves in practice.

---

## 6. Open implementation questions (not blocking, just noted for whoever builds this)

- **Evaluation order matters and must be explicit in the build:** lock categories first against the category-count limit, *then* rank resources only within categories that survived — not all resources against a flat count regardless of category state.
- **Compute-live vs. stored state:** whether locked/unlocked status gets recalculated on every read, or stored and recalculated only on specific trigger events (reorder, delete, plan change, upgrade) — a real implementation choice with performance and consistency trade-offs, not yet decided.
- **feature_access.py's fate:** revive it as the real enforcement layer for the new lock system, or replace it — right now it's unused dead code sitting alongside the actual enforcement path (`plan_limit()` calls in `views.py`).

---

## 7. Suggested build order

1. Fix the two "found while auditing" items that are cheap and independent: the hardcoded `upgradeTierCopy` blurb, and the dead hidden plan-summary block/orphaned modal.
2. Build the core lock system (§3.1–3.7) — this is the bulk of the work and everything else depends on it.
3. Rewrite the cancellation flow's warning copy and confirmation step (§3.8) to match the new no-deletion reality.
4. Ship the Data Usage MB/GB display for paid tiers (§4) — independent, can happen in parallel with steps 2–3.
5. Hold Phase 3 (§5, subscription timing) until your own testing is done.
6. Hold group-to-group transfer (§5) for a separate future branch.
