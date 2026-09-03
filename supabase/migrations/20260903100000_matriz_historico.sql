-- =============================================================================
-- Card 4.7.5 — Histórico de alteração da matriz de permissões
-- Fonte: docs/permissoes-matriz.md §10.2, docs/seed-inicial.md §2.1 e a seção 4
--        das Decisões vigentes ("log de alterações" como mitigação do risco de
--        permissões mal definidas exporem dados).
--
-- Entrega: perfil_permissao_hist + fn_perfil_permissao_historico (trigger em
--          perfil_permissao) + fn_seed_matriz reescrita para NÃO devolver o
--          código que alguém tirou de todos os perfis.
--
-- O problema que este arquivo resolve, em uma frase: desmarcar uma caixa na
-- tela de Administração (card 4.7) é um DELETE em perfil_permissao, e delete
-- não deixa rastro — três meses depois ninguém sabe quem tirou estoque.ajustar
-- da secretaria. perfil_permissao tem criado_em/por (card 3.3), mas a linha que
-- carregava o carimbo é justamente a que sumiu.
--
-- Das duas saídas que o card 2.4 §10.2 pôs na mesa — tabela de histórico
-- escrita por trigger, ou trocar o delete por `ativo = false` — ficou a
-- primeira: a segunda mudaria a política de RLS de perfil_permissao (card 2.4
-- §4), o join de tem_permissao (card 3.4) e o guarda do seed (card 3.6), três
-- lugares já asseridos, para obter um histórico de UMA transição só (a linha
-- guardaria apenas o último estado). Uma tabela imutável guarda todas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. A tabela — imutável por ausência de política (como aluno_status_hist e
--    pc_credencial_acesso), e escrita só por trigger
-- -----------------------------------------------------------------------------
-- Os dois códigos ficam gravados como texto, além dos ids: o histórico é para
-- ser lido três meses depois, sem join, e o que uma pessoa reconhece é
-- `SECRETARIA` / `estoque.ajustar`, não um uuid.
--
-- As FKs são `on delete restrict`, e não cascade, pela lição do card 4.3: a
-- cascata de uma FK não passa pela RLS da tabela referenciadora, e um perfil
-- apagado levaria junto, em silêncio, a prova de quem mexeu na matriz dele.
-- Perfil não se apaga (ativo = false, card 3.4) e código de permissão só sai
-- por migração — e uma migração que retire um código terá de decidir, por
-- escrito, o que faz com o histórico dele.
create table public.perfil_permissao_hist (
  id               uuid primary key default gen_random_uuid(),
  unidade_id       uuid not null references public.unidade(id),
  perfil_id        uuid not null references public.perfil(id)    on delete restrict,
  perfil_codigo    text not null,
  permissao_id     uuid not null references public.permissao(id) on delete restrict,
  permissao_codigo text not null,
  acao             text not null check (acao in ('CONCEDIDA', 'REMOVIDA')),
  criado_em        timestamptz not null default now(),
  criado_por       uuid,
  atualizado_em    timestamptz,
  atualizado_por   uuid
);

comment on table public.perfil_permissao_hist is
  'Toda concessão e toda remoção de permissão a um perfil, escrita por trigger em perfil_permissao. Imutável: sem política de update nem de delete (card 4.7.5). criado_por nulo = escrita da migração (seed), não de uma pessoa.';
comment on column public.perfil_permissao_hist.acao is
  'CONCEDIDA = linha inserida em perfil_permissao (caixa marcada); REMOVIDA = linha apagada (caixa desmarcada).';

-- A tela lê por unidade, do mais recente para o mais antigo; o seed procura
-- por permissão.
create index perfil_permissao_hist_unidade_ix
  on public.perfil_permissao_hist (unidade_id, criado_em desc);
create index perfil_permissao_hist_permissao_ix
  on public.perfil_permissao_hist (permissao_id);
create index perfil_permissao_hist_perfil_ix
  on public.perfil_permissao_hist (perfil_id);

