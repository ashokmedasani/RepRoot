# Google Calendar and Meet Production Setup

RepRoot schedules meetings internally and can optionally mirror them to one
Google Calendar. When Google Calendar is enabled, each new 15- or 30-minute
appointment receives a unique Google Meet link. If Google is unavailable,
RepRoot preserves the appointment and creates an internal fallback video room.

Real credentials are user-managed. Agents must never open or edit the real
environment file.

## 1. Create the Google OAuth application

1. Open Google Cloud Console and create or select the production project.
2. Enable **Google Calendar API**.
3. Configure the OAuth consent screen for the account that owns the RepRoot
   business calendar.
4. Create an **OAuth 2.0 Client ID**.
5. Select **Web application**.
6. Complete an authorization flow requesting Calendar event access and offline
   access. Retain the resulting refresh token in the deployment secret store.
7. Use the narrowest scopes that satisfy event creation and updates. RepRoot
   requires permission to create, update, cancel, and inspect its calendar
   events.

For a single company calendar, authorize the Google account that owns that
calendar. Do not use an API key: private events and Meet creation require OAuth.

## 2. Add deployment environment values manually

Add the following fields to the real backend environment configuration or the
deployment provider's secret/settings screen:

```env
GOOGLE_CALENDAR_ENABLED=True
GOOGLE_CALENDAR_CLIENT_ID=<google-oauth-web-client-id>
GOOGLE_CALENDAR_CLIENT_SECRET=<google-oauth-web-client-secret>
GOOGLE_CALENDAR_REFRESH_TOKEN=<authorized-calendar-refresh-token>
GOOGLE_CALENDAR_ID=<calendar-email-or-calendar-id>
GOOGLE_CALENDAR_TIMEOUT_SECONDS=15
```

| Variable | Secret | Source |
| --- | --- | --- |
| `GOOGLE_CALENDAR_ENABLED` | No | Set to `True` after all other values are present |
| `GOOGLE_CALENDAR_CLIENT_ID` | Treat as private | Google Cloud OAuth client |
| `GOOGLE_CALENDAR_CLIENT_SECRET` | Yes | Google Cloud OAuth client |
| `GOOGLE_CALENDAR_REFRESH_TOKEN` | Yes | Offline OAuth authorization flow |
| `GOOGLE_CALENDAR_ID` | Treat as private | Google Calendar settings; often the calendar email |
| `GOOGLE_CALENDAR_TIMEOUT_SECONDS` | No | Request timeout; `15` is the recommended starting value |

Never commit the real values. Restart or redeploy the backend after adding or
changing them.

## 3. Apply the database migration

```text
python manage.py migrate
```

The migration adds external-calendar identifiers and synchronization status to
internal meetings. RepRoot continues to own booking availability, status, and
history.

## 4. Meeting behavior

- Professionals choose a 15- or 30-minute video meeting in the mobile app.
- RepRoot stores the appointment internally in UTC.
- When Google is configured, RepRoot creates a Calendar event, unique Meet
  room, and attendee invitation.
- Rescheduling updates both RepRoot and Google Calendar.
- Cancellation removes the Google event and notifies attendees.
- If Google synchronization fails, the internal appointment remains valid and
  uses a fallback video room.
- Clients can choose **Add to calendar** in the mobile app. RepRoot exports an
  `.ics` invitation that can be opened by Apple Calendar, Google Calendar,
  Outlook, or another installed calendar application.

## 5. International meetings

Keep each professional's scheduling time zone as an IANA identifier, such as
`Asia/Kolkata`, `America/New_York`, or `Europe/London`. RepRoot stores the
appointment timestamps in UTC; Google Calendar and the device calendar display
them in each attendee's local time and account for daylight-saving changes.
