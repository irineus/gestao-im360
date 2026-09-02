-- Usuário de teste é da escola-fixture do card 3.4.5, em supabase/seed.sql, que
-- nunca sai do stack local.
do $$
begin
  insert into auth.users (id, email) values (gen_random_uuid(), 'teste@exemplo.com');
end $$;