create trigger tg_auditoria_perfil_permissao_hist
  before insert or update on public.perfil_permissao_hist
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 2. RLS: leitura por admin.ler, e mais nada
-- -----------------------------------------------------------------------------
-- Sem insert: quem escreve é o trigger, abaixo, como `security definer` — e o
-- dono (`postgres`) tem BYPASSRLS (card 3.3). Um POST direto no PostgREST cai
-- na ausência de política e é recusado; é assim que ninguém grava "remoção" de
-- uma permissão que continua lá (a lição de tg_aluno_status_hist_coerente,
-- card 4.2, resolvida aqui por construção em vez de por trigger de coerência).
-- Sem update nem delete: a imutabilidade É a ausência (cards 4.2 e 4.3).
alter table public.perfil_permissao_hist enable row level security;
alter table public.perfil_permissao_hist force  row level security;

create policy perfil_permissao_hist_sel on public.perfil_permissao_hist
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('admin.ler'));

-- -----------------------------------------------------------------------------
-- 3. O trigger
-- -----------------------------------------------------------------------------
-- security definer (lista C8, teste 011): o disparo acontece dentro da
-- transação de quem marcou ou desmarcou a caixa, que tem admin.gerir_perfis mas
-- não tem política de insert em perfil_permissao_hist — nem deve ter. Não
-- carrega filtro de unidade no corpo porque não devolve dado a ninguém: grava a
-- unidade da própria linha de perfil_permissao que acabou de mudar.
--
-- Dispara também na cascata (permissao → perfil_permissao, por exemplo): a
-- cascata não passa pela RLS mas passa pelo trigger, então a remoção em massa
-- fica registrada linha a linha.
create or replace function public.fn_perfil_permissao_historico()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linha public.perfil_permissao;
  v_acao  text;
begin
  if tg_op = 'INSERT' then
    v_linha := new;
    v_acao  := 'CONCEDIDA';
  else
    v_linha := old;
    v_acao  := 'REMOVIDA';
  end if;

  insert into public.perfil_permissao_hist
    (unidade_id, perfil_id, perfil_codigo, permissao_id, permissao_codigo, acao)
  select v_linha.unidade_id,
         pe.id, pe.codigo,
         pm.id, pm.codigo,
         v_acao
    from public.perfil    pe
    join public.permissao pm on pm.id = v_linha.permissao_id
   where pe.id = v_linha.perfil_id;

  return null;   -- after trigger: o retorno é ignorado
end;
$$;

comment on function public.fn_perfil_permissao_historico() is
  'Grava em perfil_permissao_hist cada linha inserida (CONCEDIDA) ou apagada (REMOVIDA) em perfil_permissao. Card 4.7.5.';

revoke execute on function public.fn_perfil_permissao_historico() from public, anon, authenticated;

create trigger tg_perfil_permissao_historico
  after insert or delete on public.perfil_permissao
  for each row execute function public.fn_perfil_permissao_historico();

