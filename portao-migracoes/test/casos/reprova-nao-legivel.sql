create or replace function public.fn_incompleta()
returns void language plpgsql as $$
begin
  insert into public.aluno (nome) values ('sem fim');
