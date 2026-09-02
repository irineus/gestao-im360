-- `execute` com o comando inteiro num literal: aí o portão consegue ler, e
-- reprova nomeando a tabela em vez de reclamar do dinamismo.
do $$
begin
  execute 'insert into public.material (codigo, nome) values (''INT-01'', ''Interativo 1'')';
end $$;
