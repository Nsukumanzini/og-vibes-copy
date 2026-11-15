# Requested release fixes — 6 September 2026

Scope: only the requests below and the shared data/file contracts needed to make them work. Preserve the theme and Vice Admin permissions. Do not build or deploy applications. Do not delete existing records or files.

## Student
- [ ] S1: Android signup confirmation opens the installed app; document required App Link/auth configuration. Code, release fingerprint and live association file verified; Supabase email template publication and physical Android test remain.
- [x] S2: Academic and Campus feature screens scroll with reachable controls. All 17 routed feature screens contain a scrollable surface; large-text scroll regression tests pass.
- [x] S3: Past papers use canonical modules, not duplicate subject-name variants; files can be viewed and downloaded. Legacy cache moved to a new module-normalised namespace. One live record still has no file and needs an admin upload.
- [x] S4: Published assignment attachments can be viewed and downloaded. Private Storage policy migration is ready and transaction-tested but not live yet.
- [x] S5: Students can view their submitted document and replace it when the assignment rules allow. Database update confirmation is required before the old private file is removed.
- [x] S6: Donation page opens the donation form from a Donate button, not by default.
- [x] S7: Remove the academic-period selector from ICASS.
- [x] S8: Timetables can be downloaded from inside the app.
- [x] S9: Assignment calendar includes the publication date as well as the deadline. New publication timestamp and trigger are in the pending migration; legacy published records are backfilled from creation time.
- [x] S10: Remove the global Upload work button; rename the per-assignment upload action to Submit assignment.
- [x] S11: Show text captions alongside document attachments in private and group chats.

## Staff
- [x] L1: Past-paper form label is Exam type; remove manual old paper-title field and derive a title.
- [x] L2: Add Internal exam, Internal exam (memo), Final exam, Final exam (memo), retaining the requested existing types.
- [x] L3: Remove lecturer timetable page/navigation/upload access from the staff UI. Old bookmarked route safely redirects to Academic Library.
- [x] L4: Provide back navigation throughout staff dashboard pages with a safe in-app fallback.

## Admin
- [x] A1: Remove manual old paper-title field; derive a title and add the four exam types from L2.
- [x] A2: Audit Owner management coverage and enable missing authorized controls without altering Vice Admin permissions; preserve immutable audit logs and last-Owner safeguards. Added Owner-only workflow controls for submissions, attempts, attendance, orders, applications and SOS cases; protected evidence/telemetry/audit records remain read-only.
- [x] A3: Careers form only has Title, Description, Category (Internship, Learnership, Part time, Remote, Full time), Company, application destination (link/email/physical address), Closing date, Requirements. Student handoff now opens links/email and presents physical details for copying.
- [x] A4: Accommodation rent is shown only for non-NSFAS accommodation. Hide prices from students for NSFAS accommodation.
- [x] A5: Remove accommodation accreditation-expiry, amenities and available-spaces form fields without deleting existing data.
- [x] A6: Provide back navigation throughout admin pages with a safe fallback.

## Shared verification and handoff
- [ ] V1: Check table/column names, file buckets, permissions and data mappings across all affected apps; keep existing data compatible. Schema and policies were checked live; the new private-file/calendar migration is transaction-tested but must still be applied.
- [x] V2: Run static checks and targeted regression tests; record exact outcomes and any untested live/device paths. Student analyzer: clean; Flutter tests: 17/17; cross-project contracts: 8/8; admin/staff TypeScript: clean. Physical Android confirmation, live private download and browser save dialogs remain manual tests.
- [x] V3: Report remaining blockers honestly before giving final build/deploy commands for affected apps. User performs builds and deployments.

## Remaining release blockers

1. Apply `20260906093116_academic_download_access.sql` before testing private past-paper and assignment downloads.
2. Publish `docs/student-confirmation-email-template.html` in Supabase Auth, then confirm signup on a physical Android phone.
3. Attach a real file to past-paper record `b4c0da22-0a78-4bd2-9baf-6a1f990d6c1a`; the database currently has neither a Storage path nor URL for it.

Coverage review: all requested student, staff, admin and cross-app tasks are represented above. Main website is outside scope.

Interpretation: 'Owner manages everything' means all app-managed business resources, not the ability to erase audit records or bypass the existing last-Owner protection. Any conflict will be reported instead of silently weakening security.
