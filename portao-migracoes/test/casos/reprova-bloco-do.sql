-- Caso (c) do card 4.0,5: bloco `do $$ … $$` executa NA HORA da migração — é
-- por onde uma carga entraria disfarçada, então o portão nunca remove.
do $$
begin
  insert into public.material (unidade_id, codigo, nome)
  values ('00000000-0000-0000-0000-000000000001', 'INT-01', 'Interativo 1');
end $$;
