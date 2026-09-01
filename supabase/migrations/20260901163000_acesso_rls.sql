-- =============================================================================
-- Card 3.4 — Funções de acesso e políticas de RLS
-- Fonte: docs/modelagem-dados-ddl.md §3 e §4, docs/permissoes-matriz.md §4,
--        docs/regras-negocio-funcoes.md §2.2 e §2.3, docs/views-leitura.md §3.3
--
-- Entrega: fn_hoje, fn_contexto_rotina, fn_unidade_atual, tem_permissao,
--          fn_minhas_permissoes, fn_exige_permissao, fn_param_txt, fn_param_int
--          + as políticas das sete tabelas criadas pelo card 3.3.
--
-- Esta migração fecha a janela aberta pelo card 3.3: lá as sete tabelas ficaram
-- com RLS habilitada e FORÇADA e nenhuma política — sem acesso para ninguém.
-- Aqui elas ganham acesso, e só o que a matriz do card 2.4 §4 autoriza.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. fn_hoje() — "hoje" na escola, não em UTC
--    (card 2.3 §3.3, ajuste #1 — BLOQUEANTE)
-- -----------------------------------------------------------------------------
-- O Postgres do Supabase roda em UTC. Das 21h à meia-noite em São Paulo,
-- current_date já é o dia seguinte: erra a lotação do bloco (reposições "de
-- hoje"), os dias em STANDBY e a previsão vencida — sempre no mesmo sentido, e
-- sempre à noite, quando ninguém está conferindo.
--
-- Não é security definer: não lê tabela nenhuma, então não há RLS a contornar.
-- A lista fechada do teste C8 é para funções que precisam ignorar RLS; entrar
-- nela sem necessidade é gastar a revisão consciente que a lista existe para
-- provocar.
create or replace function public.fn_hoje()
returns date
language sql
stable
set search_path = public, pg_temp
as $$ select (now() at time zone 'America/Sao_Paulo')::date $$;

comment on function public.fn_hoje() is
  'Data corrente no fuso da escola (America/Sao_Paulo). Substitui current_date em TODA view, função e rotina (card 2.3 §3.3).';

revoke execute on function public.fn_hoje() from public;
revoke execute on function public.fn_hoje() from anon;
grant  execute on function public.fn_hoje() to authenticated;

-- -----------------------------------------------------------------------------
-- 2. fn_contexto_rotina() — o desvio das rotinas pg_cron (card 2.2 §2.2)
-- -----------------------------------------------------------------------------
-- Dentro do pg_cron não há auth.uid(): fn_unidade_atual() não teria como saber
-- em que unidade opera, e toda política reprovaria. As rotinas rt_* setam as
-- duas GUCs abaixo com set_config(..., is_local => true) e as duas funções de
-- contexto passam a responder por elas.
--
-- is_local = true amarra o contexto à transação: ele evapora no commit, mesmo
-- se a rotina falhar no meio.
--
-- Por que um cliente não consegue entrar nesse contexto: as GUCs só são escritas
-- dentro das rt_*, que são security definer e não recebem grant execute para
-- anon/authenticated (teste C9). O PostgREST só expõe função com grant.
--
-- ⚠️ O papel `postgres` do Supabase TEM BYPASSRLS (achado do card 3.3), então a
-- rotina não precisa deste desvio para *enxergar* linhas — precisa dele para
-- saber QUAL unidade é a corrente. Muda a justificativa, não o desenho.
create or replace function public.fn_contexto_rotina()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$ select coalesce(current_setting('app.rotina', true), '') = 'on' $$;

comment on function public.fn_contexto_rotina() is
  'Verdadeiro dentro de uma rotina rt_* (GUC app.rotina = on). Card 2.2 §2.2.';

-- Sem grant para authenticated: é função interna, consumida por fn_unidade_atual
-- e tem_permissao, que são security definer e rodam como o dono.
revoke execute on function public.fn_contexto_rotina() from public;
revoke execute on function public.fn_contexto_rotina() from anon;

-- -----------------------------------------------------------------------------
-- 3. fn_unidade_atual() — a unidade do contexto corrente
-- -----------------------------------------------------------------------------
-- security definer para não recursar: ela lê `usuario`, que tem RLS, e a
-- política de `usuario` chama fn_unidade_atual().
--
-- `and u.ativo`: usuário desativado devolve null, e `unidade_id = null` é null
-- em toda política — ou seja, nega. Desativar o usuário é, por construção,
-- tirar-lhe o acesso, sem depender de ninguém lembrar de remover os perfis.
create or replace function public.fn_unidade_atual()
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
           when public.fn_contexto_rotina()
             then nullif(current_setting('app.rotina_unidade', true), '')::uuid
           else (select u.unidade_id
                   from public.usuario u
                  where u.id = auth.uid()
                    and u.ativo)
         end;
$$;

comment on function public.fn_unidade_atual() is
  'Unidade do usuário autenticado, ou a unidade da rotina quando em contexto rt_*. Usada em TODA política de RLS (cards 2.1 §4 e 2.2 §2.2).';

revoke execute on function public.fn_unidade_atual() from public;
revoke execute on function public.fn_unidade_atual() from anon;
grant  execute on function public.fn_unidade_atual() to authenticated;

-- -----------------------------------------------------------------------------
-- 4. tem_permissao(codigo) — o código NUNCA verifica perfil, sempre permissão
-- -----------------------------------------------------------------------------
-- security definer pelo mesmo motivo: ela lê usuario_perfil e perfil_permissao,
-- cujas políticas exigiriam `admin.ler` — e a checagem de `admin.ler` chamaria
-- tem_permissao de novo.
--
-- Três filtros além do que o DDL do card 2.1 trazia, todos pelo mesmo motivo
-- (estado que a tela deixa mudar não pode continuar concedendo acesso):
--   u.ativo    — usuário desativado não tem permissão nenhuma;
--   pe.ativo   — perfil desativado não concede nada, mesmo com as linhas de
--                perfil_permissao intactas;
--   up.unidade_id = u.unidade_id — perfil de outra unidade não vale aqui.
-- Sem `pe.ativo`, desativar um perfil na tela de Administração seria uma ação
-- sem efeito nenhum: a caixa desmarca e o usuário continua entrando.
create or replace function public.tem_permissao(p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.fn_contexto_rotina()
      or exists (
           select 1
             from public.usuario u
             join public.usuario_perfil up   on up.usuario_id = u.id
                                            and up.unidade_id = u.unidade_id
             join public.perfil pe           on pe.id = up.perfil_id
             join public.perfil_permissao pp on pp.perfil_id = pe.id
             join public.permissao p         on p.id = pp.permissao_id
            where u.id = auth.uid()
              and u.ativo
              and pe.ativo
              and p.ativo
              and p.codigo = p_codigo
         );
$$;

comment on function public.tem_permissao(text) is
  'Verdadeiro se o usuário autenticado tem a permissão <dominio>.<acao>. Usada em RLS e nos guards do Flutter. Sempre verdadeira em contexto de rotina (card 2.2 §2.2).';

revoke execute on function public.tem_permissao(text) from public;
revoke execute on function public.tem_permissao(text) from anon;
grant  execute on function public.tem_permissao(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 5. fn_minhas_permissoes() — a lista que a camada de sessão do Flutter carrega
-- -----------------------------------------------------------------------------
-- Sem ela o card 3.7 não tem como montar a sessão. Ler a matriz pela tabela
-- exige `admin.ler` (card 2.4 §4), que na matriz inicial só a direção tem — ou
-- seja, monitor, secretaria e pedagógico entrariam no app sem saber o que podem
-- fazer, e a decisão "botão sem permissão é ocultado" (card 2.6) ficaria sem
-- fonte. Uma chamada por permissão a tem_permissao() seria dezenas de idas ao
-- banco no login.
--
-- Não abre nada: devolve as permissões do PRÓPRIO usuário, que é exatamente o
-- que ele já pode descobrir chamando tem_permissao() código a código.
--
-- Em contexto de rotina devolve vazio de propósito: rotina não monta tela, e
-- tem_permissao() já responde `true` para qualquer código lá dentro.
create or replace function public.fn_minhas_permissoes()
returns setof text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.codigo
    from public.usuario u
    join public.usuario_perfil up   on up.usuario_id = u.id
                                   and up.unidade_id = u.unidade_id
    join public.perfil pe           on pe.id = up.perfil_id
    join public.perfil_permissao pp on pp.perfil_id = pe.id
    join public.permissao p         on p.id = pp.permissao_id
   where u.id = auth.uid()
     and u.ativo
     and pe.ativo
     and p.ativo
   group by p.codigo
   order by p.codigo;
$$;

comment on function public.fn_minhas_permissoes() is
  'Códigos de permissão do próprio usuário autenticado. Fonte da camada de sessão e dos guards de rota do Flutter (cards 2.6 e 3.7).';

revoke execute on function public.fn_minhas_permissoes() from public;
revoke execute on function public.fn_minhas_permissoes() from anon;
grant  execute on function public.fn_minhas_permissoes() to authenticated;

-- -----------------------------------------------------------------------------
-- 6. fn_exige_permissao(codigo) — o erro certo no topo de toda função
-- -----------------------------------------------------------------------------
-- A RLS já barraria a escrita, mas o erro dela é opaco ("nenhuma linha
-- afetada"). Esta dá ao usuário a mensagem certa e ao Flutter o código estável.
-- Não é security definer: só chama tem_permissao(), que já é.
create or replace function public.fn_exige_permissao(p_codigo text)
returns void
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  if not public.tem_permissao(p_codigo) then
    raise exception using
      errcode = 'PT403',
      message = 'Você não tem permissão para executar esta ação.',
      detail  = json_build_object('codigo', 'SEM_PERMISSAO',
                                  'permissao', p_codigo)::text,
      hint    = 'Peça à direção para conceder a permissão ao seu perfil.';
  end if;
end;
$$;

comment on function public.fn_exige_permissao(text) is
  'Levanta PT403 / SEM_PERMISSAO se o usuário não tem a permissão. Usada no topo de toda função de aplicação (card 2.2 §2.3).';

revoke execute on function public.fn_exige_permissao(text) from public;
revoke execute on function public.fn_exige_permissao(text) from anon;
grant  execute on function public.fn_exige_permissao(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. fn_param_txt / fn_param_int — nenhum número mágico dentro de função
-- -----------------------------------------------------------------------------
-- security definer com filtro de unidade no corpo (card 2.4, achado #4,
-- escalado a BLOQUEANTE pelo card de Ordem 5). Como security invoker, ler
-- `parametro` exigiria `parametros.ler`, que na matriz inicial só a direção tem:
-- v_projecao_aluno chama fn_param_int quatro vezes e fn_rep_situacao é chamada
-- pela tela — as duas erram com PARAMETRO_AUSENTE para os outros três perfis,
-- que o card 2.4 autorizou a ver essas telas. Um parâmetro de negócio não é
-- dado restrito: restrito é EDITÁ-LO (parametros.gerir).
--
-- Sendo definer, o filtro `unidade_id = fn_unidade_atual()` tem de estar no
-- corpo — é ele, e não a RLS, que impede a leitura cruzar unidade. Mesma lição
-- de fn_capacidade_efetiva (card 2.3 §3.4) e das funções de credencial (2.9).
create or replace function public.fn_param_txt(p_chave text, p_default text default null)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_valor text;
begin
  select p.valor
    into v_valor
    from public.parametro p
   where p.unidade_id = public.fn_unidade_atual()
     and p.chave = p_chave;

  v_valor := coalesce(v_valor, p_default);

  if v_valor is null then
    raise exception using
      errcode = 'PT422',
      message = format('O parâmetro "%s" não está configurado nesta unidade.', p_chave),
      detail  = json_build_object('codigo', 'PARAMETRO_AUSENTE',
                                  'chave', p_chave)::text,
      hint    = 'Cadastre o parâmetro em Administração → Parâmetros.';
  end if;

  return v_valor;
end;
$$;

comment on function public.fn_param_txt(text, text) is
  'Lê um parâmetro de texto da unidade corrente. PT422 / PARAMETRO_AUSENTE se não houver valor nem default (card 2.2 §2.3).';

create or replace function public.fn_param_int(p_chave text, p_default integer default null)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return public.fn_param_txt(p_chave, p_default::text)::integer;
end;
$$;

comment on function public.fn_param_int(text, integer) is
  'Lê um parâmetro inteiro da unidade corrente. PT422 / PARAMETRO_AUSENTE se não houver valor nem default (card 2.2 §2.3).';

revoke execute on function public.fn_param_txt(text, text)    from public;
revoke execute on function public.fn_param_txt(text, text)    from anon;
grant  execute on function public.fn_param_txt(text, text)    to authenticated;
revoke execute on function public.fn_param_int(text, integer) from public;
revoke execute on function public.fn_param_int(text, integer) from anon;
grant  execute on function public.fn_param_int(text, integer) to authenticated;

-- =============================================================================
-- 8. Políticas de RLS — card 2.4 §4, tabela a tabela
--
-- Toda política é `to authenticated`: anon não tem política nenhuma em lugar
-- nenhum, e sem política é sem acesso. Célula "—" do §4 = política ausente de
-- propósito, e a ausência está asserida no teste 010 (C4).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 8.1 unidade — a única tabela sem coluna unidade_id: ela É a unidade
-- -----------------------------------------------------------------------------
-- O filtro do §4 ("unidade_id = fn_unidade_atual()") aqui vira `id =
-- fn_unidade_atual()`.
--
-- No insert não há filtro de unidade possível, e não é descuido: uma unidade
-- nova, por definição, não é a unidade corrente de ninguém. Exigir `id =
-- fn_unidade_atual()` no with check tornaria impossível criar a segunda unidade
-- pela tela na Fase 11 — a política diria "sim" só para a unidade que já existe.
-- O controle aqui é `unidades.gerir`, que na matriz inicial é só da direção.
create policy unidade_sel on public.unidade for select to authenticated
  using (id = public.fn_unidade_atual() and public.tem_permissao('unidades.ler'));

create policy unidade_ins on public.unidade for insert to authenticated
  with check (public.tem_permissao('unidades.gerir'));

create policy unidade_upd on public.unidade for update to authenticated
  using      (id = public.fn_unidade_atual() and public.tem_permissao('unidades.gerir'))
  with check (id = public.fn_unidade_atual() and public.tem_permissao('unidades.gerir'));

-- sem delete: unidade não se apaga (ativo = false).

-- -----------------------------------------------------------------------------
-- 8.2 usuario
-- -----------------------------------------------------------------------------
-- `or id = auth.uid()` além do `admin.ler` do §4: sem isso o usuário não lê a
-- própria linha, porque `admin.ler` na matriz inicial é só da direção — e a
-- camada de sessão do card 3.7 precisa do nome e da unidade de quem entrou. Ver
-- o próprio cadastro não é privilégio administrativo; é o mínimo para o app
-- saber quem está logado.
create policy usuario_sel on public.usuario for select to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and (public.tem_permissao('admin.ler') or id = auth.uid()));

create policy usuario_ins on public.usuario for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_usuarios'));

create policy usuario_upd on public.usuario for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_usuarios'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_usuarios'));

-- sem delete: usuário não se apaga (ativo = false), e a FK de auth.users é
-- `on delete restrict`.

-- -----------------------------------------------------------------------------
-- 8.3 perfil
-- -----------------------------------------------------------------------------
create policy perfil_sel on public.perfil for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('admin.ler'));

create policy perfil_ins on public.perfil for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_perfis'));

create policy perfil_upd on public.perfil for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_perfis'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_perfis'));

