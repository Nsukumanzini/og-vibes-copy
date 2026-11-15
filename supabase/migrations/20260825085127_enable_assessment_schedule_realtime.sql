do $$
begin
  alter publication supabase_realtime add table public.assessment_briefs;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.quizzes;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.assignment_submissions;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.quiz_attempts;
exception when duplicate_object then null;
end $$;
