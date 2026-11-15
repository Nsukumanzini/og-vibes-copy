# OG Vibes authentication email templates

Paste these templates into the hosted Supabase dashboard under **Authentication → Emails → Email Templates**. Brevo delivers the messages through SMTP; Supabase still creates the secure authentication links.

| Supabase template | Subject | File |
| --- | --- | --- |
| Confirm signup | Confirm your OG Vibes account | `../student-confirmation-email-template.html` |
| Reset password | Reset your OG Vibes password | `recovery.html` |
| Invite user | You have been invited to OG Vibes | `invite.html` |
| Change email address | Confirm your new OG Vibes email address | `email-change.html` |
| Magic link | Your secure OG Vibes sign-in link | `magic-link.html` |
| Reauthentication | Your OG Vibes security verification code | `reauthentication.html` |

Before testing, confirm the SMTP sender is `OG Vibes <no-reply@auth.ogvibes.co.za>`, disable Brevo click tracking for authentication messages, and keep `https://student.ogvibes.co.za/**` in the allowed redirect URLs.

The signup template intentionally uses the six-digit `{{ .Token }}` value so email-provider click tracking cannot rewrite or consume the confirmation action. Recovery, invitation and email-change templates still use `{{ .ConfirmationURL }}`, while reauthentication uses `{{ .Token }}`. Never replace these values with a static URL or code.