-- sem delete: perfil não se apaga (ativo = false) — apagá-lo levaria junto, em
-- cascata, a matriz inteira daquele perfil.

-- -----------------------------------------------------------------------------
-- 8.4 permissao — leitura e nada mais (card 2.4 (e))
-- -----------------------------------------------------------------------------
-- O catálogo só muda por migração: um código novo só serve depois que alguma
-- política, função ou rota passa a exigi-lo, e isso é código, não dado. Sem
-- política de escrita também se fecha o modo de falha mais bobo possível —
-- alguém apagar `estoque.lancar_saida` pela tela e nenhuma entrega funcionar
-- mais. Ausência permanente, asserida no teste 010 (C4).
create policy permissao_sel on public.permissao for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('admin.ler'));

-- -----------------------------------------------------------------------------
-- 8.5 perfil_permissao — a matriz
-- -----------------------------------------------------------------------------
-- Marcar é insert, desmarcar é delete; não há update possível numa tabela que
-- só tem as duas chaves. Por isso `update` fica sem política (§4).
create policy perfil_permissao_sel on public.perfil_permissao for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('admin.ler'));

create policy perfil_permissao_ins on public.perfil_permissao for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_perfis'));

create policy perfil_permissao_del on public.perfil_permissao for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('admin.gerir_perfis'));

