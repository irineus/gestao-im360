-- `create trigger … execute function fn()` REGISTRA quem vai rodar depois; não
-- chama nada agora. Se o portão confundisse as duas coisas, todo trigger de
-- negócio das fases 5 e 6 reprovaria.
create or replace function public.fn_pendencia_bloco()
returns trigger language plpgsql as $$
begin
  insert into public.pendencia (unidade_id, tipo) values (new.unidade_id, 'BLOCO_ACIMA_CAPACIDADE');
  return new;
end $$;

create trigger tg_pendencia_bloco
  after insert on public.bloco_aluno
  for each row execute function public.fn_pendencia_bloco();
