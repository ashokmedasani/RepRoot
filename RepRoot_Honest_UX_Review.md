# RepRoot — Honest UX Review
*A full walkthrough of the app, page by page, done the way a critic would do it: use the thing, notice what snags, say so plainly.*

Tested live against your local dev servers (frontend :4300, backend :8000) using a fresh professional account and two fresh client accounts.

---

## Bottom line up front

The bones of this app are good. Templates, Notifications, Security, and the new self-hosted Schedule builder are genuinely well-designed — clear copy, sensible defaults, good empty states. But there's one **critical, reproducible bug** (a password-reset action that freezes the browser tab indefinitely), and a handful of **real, recurring UX problems** that show up in more than one place, which is usually a sign of a pattern worth fixing once rather than patching per-page. Your specific complaint — the "Actions" tab on a client's profile — was a fair catch, and there's more wrong with it than just ordering.

---

## 🔴 Critical

**1. Password reset hangs the browser tab indefinitely.**
Client Profile → Actions (or the "Password" button on the header) → Reset Password → confirm "Reset & Send" → the tab froze completely for 2+ minutes and never recovered (confirmed via repeated screenshot/script-injection timeouts). The rest of the app kept working fine in a separate tab, so this isn't a global crash — it's isolated to that one request. The likely cause: your `.env` has `EMAIL_HOST=smtp.gmail.com` with placeholder credentials (`your-email@gmail.com` / `your-app-password`), and the email send appears to happen synchronously inside the request. If the SMTP handshake stalls or times out slowly, the whole request — and the tab waiting on it — hangs with no error, no timeout, no way out for the user except closing the tab.

This isn't just a "reset password" problem. Anything that emails credentials — password reset, "create client with portal access → email login details," meeting invites — likely shares this code path and is at risk of the same freeze. I'd treat this as the top priority. Two independent fixes worth doing regardless of root cause: (a) set an explicit `EMAIL_TIMEOUT` so a bad SMTP connection fails fast instead of hanging, and (b) don't let email sending block the HTTP response — the account/reset action should complete and show success even if the email send is slow or fails.

---

## 🟠 Real bugs and inconsistencies (repeat patterns)

**2. Error and success banners appear at the top of long forms, with no scroll-to-error, toast, or redirect.**
This is the most common real problem in the app, and I hit it in two unrelated places: the Add Client form (submitting without a required Phone Number, and again on success) and the Schedule availability builder (typing an invalid start/end time). In both cases the feedback renders at the very top of a long, scrollable page while the button you just clicked is at the bottom. A real user watching the bottom of the screen will see nothing happen and likely click submit again — which for Add Client risks creating duplicate client records. This is worth fixing once as a shared pattern (toast notifications, or auto-scroll to the message) rather than per-form.

**3. The Add Client form doesn't clear or navigate away after a successful submission.** The fields stay populated with what you just submitted, compounding the double-submission risk from #2.

**4. "Reset Password" and "Reset Client" sit next to each other and mean wildly different things.** One sends a new temporary password (harmless, reversible). The other permanently wipes a client's operational history (destructive, irreversible). Same verb, same visual weight, adjacent buttons. I'd rename "Reset Client" to something that doesn't share a root word with "Reset Password" — "Clear Client History" or similar — specifically because they're one misclick apart.

**5. Destructive actions are handled inconsistently.** "Reset Client" is a big inline form sitting directly on the page (current password, type-to-confirm, reason — all exposed at once). "Delete Account" is a plain button with no confirmation step shown. Compare this to the References page, where "Create Category" — a completely benign, non-destructive action — gets a proper modal dialog. The safety net is backwards: the riskier the action, the more casual the UI treatment.

**6. Duplicate entry points for the same action.** The client profile has both a header "Password" button (opens an "Account & Access" modal with its own Reset Password button) and a separate inline "Reset Password" button under the Actions tab. Same result, two different paths, two different visual treatments. Pick one.

**7. Data Usage counter looks wrong.** Settings → Data Usage showed "Client profiles: 0" while the account clearly has an active client. Either the counter isn't wired up to count clients, or it's counting something else — worth a quick look since it's the number backing your plan-usage math.

**8. Suggested Fields duplicate on click.** In the lead form builder, clicking a "+ Field Name" quick-add chip for a field that's already on the form (because it's part of the default set) creates an exact duplicate instead of being disabled or no-op'ing. Reproduced with Phone Number.

**9. Phone Number required/optional mismatch.** The client-creation form enforces Phone Number as required (confirmed: submitting without it throws a 400), but the group registration/lead-form builder labels the same field "Phone – Optional." Whoever is configuring forms will reasonably expect that label to be authoritative. Worth deciding which one is actually true and making the other match.

