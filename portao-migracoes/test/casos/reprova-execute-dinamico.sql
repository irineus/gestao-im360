-- SQL montado em tempo de execução: o portão não consegue ler, então reprova.
do $$
declare
  v_tabela text := 'material';
begin
  execute 'insert into public.' || v_tabela || ' (codigo) values (''INT-01'')';
end $$;
