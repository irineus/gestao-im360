-- DDL que contém as palavras da escrita sem escrever nada. Um grep ingênuo
-- reprovaria este arquivo inteiro.
create table public.aluno (
  id uuid primary key,
  unidade_id uuid not null references public.unidade (id) on update cascade on delete restrict,
  status text not null
);

create policy aluno_insert on public.aluno for insert to authenticated with check (true);
create policy aluno_update on public.aluno for update to authenticated using (true);
create policy aluno_delete on public.aluno for delete to authenticated using (true);

grant select, insert, update, delete on table public.aluno to authenticated;

create or replace function public.fn_ativos() returns setof public.aluno
language sql stable as $$ select * from public.aluno for update $$;