---

## 🟡 Naming, layout, and polish

**10. The "Actions" tab ordering, specifically (your original complaint).** Top to bottom it's currently: Reset Password → Disable Portal Access → Suspend Account → Reset Client → Delete Account. The severity ordering (mild → destructive) is actually reasonable in principle, but there's no visual grouping to signal the jump — the three mild blue buttons flow directly into an orange destructive box with no section break, and (per #4/#5 above) "Reset Client" is dangerously close in name and position to "Reset Password." My honest read: the ordering isn't the real problem, the *lack of grouping and the confusing pair of names* is. I'd add a subtle divider or heading ("Access controls" / "Irreversible actions") and rename "Reset Client" so it can't be mistaken for the password action above it.

**11. Marketing page CTA labels don't match.** "Launch RepRoot" in the nav and hero vs. "Launch RepRoot" further down — same button, same destination, different text.

**12. Workspace picker avatar mismatch.** At `/portal`, the "Professional" card shows the letter "T" instead of "P." Small, but it's the first thing a returning user sees.

**13. "Create Group" button is green while every other primary action in the app (including "Add Client" on the same page) is blue.** Reads like an unintentional one-off.

**14. Payments tab has a second row of tabs nested inside it** (Summary / Payment Requests / Payment History / Available Payment Methods / Payment Activity), and "Payment History" and "Payment Activity" are close enough in name that I'd expect users to click the wrong one and not notice.

**15. Timezone field in Schedule → Meeting defaults is free text, not a dropdown.** Right now it happily accepts "UTC" as typed text with no validation. A typo here (e.g., "UCT" or a made-up zone name) would silently break slot computation with no warning to the trainer. This should be a constrained select of real IANA timezone names.

**16. Settings has ten tabs in a single horizontal row** (My Account, Security, Plan & Billing, Payment Settings, Notifications, Appearance, Data Usage, Application Guide, Support, About). It fits on a large screen but is one redesign away from wrapping awkwardly or needing horizontal scroll on anything smaller. Consider grouping into two rows or a sidebar.

**17. Username has a hard 10-character maximum at signup**, discovered only after a submit-time validation error rather than inline guidance. If that's intentional, say so before the user types 11 characters.

**18. Availability-confirmation text during signup renders in all caps** ("ASHOKTEST1 IS AVAILABLE.") regardless of the case the user typed. Minor, but reads like a bug rather than a style choice.

**19. Not auto-logged-in after signup** — new users land back on the login page instead of straight into the app. Minor friction, but avoidable.

**20. "This may take around 10–15 minutes" appears twice in a row** during onboarding (profile setup, then lead-form setup), which reads as a much bigger time commitment than the actual flow warrants.

**21. Professional Code has no live availability check**, unlike Username which has a "Verify" button. First attempt at a taken code only fails after submitting the whole multi-field profile form.

**22. Dashboard's "Activity breakdown" chart renders as a flat, blank grid for a brand-new account**, while the sections right below it (Messages, Pending Requests, Client Account Requests) use friendly text-based empty states ("No messages yet," etc.). The chart should either hide itself or show the same kind of friendly empty state until there's real data.

---

## What's actually good, for balance

Templates is genuinely well organized — standard templates to adopt, clear slot counter, sensible empty states. Notifications is the best screen in the app: bulk quick-controls plus a clean per-category matrix. Security is handled correctly, with visible password toggles and the account-deletion path routed through Support instead of a self-serve button. The new self-hosted Schedule builder (multi-block weekly availability, the whole point of ripping out Cal.com) works and is genuinely pleasant to use once you're past the timezone field. The client-side portal is, if anything, a little better designed than the professional dashboard — cleaner empty states, no wasted chart space.

---

## Test credentials

**Professional account** (created earlier this session): username/professional code `ashokt26`, display name "Ashok Kumar." I don't have the original signup password preserved on my end — a context reset happened partway through this review, and it wasn't carried forward. You're still logged in on your end, so this isn't blocking anything right now, but for a clean record I'd suggest either pulling it from earlier in this chat if you scroll up, or running `python manage.py changepassword ashokt26` (adjust to the real username) in your backend terminal to set a password you know.

**Client account** (created and verified working end-to-end, including login):
- Professional code: `ashokt26`
- Username: `rahulverma`
- Password: `RepRootClient!2026`
- I logged in with these, went through the forced first-login password change, and confirmed the dashboard, Meetings, and Templates tabs all load correctly.

(There's also an earlier test client, Priya Sharma / `priyasharma`, but her password is unknown — it was never revealed on screen, and the reset attempt is the one that triggered the critical hang above.)
