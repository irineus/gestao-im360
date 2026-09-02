-- Caso (b) do card 4.0,5: `insert into pendencia` legítimo — corpo de função,
-- que roda quando alguém chamar, não quando a migração aplicar. É a forma do
-- `gerar_pendencias` do card 5.5 e do `registrar_entrega` do 6.3.
create or replace function public.gerar_pendencias(p_unidade_id uuid)
returns integer
language plpgsql
as $$
begin
  insert into public.pendencia (unidade_id, tipo, referencia_id)
  select p_unidade_id, 'ALUNO_SEM_TURMA', a.id from public.aluno a;

  update public.pendencia set resolvida_em = now() where unidade_id = p_unidade_id;
  delete from public.pendencia where unidade_id = p_unidade_id and resolvida_em is not null;
  return 1;
end $$;
