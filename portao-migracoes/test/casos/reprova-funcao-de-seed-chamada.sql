-- O disfarce que o card 3.6 tornou natural: o corpo é isento, mas a migração
-- CHAMA a função — e aí o que ela escreve é escrito pela migração.
create or replace function public.fn_seed_catalogo(p_unidade_id uuid)
returns void
language plpgsql
as $$
begin
  perform public.fn_seed_cursos(p_unidade_id);
end $$;

create or replace function public.fn_seed_cursos(p_unidade_id uuid)
returns void
language plpgsql
as $$
begin
  insert into public.curso (unidade_id, codigo, nome) values (p_unidade_id, 'INF', 'Informática');
end $$;

select public.fn_seed_catalogo('00000000-0000-0000-0000-000000000001'::uuid);
