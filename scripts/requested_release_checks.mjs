import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';

const student = fileURLToPath(new URL('../', import.meta.url));
const admin = path.resolve(student, '../og-vibes-admin');
const staff = path.resolve(student, '../og-vibes-staff');
const staffRequire = createRequire(path.join(staff, 'package.json'));
const ts = staffRequire('typescript');
const read = (root, file) => readFile(path.join(root, file), 'utf8');

test('Admin exam choices include internal and final exams and memos', async () => {
  const ui = await read(admin, 'src/resourceUi.ts');
  assert.match(ui, /exam_type: \[[^\]]*"Internal exam"[^\]]*"Final exam"/);
  assert.match(ui, /flatMap\(\(value\) => \[value, `\$\{value\} \(memo\)`\]\)/);
  assert.match(ui, /past_papers: \["module_id", "exam_type", "year"\]/);
});

test('Career categories match the requested five choices', async () => {
  const ui = await read(admin, 'src/resourceUi.ts');
  assert.match(ui, /category: \["Internship", "Learnership", "Part time", "Remote", "Full time"\]/);
});

test('Vice Admin cannot gain Owner-only actions or change their own role', async () => {
  const security = await read(student, 'supabase/functions/admin-control/security.ts');
  assert.match(security, /ownerOnlyActions = new Set\(\["set_vice_admin", "audit_export", "remove"\]\)/);
  assert.match(security, /role === "owner" && Boolean\(targetId\) && actorId !== targetId/);
});

test('Staff timetable route redirects and navigation no longer exposes it', async () => {
  assert.match(await read(staff, 'app/dashboard/schedule/page.tsx'), /redirect\(['"]\/dashboard\/slides['"]\)/);
  assert.doesNotMatch(await read(staff, 'components/dashboard/sidebar.tsx'), /href:\s*["']\/dashboard\/schedule/);
});

test('Staff papers derive their title without a manual paper-title field', async () => {
  const source = await read(staff, 'components/dashboard/operation-managers.tsx');
  assert.match(source, /Exam type/);
  assert.doesNotMatch(source, /paperMode\?"Paper title"/);
  assert.match(source, /Internal exam/);
  assert.match(source, /Final exam/);
});

test('Admin function derives paper titles and keeps audit logs immutable', async () => {
  const source = await read(student, 'supabase/functions/admin-control/index.ts');
  const parsed = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2022 }, reportDiagnostics: true,
  });
  assert.equal(parsed.diagnostics?.length ?? 0, 0);
  assert.match(source, /payload\.title = `\$\{selectedModule\.name\}/);
  assert.match(source, /if \(payload\.nsfas_accredited === true\) payload\.monthly_price = 0/);
  assert.match(source, /admin_audit_logs: \{[^\n]*readOnly: true/);
  assert.match(source, /const ownerResourceOverrides/);
  assert.match(source, /assignment_submissions: \{[\s\S]*?delete: true/);
  assert.match(source, /role !== "owner"/);
});

test('Signup confirmation is verified on the associated student domain', async () => {
  const main = await read(student, 'lib/main.dart');
  const confirmation = await read(student, 'lib/screens/signup_confirmation_screen.dart');
  const manifest = await read(student, 'android/app/src/main/AndroidManifest.xml');
  const association = JSON.parse(await read(student, 'web/.well-known/assetlinks.json'));
  assert.match(main, /student\.ogvibes\.co\.za/);
  assert.match(main, /queryParameters\['token_hash'\]/);
  assert.match(confirmation, /auth\.verifyOTP/);
  assert.match(confirmation, /OtpType\.email/);
  assert.match(manifest, /android:autoVerify="true"/);
  assert.match(manifest, /android:host="student\.ogvibes\.co\.za"/);
  assert.equal(association[0].target.package_name, 'za.co.ogtechnologies.ogvibes');
});

test('Academic storage migration covers papers and published assessments', async () => {
  const migration = await read(student, 'supabase/migrations/20260906093116_academic_download_access.sql');
  assert.match(migration, /public\.past_papers/);
  assert.match(migration, /public\.assessment_briefs/);
  assert.match(migration, /private\.can_access_module/);
  assert.match(migration, /published_at timestamptz/);
  assert.doesNotMatch(migration, /bucket_id\s*=\s*'academic-content'[\s\S]*or\s+true/i);
});
