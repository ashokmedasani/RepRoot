# Mobile information density — diagnosis and plan

**Date:** 6 August 2026
**Scope:** Professional side, Flutter app
**Trigger:** Pages feel overloaded; content misaligns; the chat window is unusably small.

---

## 1. The one-sentence diagnosis

The app was ported from the website **screen-for-screen**, but a phone has roughly a quarter of the vertical space and none of the horizontal space — so layout that costs the website nothing (a persistent identity panel *beside* the content) becomes a permanent tax on the phone, where it sits *above* the content and steals from every tab.

This is my doing — the parity work deliberately mirrored the web page structure. It was the right call for *features*, and the wrong call for *navigation*.

---

## 2. Why the chat box is small — the actual arithmetic

On the client page, the chat tab is at the bottom of a stack of fixed chrome. On a typical ~760pt phone viewport:

| Element | Cost |
|---|---|
| System/browser chrome + AppBar | ~56 |
| Client header card (76pt avatar, name, Edit Profile, 4-field info grid) | ~260 |
| Detail tab bar (5 tabs) + spacing | ~52 |
| App bottom nav shell | ~64 |
| Chat composer | ~64 |
| **Left for actual messages** | **~264pt ≈ 3 bubbles** |

**Two-thirds of the screen is chrome.** No amount of restyling fixes that — it's structural. The chat isn't small because of padding or font size; it's small because five other things were promised the same pixels.

### The worst case: the Payments tab

Open a client → Payments and you are looking at **three stacked levels of tab navigation** at once:

```
App bottom nav        Dashboard · Clients · Manage · Schedule · More   (5)
Client detail tabs    Workspace · Templates · Chat · Payments · Actions (5)
Payments sub-tabs     Summary · Methods · Requests · Transactions · Activity (5)
```

Three tab bars is one more than any mobile UI should ever show. That alone explains "too much information, badly aligned" better than any individual page does.

---

## 3. The principle to design against

> **On a phone, vertical space is the scarcest resource. Anything permanently on screen must earn its place on *every* screen it appears on.**

A corollary that resolves most of the specific complaints:

> **Feature parity ≠ layout parity.** The phone should let a professional do everything the website does — it must not do it in the same *shape*.

---

## 4. The plan, in priority order

Ordered by impact ÷ effort. Each item is independent; you can stop at any point.

### P1 — Chat becomes its own full-screen route ⭐ biggest win

**Change:** `/professional/tabs/clients/:clientId/chat` as a real page. Reached by tapping "Chat" on the client page. Own AppBar showing the client's name and avatar (small), no detail tab bar, no header card.

**Gain:** messages go from ~264pt to ~620pt — **more than double**, roughly 3 bubbles to 8–9.

**Why it's also correct, not just bigger:** a conversation is a *destination*, not a facet of a record. Every messaging app on earth gives chat the full viewport. It also fixes the keyboard problem: right now the on-screen keyboard covers most of an already-tiny message list.

**Effort:** low. The chat widget already exists; it moves into a route and drops its parent chrome.

**Risk:** low. No API changes; polling logic moves with it.

---

### P2 — Collapse the client header

**Change:** the header card stays expanded only on the Workspace tab. Elsewhere it collapses to a 56pt bar: small avatar, name, status pill. Use a `SliverAppBar` so it also collapses on scroll.

**Gain:** ~200pt back on Templates, Payments, and Actions.

**Why:** identity context is useful when you're reading someone's activity. It is dead weight when you're reviewing a payment request — you already know who you tapped.

**Effort:** medium — the header is currently a `Flexible` + shrink-wrapped `ListView` (there's a comment in the file explaining a past bug with exactly this). Moving to slivers removes that fragility.

---

### P3 — Cut five detail tabs to three

**Change:**

| Now | Becomes |
|---|---|
| Workspace | Workspace |
| Templates | Templates |
| Chat | → P1 route, entry point in the header |
| Payments | → own route (it already has 5 sub-tabs; it deserves a page) |
| Actions | → AppBar overflow menu (⋮) |

Leaves **Workspace · Templates**, which arguably needs no tab bar at all.

**Why Actions isn't a tab:** it's a list of one-off destructive/admin operations — deactivate, reset password, export, delete, grant portal access. Nobody browses to it. That is the definition of an overflow menu, and it's costing a fifth of the tab bar.

**Gain:** removes a whole navigation level; tab labels stop truncating.

---

### P4 — Fix the alignment properly

Two real defects, not taste:

1. **The info grid** uses a `Wrap` with a computed cell width. `Wrap` aligns items by their *top* edge within a run, so when one field's value wraps to two lines the neighbouring cell's label no longer lines up. Replace with a 2-column layout with a shared baseline, or a single-column definition list (label left, value right) — which on a 390pt-wide phone is honestly more legible than two columns.

2. **KPI tile labels** wrap to two lines at four-across ("Pending Passwords", "Awaiting Review"), so tiles in a row end up different heights. I already forced equal heights via `IntrinsicHeight`, but the real fix is **three tiles per row, not four**, or shorter labels.

---

### P5 — Progressive disclosure as a habit

**Change:** each page shows a *summary* by default and expands on demand. The Workspace tab currently renders 8 sections unconditionally.

Rules worth adopting:
- Never render an empty section — collapse to nothing, not to an empty state.
- Long lists cap at 3 with "View all (24)".
- Anything only needed occasionally goes behind a sheet.

---

## 5. What I'd deliberately *not* do

- **Don't shrink fonts or padding.** You said the premium feel is landing — that came from the generous spacing. Fixing density by tightening it would trade the thing that's working for the thing that isn't. The fix is *fewer things per screen*, not *smaller things*.
- **Don't remove features.** Everything stays reachable; only the route to it changes.
- **Don't add a tablet/responsive layout yet.** Solve the phone first.

---

## 6. Suggested sequence

1. **P1 (chat route)** — biggest visible improvement, lowest risk. Do this alone and reassess.
2. **P3 (tab reduction)** — structural, unlocks P2.
3. **P2 (collapsing header)** — the fiddliest; worth doing after the tab structure settles.
4. **P4 (alignment)** — cosmetic but cheap.
5. **P5 (disclosure)** — ongoing discipline rather than a task.

Each is independently shippable and independently revertable.
