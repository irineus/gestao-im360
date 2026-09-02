-- Nem comentário nem literal é comando: "insert into aluno" escrito aqui não
-- grava nada. `delete from combo` também não.
comment on table public.aluno is $doc$
  Migrar com o importador do card 9.1; nunca com insert into aluno numa migração.
$doc$;

create or replace function public.fn_mensagem()
returns text language sql as $$ select 'insert into aluno é proibido em migração'::text $$;
