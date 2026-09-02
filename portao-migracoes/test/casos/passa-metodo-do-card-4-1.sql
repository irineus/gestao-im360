-- O que a migração do card 4.1 pode ter: ESTRUTURA, mais as três linhas de
-- `metodo` — enumeração fixa do produto, já referenciada pelos parâmetros
-- `ritmo_padrao_dias_*` do seed do 3.6. `material`, `curso`, `modulo` e `combo`
-- nascem VAZIAS: o catálogo real vem pelo importador do card 9.1.
create table public.metodo (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade (id),
  codigo text not null,
  nome text not null
);

create table public.material (
  id uuid primary key default gen_random_uuid(),
  unidade_id uuid not null references public.unidade (id) on update cascade,
  metodo_id uuid not null references public.metodo (id),
  codigo text not null
);

do $$
declare
  v_unidade uuid;
begin
  select id into v_unidade from public.unidade where codigo = 'MATRIZ';

  insert into public.metodo (unidade_id, codigo, nome)
  values (v_unidade, 'INTERATIVO', 'Interativo'),
         (v_unidade, 'INGLES',     'Inglês'),
         (v_unidade, 'MODULAR',    'Modular')
  on conflict (unidade_id, codigo) do update set nome = excluded.nome;
end $$;