-- -----------------------------------------------------------------------------
-- 8.6 usuario_perfil — atribuição de perfil ao usuário
-- -----------------------------------------------------------------------------
create policy usuario_perfil_sel on public.usuario_perfil for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('admin.ler'));

create policy usuario_perfil_ins on public.usuario_perfil for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('admin.gerir_usuarios'));

create policy usuario_perfil_del on public.usuario_perfil for delete to authenticated
  using (unidade_id = public.fn_unidade_atual()
         and public.tem_permissao('admin.gerir_usuarios'));

-- -----------------------------------------------------------------------------
-- 8.7 parametro
-- -----------------------------------------------------------------------------
-- `parametros.ler` guarda a TELA de parâmetros, não a leitura pelas regras: as
-- regras leem por fn_param_int/fn_param_txt, que são security definer justamente
-- para não dependerem desta política (§7 acima).
create policy parametro_sel on public.parametro for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.tem_permissao('parametros.ler'));

create policy parametro_ins on public.parametro for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('parametros.gerir'));

create policy parametro_upd on public.parametro for update to authenticated
  using      (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('parametros.gerir'))
  with check (unidade_id = public.fn_unidade_atual()
              and public.tem_permissao('parametros.gerir'));

-- sem delete: parâmetro ausente é erro PARAMETRO_AUSENTE, e apagar um parâmetro
-- pela tela quebraria a função que o lê. Corrige-se o valor, não se remove a
-- linha.
