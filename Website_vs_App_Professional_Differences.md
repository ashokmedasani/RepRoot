# Website vs. App — Professional Side: Differences Log

Compared the live local website (`localhost:4300`, logged in as `premium_usage_demo`) against the Flutter app running on the Pixel 10 Pro emulator, page by page. This covers Dashboard, Clients list, and the Client Detail page's header + Workspace tab before the local backend went offline and stopped the pass (see **Blocker** at the bottom).

## Fixed during this pass

**"Total Entries" showed the wrong number.** On the client detail page's Client Activity row, mobile showed the client's all-time entry count (193). The website's "Total Entries" tile is actually scoped to the current month (its own "This month" caption confirms it) — same client should show a small number, not 193. Mobile was reading `_entries.length` instead of filtering to the current month. Fixed to match the website's `entriesThisMonth` logic exactly.

**"Show less" left dead space on the client header.** Reported separately — fixed by adding `shrinkWrap: true` to the header's scroll view (see earlier message). Confirmed via code review, not yet re-verified live because of the backend outage below.

## Real gaps (not yet built — flagging for a decision)

**Clients list is missing its KPI row.** The website's Clients page shows 4 stat cards above the table: Total Clients, Active Clients, Pending Passwords, and Groups. The mobile Clients page has no equivalent — it goes straight from the header into the search bar. Worth adding if you want parity.

**Client Detail → Workspace is missing "Recent Entries."** The website shows the client's 3 most recent tracking entries (template name + date, tap to open) directly below the Client Activity KPI row. Mobile's Workspace tab has the KPI row and then jumps straight to Professional Notes — no recent-entries list at all.

**Client Activity KPI tiles are missing their secondary captions.** The website's 4 tiles each have a small second line: "This month" (Total Entries), the template name (Last Entry), "Keep it up!" / "No current streak" (Streak), "This month" (Completion). Mobile's `CompactStat` only shows icon + value + label — no room for that second line in the current design.

## Confirmed intentional (already decided earlier this session — not bugs)

These look like divergences from the website but were explicit decisions you made earlier, so flagging them here just so they're accounted for, not re-flagging as problems:

- **Templates is its own tab on mobile** (Workspace / **Templates** / Chat / Payments / Actions). The website keeps template-assignment inside the single "Client Workspace" tab — mobile split it out on your instruction.
- **"Joined date" lives only in "Show all details" on mobile.** The website always shows Joined Date in the main info grid (5 fields: Email, Username, Group, Status, Joined Date). You asked to drop it from mobile's always-visible grid — done on purpose.
- **Clients page subtitle removed on mobile.** The website's Clients page has a full sentence under the title ("Review every approved client, open profiles, and continue conversations."). You asked for mobile's to be trimmed to just "Clients" — done on purpose.

## Minor visual differences (not necessarily worth changing)

- Website's info-grid fields (Email/Username/Group/etc.) render inside light-blue tinted boxes; mobile renders them as plain stacked label/value text with no box.
- Website's "Edit Profile" is a bordered button; mobile is a small text link (reasonable given mobile's tighter header).
- Website's default client avatar is the RepRoot leaf logo; mobile shows initials in a colored circle instead.
- Website's "Show all details" link says how many more fields there are ("4 more"); mobile's doesn't include a count.

## Blocker — local backend went offline mid-comparison

Reloading `professional/clients/88` directly (to check the Chat/Payments/Actions tabs) hit the website's own error page: **"We cannot reach the service" / Offline**, and stayed there after two retries. No app-side console errors — this points to the local Django backend having stopped or become unreachable, not a website bug. That's why the comparison stops here; Chat, Payments, Actions, Forms & Groups vs. Manage, Templates, Schedule, and Settings/Profile are still unchecked.

Once your backend is back up, let me know and I'll pick the comparison back up from Chat/Payments/Actions and then the rest of the app.
