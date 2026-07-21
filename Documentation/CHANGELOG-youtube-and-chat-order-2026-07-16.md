# In-app YouTube playback + unread chats first (2026-07-16)

Two requests, both Flutter-side (`mobile_flutter/`), one with a small additive backend
change. The Ionic app (`mobile/`) is retired and was not touched.

---

## 1. YouTube videos play inside the app

**Before.** Every trainer resource — PDF, image, video — went out through
`launchUrl(..., LaunchMode.externalApplication)`, so tapping a video threw the client out
of CoachFlow and into the YouTube app or a browser tab. The backend has always insisted a
video reference *be* a YouTube link, with the validation message saying why: *"Videos must
be YouTube links so they can be streamed in-app."* The app just never held up its end.

**After.** YouTube links open a player screen inside the app. Everything else still goes to
the system handler exactly as before.

### Files

| File | Role |
|---|---|
| `lib/shared/video/youtube_link.dart` | Decides whether a URL is a playable YouTube link and extracts the video id |
| `lib/shared/video/youtube_player_page.dart` | The in-app player screen |
| `lib/shared/video/open_resource.dart` | One entry point: YouTube in-app, everything else out |
| `test/shared/youtube_link_test.dart` | 13 tests, mostly about what the parser must *refuse* |

`open_resource.dart` also collapses three near-identical `_open` methods (client Programs,
client Trainer profile, trainer References) that had each grown their own copy of the same
launch-and-toast logic.

### Following YouTube's terms

This embeds **YouTube's own IFrame player** (`youtube_player_iframe` wraps the official
IFrame Player API). It does not resolve stream URLs. That distinction is the whole
compliance story:

- **Stream extraction is out.** `youtube_explode_dart` and similar are the popular way to
  get a video into a native Flutter `VideoPlayer`, and they break the Terms of Service —
  playback is only licensed through the official player. They also break whenever YouTube
  rotates its signature cipher.
- **Controls, branding and the fullscreen button stay on.** The terms forbid hiding or
  obscuring the player's UI. Ads are served by the player; nothing here may cover, skip or
  strip them, so `showControls` and `showVideoAnnotations` are left at their defaults
  rather than turned off to make the embed look tidier.
- **No background or audio-only playback.** Audio is never separated from video.
- **Embedding refusals are honoured.** If a video's owner disallows embedding (YouTube
  reports this as 101/150/152), the app says so in plain language and offers a
  "Watch on YouTube" button. That restriction is the owner's to make; the compliant
  response is to hand the viewer over, not to route around it.
- **`privacyEnhancedMode` is on**, so playback is served from youtube-nocookie.com —
  YouTube's own privacy-preserving embed. A client watching their trainer's workout
  reference shouldn't collect ad-tracking cookies for it.

### The parser, and why it checks the host first

`youtubeVideoId` verifies the host **before** parsing an id. The package's
`convertUrlToId` treats any 11-character string without `"http"` in it as a bare video id,
so a text note reading `hello world` would come back as a perfectly good "video". The host
check closes that off, and also rejects lookalikes like `youtube.com.evil.example`.

The accepted hosts are deliberately the same four as `YOUTUBE_HOSTS` in
`backend/accounts/serializers.py`. **If that list ever grows, grow both** —
`music.youtube.com` is the obvious candidate, and today the backend rejects it, so the app
refuses it too rather than promising playback the backend won't allow.

---

## 2. Clients with unread messages sort to the top

**Request.** Clients who message the trainer should show first, ordered by most recent
message.

**Scope decision.** Only *unread* chats float; the rest of the roster stays alphabetical.
The Clients tab is a list of ~100 people that a trainer searches by name, so ordering all
of it by chat activity — inbox style — would shuffle familiar rows for no reason. Reading a
chat drops it out of the unread set, and the row settles back into place on the next poll.
This was chosen over full inbox ordering with the user.

### Backend — `TrainerChatUnreadView` (`backend/accounts/views.py`)

`GET /api/accounts/trainer/chat/unread/` gains a `last_unread_at` map alongside the
existing `by_client`:

```json
{
  "unread_count": 3,
  "by_client":      { "63": 2, "71": 1 },
  "last_unread_at": { "63": "2026-07-16T09:41:12.004Z", "71": "2026-07-16T08:02:55.771Z" }
}
```

Purely additive — existing consumers (the web portal, and the Ionic app while it lasts)
ignore it. It's one extra `Max('created_at')` annotation on the query that was already
running, and `ChatMessage` is already indexed on `(client, created_at)`, so it costs
nothing.

It's the newest **unread** message, not the newest message in the thread, deliberately: the
trainer's own reply shouldn't push a chat up its own list, and once they read the thread
the client drops out of the response entirely.

### Flutter

- `lib/core/api/chat_api.dart` — `TrainerUnreadSummary` gains `lastUnreadAt`. An
  unparseable timestamp drops that client from the ordering rather than taking the list
  down with it.
- `lib/features/trainer/trainer_clients_page.dart` — sorts unread first, newest message
  first, then by name.

The name comparison is the tiebreak rather than returning `0`, because **`List.sort` in
Dart is not stable** — returning `0` would let it shuffle the alphabetical order the load
step established.

### Not done

The **web portal's** clients list shows the same unread badges and would get the same
benefit; the backend field it needs is already live. Left alone because this round was
scoped to Flutter.