-- -----------------------------------------------------------------------------
-- 4. O seed deixa de devolver o que alguém tirou de todos
-- -----------------------------------------------------------------------------
-- O guarda do card 3.6 é POR CÓDIGO: o seed só distribui um código que não tem
-- nenhuma linha na matriz da unidade. Ele fecha o caso "desmarquei de um
-- perfil" e deixa aberto o caso residual "desmarquei de todos" — sem histórico,
-- os dois estados (nunca dado × tirado de todo mundo) são a mesma ausência.
-- Com o histórico, deixam de ser: código com uma REMOVIDA registrada foi
-- tirado por alguém, e o deploy seguinte não o devolve. Código sem linha e sem
-- histórico nunca foi dado — é o código novo de uma migração futura, e continua
-- chegando.
--
-- Mesmo corpo do card 3.6, com UMA cláusula a mais; a matriz é a de
-- docs/permissoes-matriz.md §5 (direção 50, secretaria 37, pedagógico 22,
-- monitor 14).
create or replace function public.fn_seed_matriz(p_unidade_id uuid)
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_n integer;
begin
  insert into public.perfil_permissao (unidade_id, perfil_id, permissao_id)
  select p_unidade_id, pe.id, pm.id
    from (values
      ('admin.ler',                         '{DIRECAO}'::text[]),
      ('admin.gerir_usuarios',              '{DIRECAO}'),
      ('admin.gerir_perfis',                '{DIRECAO}'),
      ('unidades.ler',                      '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('unidades.gerir',                    '{DIRECAO}'),
      ('parametros.ler',                    '{DIRECAO}'),
      ('parametros.gerir',                  '{DIRECAO}'),
      ('materiais.ler',                     '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('materiais.criar',                   '{DIRECAO,SECRETARIA}'),
      ('materiais.editar',                  '{DIRECAO,SECRETARIA}'),
      ('materiais.excluir',                 '{DIRECAO,SECRETARIA}'),
      ('alunos.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('alunos.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.alterar_status',             '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('alunos.reverter_status',            '{DIRECAO}'),
      ('alunos.formar_sem_certificado',     '{DIRECAO}'),
      ('alunos.editar_trilha',              '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('salas.ler',                         '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('salas.criar',                       '{DIRECAO,SECRETARIA}'),
      ('salas.editar',                      '{DIRECAO,SECRETARIA}'),
      ('salas.excluir',                     '{DIRECAO}'),
      ('salas.registrar_manutencao',        '{DIRECAO,SECRETARIA,MONITOR}'),
      ('salas.acessar_credencial',          '{DIRECAO,MONITOR}'),
      ('professores.ler',                   '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('professores.criar',                 '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('professores.editar',                '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.ler',                        '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('turmas.criar',                      '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.editar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.excluir',                    '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.alocar',                     '{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('turmas.lancar_reposicao_retroativa','{DIRECAO,PEDAGOGICO,SECRETARIA}'),
      ('estoque.ler',                       '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('estoque.lancar_saida',              '{DIRECAO,SECRETARIA,MONITOR}'),
      ('estoque.estornar',                  '{DIRECAO,SECRETARIA}'),
      ('estoque.ajustar',                   '{DIRECAO,SECRETARIA}'),
      ('compras.ler',                       '{DIRECAO,SECRETARIA}'),
      ('compras.criar',                     '{DIRECAO,SECRETARIA}'),
      ('compras.editar',                    '{DIRECAO,SECRETARIA}'),
      ('compras.excluir',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber',                   '{DIRECAO,SECRETARIA}'),
      ('compras.receber_excedente',         '{DIRECAO}'),
      ('certificados.ler',                  '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('certificados.criar',                '{DIRECAO,SECRETARIA,MONITOR}'),
      ('certificados.marcar_pedagogico',    '{DIRECAO,PEDAGOGICO}'),
      ('certificados.marcar_financeiro',    '{DIRECAO,MONITOR}'),
      ('certificados.alterar_status',       '{DIRECAO,SECRETARIA}'),
      ('pendencias.ler',                    '{DIRECAO,PEDAGOGICO,SECRETARIA,MONITOR}'),
      ('pendencias.resolver',               '{DIRECAO,PEDAGOGICO,SECRETARIA}')
    ) as m(codigo, perfis)
    join public.permissao pm on pm.unidade_id = p_unidade_id and pm.codigo = m.codigo
    join public.perfil    pe on pe.unidade_id = p_unidade_id and pe.codigo = any (m.perfis)
   where not exists (select 1 from public.perfil_permissao pp
                      where pp.permissao_id = pm.id)
     -- card 4.7.5: código que ALGUÉM tirou (de um perfil ou de todos) não volta.
     and not exists (select 1 from public.perfil_permissao_hist h
                      where h.permissao_id = pm.id
                        and h.acao = 'REMOVIDA')
  on conflict (perfil_id, permissao_id) do nothing;

  select count(*) into v_n
    from public.perfil_permissao where unidade_id = p_unidade_id;
  return v_n;
end $$;

comment on function public.fn_seed_matriz(uuid) is
  'Matriz inicial de docs/permissoes-matriz.md §5 (direção 50, secretaria 37, pedagógico 22, monitor 14). Distribui só código que não tem linha nenhuma na unidade E nunca foi removido por ninguém (perfil_permissao_hist, card 4.7.5): código novo chega; código desmarcado na tela — de um perfil ou de todos — não volta no deploy seguinte.';

revoke execute on function public.fn_seed_matriz(uuid) from public, anon, authenticated;
