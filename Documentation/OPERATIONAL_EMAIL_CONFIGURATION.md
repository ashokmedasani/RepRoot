# Operational Email Configuration

RepRoot does not keep production mailbox addresses or SMTP credentials in
source code. Configure these values manually in the backend deployment
environment. Do not commit the real values.

| Variable | Secret | Purpose | Value supplied by |
| --- | --- | --- | --- |
| `EMAIL_HOST_USER` | Treat as private | SMTP authentication username or mailbox | SMTP provider |
| `EMAIL_HOST_PASSWORD` | Yes | SMTP password or application password | SMTP provider |
| `DEFAULT_FROM_EMAIL` | No | Default transactional sender identity | A sender verified by the SMTP provider |
| `SUPPORT_EMAIL` | No | Monitored support and cancellation-escalation inbox | Your support mailbox |
| `MEETING_FROM_EMAIL` | No | Meeting decisions, follow-ups, and calendar invitations | A sender verified by the SMTP provider |
| `GOOGLE_CALENDAR_ID` | Treat as private | Calendar used for synchronized meetings | Google Calendar |

Placeholder layout:

```dotenv
EMAIL_HOST_USER=<smtp-authentication-username>
EMAIL_HOST_PASSWORD=<smtp-password-or-app-password>
DEFAULT_FROM_EMAIL=RepRoot <notifications@your-domain.example>
SUPPORT_EMAIL=support@your-domain.example
MEETING_FROM_EMAIL=RepRoot Meetings <meetings@your-domain.example>
GOOGLE_CALENDAR_ID=<calendar-email-or-calendar-id>
```

The website exposes the support address publicly. Its production build reads
the same non-secret `SUPPORT_EMAIL` deployment variable and writes the runtime
configuration automatically. The resulting public configuration has this
layout:

```js
window.APP_CONFIG = {
  apiBaseUrl: "https://api.your-domain.example",
  supportEmail: "support@your-domain.example"
};
```

Restart or redeploy the backend after changing backend variables. Rebuild or
redeploy the website after changing its runtime configuration.

Production scheduling must also run this Django command at least once daily so
cancelled memberships downgrade even when the user does not open the billing
screen:

```text
python manage.py process_subscription_cancellations
```
