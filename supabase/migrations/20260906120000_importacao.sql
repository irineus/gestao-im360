-- =============================================================================
-- Card 9.1 — Importação: as três tabelas, o guarda e as duas funções
--
-- Fontes: docs/plano-projeto-sistema.md §8 (o mapeamento fonte → destino e os
--           três princípios: reexecutável, auditável, ensaiada),
--         docs/wireframes.md §16 (a tela 13, assistente de 4 passos),
--         docs/permissoes-matriz.md §6 linha 13 e §7 item 4 (o conjunto exato da
--           rota, que este card é quem sabe),
--         docs/modelagem-dados-ddl.md §12 (as três tabelas novas, que o card 2.1
--           não previa — ver a divergência 1),
--         docs/estrategia-testes.md §13 (obrigação de teste) e §14 linha
--           "Migração de dados (Fase 9)": reexecutabilidade.
--
-- ⚠️ ESTRUTURA E MAIS NADA. Decisão de 02/09/2026 (Irineu): migração não grava
--    dado de negócio. Este arquivo cria tabela, política e função — nenhuma
--    linha de aluno, material ou movimento entra por aqui. É o oposto do que o
--    card faz em TEMPO DE EXECUÇÃO: a carga é operação de gente, disparada da
--    tela 13, contra o ambiente em que essa pessoa está logada.
--
-- -----------------------------------------------------------------------------
-- A ideia central, e é dela que sai tudo o mais:
--
--   A IMPORTAÇÃO NÃO REIMPLEMENTA REGRA NENHUMA. Ela empurra as linhas para as
--   tabelas de negócio, sob RLS, e deixa os triggers que já existem decidirem —
--   fn_bloco_aluno_admissao, fn_aluno_status_valida, fn_composicao_metodo_
--   coerente, tg_pc_manutencao_status, tg_pc_revalida_blocos. O que ela
--   acrescenta é o que faltava: a TRANSAÇÃO (tudo ou nada) e o RELATÓRIO.
--
--   É o §4.1 do card 2.3 aplicado ao maior candidato a segunda implementação do
--   projeto: um importador que checasse capacidade por conta própria teria duas
--   contas de vaga no sistema, e a que erra em silêncio é sempre a segunda.
--
--   A validação é o outro lado, e não contradiz isto: ela confere o ARQUIVO
--   CONTRA SI MESMO (o aluno alocado consta como ATIVO no mesmo arquivo? o
--   material referenciado existe?) e contra o que já está no banco. Nenhuma
--   das dezesseis verificações decide regra de negócio; elas antecipam, TODAS DE
--   UMA VEZ, o que o banco recusaria uma a uma — que é a diferença entre um
--   relatório com 40 linhas e quarenta uploads.
-- -----------------------------------------------------------------------------
--
-- Quatro códigos de erro novos, no fixture `test/fixtures/codigos_erro.txt` e no
-- catálogo do app (contrato do card 2.8 §10):
--   • IMPORTACAO_INEXISTENTE (404) — família de PC_INEXISTENTE: lote de outra
--     unidade é indistinguível de inexistente;
--   • ARQUIVO_INVALIDO (422) — o `jsonb` não é objeto, ou não traz entidade
--     nenhuma conhecida;
--   • IMPORTACAO_REPROVADA (422) — aplicar lote que tem ocorrência de ERRO;
--   • IMPORTACAO_JA_APLICADA (409) — aplicar duas vezes o MESMO lote. Não
--     confundir com reexecutar o mesmo snapshot, que é obrigatório e se faz
--     enviando o arquivo de novo: nasce outro lote, e o resultado é idêntico.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 1 — três tabelas fora do DDL do card 2.1. Ele lista
--    33 tabelas de negócio e nenhuma de importação, porque em 31/08/2026 a carga
--    ainda era "script + psql". A decisão de 02/09/2026 mudou isso: a carga
--    passou a ser operação de tempo de execução, e operação de tempo de execução
--    deixa rastro em tabela. `importacao` guarda o lote e o arquivo,
--    `importacao_ocorrencia` guarda o relatório (é o entregável "auditável" do
--    plano §8) e `importacao_referencia` guarda a chave externa das linhas que
--    NÃO têm chave natural — hoje só `movimento_estoque`.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 2 — `certificado_checklist` NÃO é importado, contra
--    a linha "Certificados → certificado_checklist" do plano §8. Quem decidiu
--    foi o card 8.3, por escrito, no comentário da própria tabela: «NÃO se migra
--    da planilha: a aba Certificados não guarda quem marcou nem quando, que é
--    justamente o que esta tabela existe para guardar». Importar aquilo criaria
--    quatro pares quem/quando nulos com cara de checklist trabalhado. O caminho
--    certo já existe e é a tela 9 (card 8.6), que abre o checklist à mão.
--
-- ⚠️ DIVERGÊNCIA REGISTRADA 3 — `pc.status = 'MANUTENCAO'` importado sozinho é
--    AVISO, não dado. `pc.status` é DERIVADO de `pc_manutencao` (card 5.4,
--    fn_pc_status_sincronizar) e a rotina `rt_pcs_normaliza` roda às 03:10: um
--    PC importado como MANUTENCAO sem a linha de manutenção volta a OPERACIONAL
--    na primeira madrugada, e a capacidade do bloco sobe sozinha. Por isso a
--    entidade `pc_manutencao` existe no arquivo, e por isso a verificação V14
--    avisa quem esquecer dela.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. As três tabelas
-- -----------------------------------------------------------------------------
create table public.importacao (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  arquivo       text not null,
  snapshot_em   date not null,
  status        text not null default 'VALIDADA'
                check (status in ('VALIDADA','REPROVADA','APLICADA','FALHOU')),
  dados         jsonb not null,
  totais        jsonb,
  simulado_em   timestamptz,
  aplicado_em   timestamptz,
  aplicado_por  uuid references public.usuario(id),
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid,
  constraint importacao_arquivo_ck check (btrim(arquivo) <> ''),
  constraint importacao_dados_ck   check (jsonb_typeof(dados) = 'object')
);

comment on table public.importacao is
  'Um lote de importação: o arquivo enviado, o snapshot que ele representa e o que aconteceu com ele. VAZIA em produção até a virada do card 9.7 — lá ela recebe UMA linha. Reexecutar o mesmo snapshot é enviar o arquivo de novo: nasce OUTRO lote, e é a idempotência por chave natural que faz os totais baterem.';
comment on column public.importacao.snapshot_em is
  'Data do snapshot da PLANILHA, não do upload — exigência do card 9.4: «divergir de totais tirados de dias diferentes já é divergir por nada». Informada por quem importa; o sistema não tem como inferi-la do arquivo.';
comment on column public.importacao.dados is
  'O arquivo inteiro, normalizado em jsonb pelo app (uma chave por entidade, um array por chave). Guardado porque o plano §8 exige AUDITÁVEL: sem o que entrou, o relatório de ocorrências fala de um arquivo que ninguém mais tem. O contrato do formato é docs/importacao.md §3, e o produtor dele é o card 9.2.';
comment on column public.importacao.status is
  'VALIDADA (sem ERRO, pode aplicar) · REPROVADA (tem ERRO, aplicar recusa) · APLICADA · FALHOU (o banco recusou alguma linha na aplicação e a transação inteira voltou). Não existe estado intermediário: a aplicação é uma transação só.';
comment on column public.importacao.totais is
  'O que o passo 4 do wireframes.md §16 mostra: por entidade, quantas linhas o arquivo trazia, quantas foram aplicadas, quantas foram ignoradas e quantas EXISTEM no sistema depois. A última coluna é a que se compara com o Dashboard da planilha (card 9.4) — as outras três explicam a diferença.';
comment on column public.importacao.simulado_em is
  'Carimbo da última simulação (fn_importacao_aplicar com p_simular). A simulação escreve de verdade e desfaz tudo por subtransação — é o "dry-run primeiro" do §16, e é o único jeito de medir o que os TRIGGERS diriam sem confiar numa segunda implementação deles.';

create table public.importacao_ocorrencia (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  importacao_id uuid not null references public.importacao(id) on delete cascade,
  severidade    text not null check (severidade in ('ERRO','AVISO')),
  entidade      text not null,
  linha         integer check (linha is null or linha > 0),
  codigo        text not null,
  mensagem      text not null,
  valor         text,
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid
);

comment on table public.importacao_ocorrencia is
  'O relatório do passo 3 (wireframes.md §16). ERRO bloqueia aplicar; AVISO aplica e fica registrado — é a separação que o §16 desenha e a lista de exceções que o card 9.3 revisa. Imutável pela AUSÊNCIA de política de update e delete, como aluno_status_hist e perfil_permissao_hist (card 2.4 §4).';
comment on column public.importacao_ocorrencia.codigo is
  'Código do relatório, para agrupar e filtrar (REFERENCIA_AUSENTE, ALUNO_SEM_TURMA, …). NÃO é código de erro do contrato do card 2.8 §10: nenhum deles chega ao app como exceção, e é por isso que a MENSAGEM em português vem gravada na linha em vez de ser traduzida pelo catálogo do Flutter.';
comment on column public.importacao_ocorrencia.linha is
  'Posição do item DENTRO do array da entidade (1 = primeiro), não a linha da planilha — o arquivo já passou pelo script do card 9.2 e a numeração original se perdeu ali. Nulo quando a ocorrência é do lote inteiro.';

create table public.importacao_referencia (
  id            uuid primary key default gen_random_uuid(),
  unidade_id    uuid not null references public.unidade(id),
  entidade      text not null,
  chave_externa text not null,
  registro_id   uuid not null,
  criado_em     timestamptz not null default now(),
  criado_por    uuid,
  atualizado_em timestamptz,
  atualizado_por uuid,
  constraint importacao_referencia_uk unique (unidade_id, entidade, chave_externa)
);

comment on table public.importacao_referencia is
  'Chave externa do arquivo → linha criada, para as entidades SEM chave natural. Hoje só movimento_estoque: as outras dezesseis se reconhecem por unique própria (material por método+código, aluno por codigo_sgf, bloco por sala+dia+hora…) e não precisam de mapa. É o que torna a segunda importação do mesmo snapshot um UPDATE em vez de uma duplicata — a pré-condição (3) do card 9.7.';
comment on column public.importacao_referencia.chave_externa is
  'Vem do arquivo (campo `chave` do movimento) e é responsabilidade do card 9.2 fazê-la estável entre snapshots. Instável, o mesmo movimento entra duas vezes — e movimento_estoque é IMUTÁVEL, então a sobra não se apaga, só se estorna.';

-- -----------------------------------------------------------------------------
-- 2. Índices dos lados que a unique não cobre
-- -----------------------------------------------------------------------------
-- Mesma razão dos cards 3.3, 4.1, 4.3, 5.1, 6.1 e 8.3: uma unique só serve de
-- índice para a FK quando a coluna é a PRIMEIRA dela.
create index importacao_unidade_ix          on public.importacao (unidade_id, criado_em desc);
create index importacao_aplicado_por_ix     on public.importacao (aplicado_por);
create index importacao_ocorrencia_lote_ix  on public.importacao_ocorrencia (importacao_id, severidade);
create index importacao_referencia_reg_ix   on public.importacao_referencia (registro_id);

-- -----------------------------------------------------------------------------
-- 3. Triggers de auditoria (C3 do card 2.8)
-- -----------------------------------------------------------------------------
create trigger tg_auditoria_importacao
  before insert or update on public.importacao
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_importacao_ocorrencia
  before insert or update on public.importacao_ocorrencia
  for each row execute function public.fn_auditoria();

create trigger tg_auditoria_importacao_referencia
  before insert or update on public.importacao_referencia
  for each row execute function public.fn_auditoria();

-- -----------------------------------------------------------------------------
-- 4. fn_importacao_conjunto e fn_importacao_pode — quem importa, em UM lugar
-- -----------------------------------------------------------------------------
-- O conjunto exato que o §7 item 4 do card 2.4 deixou em aberto desde
-- 01/09/2026: «Importação (tela 13) entra com admin.ler mais os domínios do que
-- importa; o conjunto exato é do card 9.1, que sabe o que o arquivo traz».
--
-- Ele é o que o arquivo traz, código a código, e não uma permissão nova:
--
--   • `admin.ler` — é ele que faz a tela ser da DIREÇÃO e só dela. Os quatorze
--     códigos de escrita abaixo a secretaria também tem (matriz do §5), então
--     sem esta linha a tela que carrega a escola inteira abriria para ela;
--   • os quatorze de escrita — porque as funções são `invoker`: quem importa
--     escreve sob a PRÓPRIA RLS, e a política de cada tabela cobra o seu código.
--     Exigi-los no topo troca um `42501` cru vindo de uma tela que fala de
--     planilha por SEM_PERMISSAO nomeando o que falta. É a mesma regra do card
--     6.5 (divergência 14 do wireframes.md §17) e a alternativa considerada era
--     `security definer`, recusada: definer nesta função é BYPASSRLS sobre
--     dezessete tabelas de negócio ao mesmo tempo, e o filtro de unidade
--     passaria a ser responsabilidade do corpo em cada um dos dezessete blocos.
--
-- CRIAR UM CÓDIGO NOVO (`admin.importar`) foi a outra alternativa, e foi
-- recusada por dois motivos: o catálogo iria a 51 e o critério 1 do marco 4.8 —
-- que está AGUARDANDO gente com o número 50 escrito nele — reprovaria por uma
-- mudança que não é do marco; e um código que só a direção tem, guardando uma
-- tela que só a direção abre, não decide nada que `admin.ler` já não decida.
create or replace function public.fn_importacao_conjunto()
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $$
  select array[
    'admin.ler',
    'materiais.criar', 'materiais.editar',
    'alunos.criar', 'alunos.editar', 'alunos.editar_trilha',
    'salas.criar', 'salas.editar', 'salas.registrar_manutencao',
    'professores.criar',
    'turmas.criar', 'turmas.alocar',
    'estoque.lancar_saida', 'estoque.ajustar', 'compras.receber'
  ]::text[];
$$;

comment on function public.fn_importacao_conjunto() is
  'O conjunto exato da rota 13 (permissoes-matriz.md §6). UMA fonte: a RLS destas três tabelas, o guarda das duas funções e o guarda de rota do app leem daqui. Duas cópias divergiriam para o lado silencioso — a tela abriria e a aplicação morreria no meio.';

create or replace function public.fn_importacao_pode()
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select not exists (
    select 1
      from unnest(public.fn_importacao_conjunto()) as c(codigo)
     where not public.tem_permissao(c.codigo));
$$;

comment on function public.fn_importacao_pode() is
  'Verdadeiro quando o usuário tem TODOS os códigos de fn_importacao_conjunto(). Usada nas políticas das três tabelas de importação. Quem chama função responde SEM_PERMISSAO nomeando o código que falta (fn_importacao_exigir); a política só diz sim ou não, que é o que política sabe dizer.';

create or replace function public.fn_importacao_exigir()
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_codigo text;
begin
  -- Ordem do array, e ela importa: `admin.ler` primeiro faz a secretaria (que
  -- tem os quatorze de escrita) receber "admin.ler" em vez do próximo da lista.
  foreach v_codigo in array public.fn_importacao_conjunto() loop
    perform public.fn_exige_permissao(v_codigo);
  end loop;
end $$;

comment on function public.fn_importacao_exigir() is
  'Cobra o conjunto da rota 13 código a código, com fn_exige_permissao — que é quem levanta SEM_PERMISSAO com o código no DETAIL (card 2.2 §12). Sem isto, faltar `estoque.lancar_saida` apareceria só na décima sétima entidade, como 42501 cru, com metade da escola já escrita e a transação prestes a voltar.';

revoke execute on function public.fn_importacao_conjunto() from public;
revoke execute on function public.fn_importacao_conjunto() from anon;
grant  execute on function public.fn_importacao_conjunto() to authenticated;
revoke execute on function public.fn_importacao_pode() from public;
revoke execute on function public.fn_importacao_pode() from anon;
grant  execute on function public.fn_importacao_pode() to authenticated;
revoke execute on function public.fn_importacao_exigir() from public;
revoke execute on function public.fn_importacao_exigir() from anon;
grant  execute on function public.fn_importacao_exigir() to authenticated;

-- -----------------------------------------------------------------------------
-- 5. RLS: as três com o mesmo guarda, e nenhuma com delete
-- -----------------------------------------------------------------------------
alter table public.importacao              enable row level security;
alter table public.importacao              force  row level security;
alter table public.importacao_ocorrencia   enable row level security;
alter table public.importacao_ocorrencia   force  row level security;
alter table public.importacao_referencia   enable row level security;
alter table public.importacao_referencia   force  row level security;

create policy importacao_sel on public.importacao
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

create policy importacao_ins on public.importacao
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

-- `update` existe para o que a própria importação escreve depois de validar e
-- de aplicar (status, totais, carimbos). Não há tela que edite lote.
create policy importacao_upd on public.importacao
  for update to authenticated
  using      (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode())
  with check (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

create policy importacao_ocorrencia_sel on public.importacao_ocorrencia
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

create policy importacao_ocorrencia_ins on public.importacao_ocorrencia
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

create policy importacao_referencia_sel on public.importacao_referencia
  for select to authenticated
  using (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

create policy importacao_referencia_ins on public.importacao_referencia
  for insert to authenticated
  with check (unidade_id = public.fn_unidade_atual() and public.fn_importacao_pode());

-- Sem `delete` em nenhuma das três, e sem `update` nas duas últimas: relatório é
-- histórico da migração, e o mapa de chave externa é o que impede a próxima
-- importação de duplicar. Apagar qualquer um dos dois é apagar a explicação de
-- como a escola entrou no sistema.

-- -----------------------------------------------------------------------------
-- 6. fn_importacao_registrar — passos 1 a 3 do §16 (recebe, valida, relata)
-- -----------------------------------------------------------------------------
-- As dezesseis verificações (V1…V16) estão em docs/importacao.md §4, e o critério
-- de ERRO × AVISO é o do §16: ERRO é o que o BANCO recusaria (referência que não
-- existe, enum fora do check, aluno inativo alocado) — aplicar seria bater no
-- trigger; AVISO é o que o banco ACEITA e uma pessoa precisa olhar (aluno sem
-- turma, previsão atípica, entrega sem saída de estoque).
create or replace function public.fn_importacao_registrar(
  p_arquivo     text,
  p_snapshot_em date,
  p_dados       jsonb
)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_id       uuid;
  v_unidade  uuid;
  v_erros    integer;
  v_entidades constant text[] := array[
    'professor','sala','pc','pc_manutencao','material','curso','curso_material',
    'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
    'turma_modular','turma_modular_modulo','turma_modular_aluno',
    'aluno_material','movimento_estoque'];
begin
  perform public.fn_importacao_exigir();

  v_unidade := public.fn_unidade_atual();

  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then
    raise exception using
      errcode = 'PT422',
      message = 'O arquivo enviado não tem o formato esperado.',
      detail  = json_build_object('codigo', 'ARQUIVO_INVALIDO',
                                  'motivo', 'raiz não é objeto')::text;
  end if;

  -- Arquivo sem NENHUMA entidade conhecida é erro de formato, não importação
  -- vazia: o caso real é o extrator do card 9.2 mudar um nome de chave e a
  -- importação responder "0 linhas aplicadas, tudo certo".
  if not exists (select 1 from unnest(v_entidades) e(nome)
                  where jsonb_typeof(p_dados -> e.nome) = 'array') then
    raise exception using
      errcode = 'PT422',
      message = 'O arquivo não traz nenhuma das entidades conhecidas.',
      detail  = json_build_object('codigo', 'ARQUIVO_INVALIDO',
                                  'motivo', 'nenhuma entidade conhecida')::text;
  end if;

  insert into public.importacao (unidade_id, arquivo, snapshot_em, dados)
  values (v_unidade, p_arquivo, coalesce(p_snapshot_em, public.fn_hoje()), p_dados)
  returning id into v_id;

  perform public.fn_importacao_validar(v_id);

  select count(*) into v_erros
    from public.importacao_ocorrencia o
   where o.importacao_id = v_id and o.severidade = 'ERRO';

  update public.importacao i
     set status = case when v_erros > 0 then 'REPROVADA' else 'VALIDADA' end,
         totais = public.fn_importacao_totais_arquivo(p_dados)
   where i.id = v_id;

  return v_id;
end $$;

comment on function public.fn_importacao_registrar(text, date, jsonb) is
  'Passos 1 a 3 do wireframes.md §16: recebe o arquivo normalizado, cria o lote, valida e devolve o id. NÃO escreve nada de negócio — depois dela o lote está VALIDADA ou REPROVADA, e o relatório está em importacao_ocorrencia. Chamar de novo com o mesmo arquivo cria OUTRO lote, de propósito: o §8 do plano exige reexecutável, e histórico de tentativa é o que explica o que mudou entre uma e outra.';

revoke execute on function public.fn_importacao_registrar(text, date, jsonb) from public;
revoke execute on function public.fn_importacao_registrar(text, date, jsonb) from anon;
grant  execute on function public.fn_importacao_registrar(text, date, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 7. fn_importacao_totais_arquivo — quantas linhas o arquivo traz por entidade
-- -----------------------------------------------------------------------------
create or replace function public.fn_importacao_totais_arquivo(p_dados jsonb)
returns jsonb
language sql
stable
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(e.nome,
                    jsonb_build_object('arquivo',
                      jsonb_array_length(p_dados -> e.nome))), '{}'::jsonb)
    from unnest(array[
      'professor','sala','pc','pc_manutencao','material','curso','curso_material',
      'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
      'turma_modular','turma_modular_modulo','turma_modular_aluno',
      'aluno_material','movimento_estoque']) e(nome)
   where jsonb_typeof(p_dados -> e.nome) = 'array';
$$;

comment on function public.fn_importacao_totais_arquivo(jsonb) is
  'Quantas linhas o arquivo traz por entidade. É a coluna "arquivo" dos totais do passo 4; as outras três (aplicadas, ignoradas, no_sistema) só existem depois de fn_importacao_aplicar.';

revoke execute on function public.fn_importacao_totais_arquivo(jsonb) from public;
revoke execute on function public.fn_importacao_totais_arquivo(jsonb) from anon;
grant  execute on function public.fn_importacao_totais_arquivo(jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 8. Três conversores tolerantes — texto do arquivo → tipo do banco, ou nulo
-- -----------------------------------------------------------------------------
-- Existem para a validação poder DIZER "esta data está errada" em vez de morrer
-- com 22007 na primeira célula torta. Sem eles, um "31/02" no arquivo derrubaria
-- a validação inteira e o relatório sairia com uma linha só — justamente o
-- contrário do que o passo 3 do §16 existe para fazer.
create or replace function public.fn_importacao_data(p_texto text)
returns date
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  if p_texto is null or btrim(p_texto) = '' then
    return null;
  end if;
  return btrim(p_texto)::date;
exception when others then
  return null;
end $$;

create or replace function public.fn_importacao_int(p_texto text)
returns integer
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  if p_texto is null or btrim(p_texto) = '' then
    return null;
  end if;
  return btrim(p_texto)::integer;
exception when others then
  return null;
end $$;

create or replace function public.fn_importacao_hora(p_texto text)
returns time
language plpgsql
immutable
set search_path = public, pg_temp
as $$
begin
  if p_texto is null or btrim(p_texto) = '' then
    return null;
  end if;
  return btrim(p_texto)::time;
exception when others then
  return null;
end $$;

comment on function public.fn_importacao_data(text) is
  'Texto do arquivo → date, ou NULO quando não converte. O nulo é ambíguo de propósito (ausente e inválido viram a mesma coisa), e é a validação que desfaz a ambiguidade: campo obrigatório vazio é CAMPO_OBRIGATORIO; campo preenchido que não converte é DATA_INVALIDA.';

revoke execute on function public.fn_importacao_data(text) from public;
revoke execute on function public.fn_importacao_data(text) from anon;
grant  execute on function public.fn_importacao_data(text) to authenticated;
revoke execute on function public.fn_importacao_int(text) from public;
revoke execute on function public.fn_importacao_int(text) from anon;
grant  execute on function public.fn_importacao_int(text) to authenticated;
revoke execute on function public.fn_importacao_hora(text) from public;
revoke execute on function public.fn_importacao_hora(text) from anon;
grant  execute on function public.fn_importacao_hora(text) to authenticated;

-- -----------------------------------------------------------------------------
-- 9. fn_importacao_validar — as dezesseis verificações (docs/importacao.md §4)
-- -----------------------------------------------------------------------------
-- ERRO é o que o BANCO recusaria (referência inexistente, enum fora do check,
-- aluno inativo alocado): aplicar bateria no trigger e a transação voltaria
-- inteira. AVISO é o que o banco ACEITA e uma pessoa precisa olhar — é a lista
-- de exceções que o card 9.3 revisa.
create or replace function public.fn_importacao_validar(p_importacao_id uuid)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade  uuid;
  v_snapshot date;
  v_dados    jsonb;
  v_d        jsonb;
  v_entidades constant text[] := array[
    'professor','sala','pc','pc_manutencao','material','curso','curso_material',
    'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
    'turma_modular','turma_modular_modulo','turma_modular_aluno',
    'aluno_material','movimento_estoque'];
begin
  select i.unidade_id, i.snapshot_em, i.dados
    into v_unidade, v_snapshot, v_dados
    from public.importacao i
   where i.id = p_importacao_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Esta importação não foi encontrada.',
      detail  = json_build_object('codigo', 'IMPORTACAO_INEXISTENTE',
                                  'importacao', p_importacao_id)::text;
  end if;

  -- V1 — estrutura. Toda entidade conhecida vira array (ausente ou torta vira
  -- vazia) para o resto da função não precisar se defender a cada consulta.
  select coalesce(jsonb_object_agg(e.nome,
           case when jsonb_typeof(v_dados -> e.nome) = 'array'
                then v_dados -> e.nome else '[]'::jsonb end), '{}'::jsonb)
    into v_d
    from unnest(v_entidades) e(nome);

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', e.nome, 'ENTIDADE_INVALIDA',
         format('A entidade "%s" veio no arquivo mas não é uma lista.', e.nome),
         jsonb_typeof(v_dados -> e.nome)
    from unnest(v_entidades) e(nome)
   where v_dados ? e.nome and jsonb_typeof(v_dados -> e.nome) <> 'array';

  -- Chave desconhecida é AVISO e não silêncio: é assim que se descobre que o
  -- extrator do card 9.2 renomeou uma aba e a importação passou por cima dela.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', k.chave, 'ENTIDADE_DESCONHECIDA',
         format('O arquivo traz "%s", que a importação não conhece — foi ignorada.', k.chave),
         null
    from jsonb_object_keys(v_dados) k(chave)
   where not (k.chave = any (v_entidades))
     and k.chave <> 'snapshot_em';

  -- V2 — campos obrigatórios, entidade a entidade.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'CAMPO_OBRIGATORIO',
         format('%s: o campo "%s" está vazio.', x.entidade, x.campo), null
    from (
      select 'professor' as entidade, e.n, 'nome' as campo, e.j ->> 'nome' as valor
        from jsonb_array_elements(v_d -> 'professor') with ordinality e(j, n)
      union all select 'sala', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all select 'sala', e.n, 'tipo', e.j ->> 'tipo'
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all select 'pc', e.n, 'identificador', e.j ->> 'identificador'
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc', e.n, 'sala', e.j ->> 'sala'
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'pc', e.j ->> 'pc'
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'material', e.n, 'codigo', e.j ->> 'codigo'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'categoria', e.j ->> 'categoria'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'material', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
      union all select 'curso', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
      union all select 'curso', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
      union all select 'combo', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
      union all select 'combo', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
      union all select 'aluno', e.n, 'codigo', e.j ->> 'codigo'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'metodo', e.j ->> 'metodo'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'nome', e.j ->> 'nome'
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'chave', e.j ->> 'chave'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'tipo', e.j ->> 'tipo'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) x
   where nullif(btrim(coalesce(x.valor, '')), '') is null;

  -- V3 — enumerações. Fora do check da coluna, o insert morreria com 23514 cru,
  -- que é o erro que o card 2.2 §1.2 proíbe em tela.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'VALOR_INVALIDO',
         format('%s: "%s" não é um valor aceito para %s (use %s).',
                x.entidade, x.valor, x.campo, x.aceitos), x.valor
    from (
      select 'sala' as entidade, e.n, 'tipo' as campo, e.j ->> 'tipo' as valor,
             'LABORATORIO ou SALA_MODULAR' as aceitos,
             (e.j ->> 'tipo') = any (array['LABORATORIO','SALA_MODULAR']) as ok
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all
      select 'pc', e.n, 'status', e.j ->> 'status',
             'OPERACIONAL, MANUTENCAO ou DESATIVADO',
             coalesce(e.j ->> 'status', 'OPERACIONAL')
               = any (array['OPERACIONAL','MANUTENCAO','DESATIVADO'])
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all
      select 'pc_manutencao', e.n, 'tipo', e.j ->> 'tipo',
             'PREVENTIVA, CORRETIVA ou CONFIGURACAO',
             coalesce(e.j ->> 'tipo', 'CORRETIVA')
               = any (array['PREVENTIVA','CORRETIVA','CONFIGURACAO'])
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all
      select 'aluno', e.n, 'status', e.j ->> 'status',
             'ATIVO, ACELERAR, STANDBY, TRANCADO, CANCELADO ou FORMADO',
             coalesce(e.j ->> 'status', 'ATIVO') = any (array['ATIVO','ACELERAR',
               'STANDBY','TRANCADO','CANCELADO','FORMADO'])
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all
      select 'bloco_aluno', e.n, 'tipo', e.j ->> 'tipo',
             'REM, PRE, REP ou NOVO',
             (e.j ->> 'tipo') = any (array['REM','PRE','REP','NOVO'])
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all
      select 'aluno_material', e.n, 'origem', e.j ->> 'origem',
             'COMBO ou MANUAL',
             coalesce(e.j ->> 'origem', 'COMBO') = any (array['COMBO','MANUAL'])
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all
      -- ESTORNO fica fora de propósito: estorno migrado seria um estorno sem
      -- movimento de origem no sistema, e movimento_estorno_ck o recusaria.
      select 'movimento_estoque', e.n, 'tipo', e.j ->> 'tipo',
             'ENTRADA, SAIDA ou AJUSTE',
             (e.j ->> 'tipo') = any (array['ENTRADA','SAIDA','AJUSTE'])
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all
      select x2.entidade, x2.n, 'metodo', x2.valor,
             'INTERATIVO, INGLES ou MODULAR',
             x2.valor = any (array['INTERATIVO','INGLES','MODULAR'])
        from (
          select 'material' as entidade, e.n, e.j ->> 'metodo' as valor
            from jsonb_array_elements(v_d -> 'material') with ordinality e(j, n)
          union all select 'curso', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'curso') with ordinality e(j, n)
          union all select 'combo', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'combo') with ordinality e(j, n)
          union all select 'aluno', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
          union all select 'bloco_horario', e.n, e.j ->> 'metodo'
            from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
        ) x2
    ) x
   where not x.ok and x.valor is not null;

  -- V4 — datas e horas preenchidas que não convertem.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'DATA_INVALIDA',
         format('%s: "%s" não é uma data válida em %s (esperado AAAA-MM-DD).',
                x.entidade, x.valor, x.campo), x.valor
    from (
      select 'aluno' as entidade, e.n, 'data_inicio' as campo, e.j ->> 'data_inicio' as valor
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno', e.n, 'prev_conclusao_curso', e.j ->> 'prev_conclusao_curso'
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'data_entrega', e.j ->> 'data_entrega'
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'data_inicio', e.j ->> 'data_inicio'
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'data_entrada', e.j ->> 'data_entrada'
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'data_inicio', e.j ->> 'data_inicio'
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'ocorrido_em', e.j ->> 'ocorrido_em'
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) x
   where nullif(btrim(coalesce(x.valor, '')), '') is not null
     and public.fn_importacao_data(x.valor) is null;

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'bloco_horario', e.n, 'DATA_INVALIDA',
         format('bloco_horario: "%s" não é uma hora válida (esperado HH:MM).',
                e.j ->> 'hora_inicio'), e.j ->> 'hora_inicio'
    from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
   where public.fn_importacao_hora(e.j ->> 'hora_inicio') is null;

  -- V5 — números fora de faixa, pela mesma razão do V3.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'VALOR_INVALIDO',
         format('%s: %s inválido em "%s".', x.entidade,
                coalesce(x.valor, '(vazio)'), x.campo), x.valor
    from (
      select 'sala' as entidade, e.n, 'capacidade_nominal' as campo,
             e.j ->> 'capacidade_nominal' as valor,
             coalesce(public.fn_importacao_int(e.j ->> 'capacidade_nominal'), 0) > 0 as ok
        from jsonb_array_elements(v_d -> 'sala') with ordinality e(j, n)
      union all
      select 'turma_modular', e.n, 'capacidade', e.j ->> 'capacidade',
             coalesce(public.fn_importacao_int(e.j ->> 'capacidade'), 0) > 0
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all
      select 'curso_material', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all
      select 'modulo', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all
      select 'combo_curso', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all
      select 'aluno_material', e.n, 'ordem', e.j ->> 'ordem',
             coalesce(public.fn_importacao_int(e.j ->> 'ordem'), 0) > 0
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all
      select 'movimento_estoque', e.n, 'quantidade', e.j ->> 'quantidade',
             coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0) <> 0
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all
      select 'bloco_horario', e.n, 'dia_semana', e.j ->> 'dia_semana',
             coalesce(public.fn_importacao_int(e.j ->> 'dia_semana'), 0) between 1 and 7
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all
      select 'bloco_aluno', e.n, 'dia_semana', e.j ->> 'dia_semana',
             coalesce(public.fn_importacao_int(e.j ->> 'dia_semana'), 0) between 1 and 7
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
    ) x
   where not x.ok;

  -- V5.1 — o sinal do movimento (movimento_sinal_ck no DDL). Chegar ao check
  -- custaria a transação inteira por um sinal trocado na planilha.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'movimento_estoque', e.n, 'VALOR_INVALIDO',
         format('movimento_estoque: %s com quantidade %s — ENTRADA é positiva e SAIDA é negativa.',
                e.j ->> 'tipo', e.j ->> 'quantidade'), e.j ->> 'quantidade'
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where public.fn_importacao_int(e.j ->> 'quantidade') is not null
     and ((e.j ->> 'tipo' = 'ENTRADA' and public.fn_importacao_int(e.j ->> 'quantidade') < 0)
       or (e.j ->> 'tipo' = 'SAIDA'   and public.fn_importacao_int(e.j ->> 'quantidade') > 0));

  -- V6 — chave duplicada DENTRO do arquivo. Sem esta, a segunda linha venceria a
  -- primeira no `on conflict do update` e a importação diria "aplicadas: 2".
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, 'CHAVE_DUPLICADA',
         format('%s: a chave "%s" aparece %s vezes no arquivo.',
                x.entidade, x.chave, x.vezes), x.chave
    from (
      select entidade, chave, count(*) as vezes
        from (
          select 'professor' as entidade, btrim(e.j ->> 'nome') as chave
            from jsonb_array_elements(v_d -> 'professor') e(j)
          union all select 'sala', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'sala') e(j)
          union all select 'pc', btrim(e.j ->> 'identificador')
            from jsonb_array_elements(v_d -> 'pc') e(j)
          union all select 'material',
                 concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'codigo'))
            from jsonb_array_elements(v_d -> 'material') e(j)
          union all select 'curso',
                 concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'nome'))
            from jsonb_array_elements(v_d -> 'curso') e(j)
          union all select 'combo', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'combo') e(j)
          union all select 'aluno', btrim(e.j ->> 'codigo')
            from jsonb_array_elements(v_d -> 'aluno') e(j)
          union all select 'bloco_horario',
                 concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                           e.j ->> 'hora_inicio')
            from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
          union all select 'turma_modular', btrim(e.j ->> 'nome')
            from jsonb_array_elements(v_d -> 'turma_modular') e(j)
          union all select 'aluno_material',
                 concat_ws('/', btrim(e.j ->> 'aluno'), e.j ->> 'metodo',
                           btrim(e.j ->> 'material'))
            from jsonb_array_elements(v_d -> 'aluno_material') e(j)
          union all select 'movimento_estoque', btrim(e.j ->> 'chave')
            from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
        ) t
       where nullif(chave, '') is not null
       group by entidade, chave
      having count(*) > 1
    ) x;

  -- V7 — referência que não resolve, nem no arquivo nem no banco.
  --
  -- Um `left join` contra a lista DISTINTA do que existe, e não um `exists`
  -- correlacionado por linha: com 4 mil movimentos e 200 materiais, o
  -- correlacionado é produto cartesiano e a validação estoura o
  -- `statement_timeout` do PostgREST antes de dizer qualquer coisa.
  --
  -- «Nem no arquivo nem no banco» é a parte que importa: numa reimportação o
  -- material já está no banco e não precisa vir de novo no arquivo, e numa
  -- carga do zero ele vem no mesmo arquivo, algumas entidades acima. Olhar só
  -- para um dos dois lados reprovaria metade das cargas legítimas.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', r.entidade, r.n, 'REFERENCIA_AUSENTE',
         format('%s: %s "%s" não existe no arquivo nem no sistema.',
                r.entidade, r.alvo, r.chave), r.chave
    from (
      select 'pc' as entidade, e.n, 'sala' as alvo, btrim(e.j ->> 'sala') as chave
        from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
      union all select 'pc_manutencao', e.n, 'pc', btrim(e.j ->> 'pc')
        from jsonb_array_elements(v_d -> 'pc_manutencao') with ordinality e(j, n)
      union all select 'curso_material', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all select 'curso_material', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'curso_material') with ordinality e(j, n)
      union all select 'modulo', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all select 'modulo', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'modulo') with ordinality e(j, n)
      union all select 'combo_curso', e.n, 'combo', btrim(e.j ->> 'combo')
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all select 'combo_curso', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'combo_curso') with ordinality e(j, n)
      union all select 'aluno', e.n, 'combo', btrim(e.j ->> 'combo')
        from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
      union all select 'bloco_horario', e.n, 'sala', btrim(e.j ->> 'sala')
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all select 'bloco_horario', e.n, 'professor', btrim(e.j ->> 'professor')
        from jsonb_array_elements(v_d -> 'bloco_horario') with ordinality e(j, n)
      union all select 'bloco_aluno', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all select 'bloco_aluno', e.n, 'bloco',
             concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                       public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'curso',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'))
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular', e.n, 'sala', btrim(e.j ->> 'sala')
        from jsonb_array_elements(v_d -> 'turma_modular') with ordinality e(j, n)
      union all select 'turma_modular_modulo', e.n, 'turma', btrim(e.j ->> 'turma')
        from jsonb_array_elements(v_d -> 'turma_modular_modulo') with ordinality e(j, n)
      union all select 'turma_modular_modulo', e.n, 'modulo',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'),
                       e.j ->> 'modulo_ordem')
        from jsonb_array_elements(v_d -> 'turma_modular_modulo') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'turma', btrim(e.j ->> 'turma')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'turma_modular_aluno', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'aluno_material', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'material',
             concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material'))
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
      union all select 'movimento_estoque', e.n, 'aluno', btrim(e.j ->> 'aluno')
        from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
    ) r
    left join (
      select distinct alvo, chave from (
        select 'professor' as alvo, btrim(e.j ->> 'nome') as chave
          from jsonb_array_elements(v_d -> 'professor') e(j)
        union all select 'professor', p.nome
          from public.professor p where p.unidade_id = v_unidade
        union all select 'sala', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'sala') e(j)
        union all select 'sala', s.nome
          from public.sala s where s.unidade_id = v_unidade
        union all select 'pc', btrim(e.j ->> 'identificador')
          from jsonb_array_elements(v_d -> 'pc') e(j)
        union all select 'pc', c.identificador
          from public.pc c where c.unidade_id = v_unidade
        union all select 'material',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'codigo'))
          from jsonb_array_elements(v_d -> 'material') e(j)
        union all select 'material', concat_ws('/', mo.codigo, m.codigo)
          from public.material m
          join public.metodo mo on mo.id = m.metodo_id
         where m.unidade_id = v_unidade
        union all select 'curso',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'nome'))
          from jsonb_array_elements(v_d -> 'curso') e(j)
        union all select 'curso', concat_ws('/', mo.codigo, c.nome)
          from public.curso c
          join public.metodo mo on mo.id = c.metodo_id
         where c.unidade_id = v_unidade
        union all select 'combo', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'combo') e(j)
        union all select 'combo', cb.nome
          from public.combo cb where cb.unidade_id = v_unidade
        union all select 'aluno', btrim(e.j ->> 'codigo')
          from jsonb_array_elements(v_d -> 'aluno') e(j)
        union all select 'aluno', a.codigo_sgf
          from public.aluno a
         where a.unidade_id = v_unidade and a.codigo_sgf is not null
        union all select 'bloco',
               concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                         public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
          from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
        union all select 'bloco',
               concat_ws('/', s.nome, b.dia_semana::text, b.hora_inicio::text)
          from public.bloco_horario b
          join public.sala s on s.id = b.sala_id
         where b.unidade_id = v_unidade
        union all select 'turma', btrim(e.j ->> 'nome')
          from jsonb_array_elements(v_d -> 'turma_modular') e(j)
        union all select 'turma', t.nome
          from public.turma_modular t where t.unidade_id = v_unidade
        union all select 'modulo',
               concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'curso'),
                         e.j ->> 'ordem')
          from jsonb_array_elements(v_d -> 'modulo') e(j)
        union all select 'modulo',
               concat_ws('/', mo.codigo, c.nome, md.ordem::text)
          from public.modulo md
          join public.curso c  on c.id = md.curso_id
          join public.metodo mo on mo.id = c.metodo_id
         where md.unidade_id = v_unidade
      ) t
    ) d on d.alvo = r.alvo and d.chave = r.chave
   where nullif(btrim(coalesce(r.chave, '')), '') is not null
     and d.chave is null;

  -- V8 — método do aluno diferente do método do bloco. É o METODO_INCOMPATIVEL
  -- de fn_bloco_aluno_admissao, antecipado para TODAS as linhas de uma vez: o
  -- trigger acusa a primeira e aborta, e a segunda aparece no upload seguinte.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'bloco_aluno', e.n, 'METODO_INCOMPATIVEL',
         format('bloco_aluno: o aluno %s é de %s e o bloco é de %s.',
                e.j ->> 'aluno', coalesce(af.metodo, ab.metodo), bl.metodo),
         e.j ->> 'aluno'
    from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
    left join (select btrim(a.j ->> 'codigo') as codigo, a.j ->> 'metodo' as metodo
                 from jsonb_array_elements(v_d -> 'aluno') a(j)) af
           on af.codigo = btrim(e.j ->> 'aluno')
    left join (select a.codigo_sgf as codigo, mo.codigo as metodo
                 from public.aluno a
                 join public.metodo mo on mo.id = a.metodo_id
                where a.unidade_id = v_unidade and a.codigo_sgf is not null) ab
           on ab.codigo = btrim(e.j ->> 'aluno')
    join (select concat_ws('/', btrim(b.j ->> 'sala'), b.j ->> 'dia_semana',
                           public.fn_importacao_hora(b.j ->> 'hora_inicio')::text) as chave,
                 b.j ->> 'metodo' as metodo
            from jsonb_array_elements(v_d -> 'bloco_horario') b(j)) bl
      on bl.chave = concat_ws('/', btrim(e.j ->> 'sala'), e.j ->> 'dia_semana',
                              public.fn_importacao_hora(e.j ->> 'hora_inicio')::text)
   where coalesce(af.metodo, ab.metodo) is not null
     and coalesce(af.metodo, ab.metodo) <> bl.metodo;

  -- V9 — aluno fora de ATIVO/ACELERAR ocupando vaga. É o ALUNO_INATIVO do mesmo
  -- trigger (e do fn_turma_modular_aluno_admissao), pela mesma razão do V8.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', x.entidade, x.n, 'ALUNO_INATIVO',
         format('%s: o aluno %s está como %s e não pode ocupar vaga.',
                x.entidade, x.aluno, s.status), x.aluno
    from (
      select 'bloco_aluno' as entidade, e.n, btrim(e.j ->> 'aluno') as aluno,
             coalesce(e.j ->> 'ativo', 'true') as ativo
        from jsonb_array_elements(v_d -> 'bloco_aluno') with ordinality e(j, n)
      union all
      select 'turma_modular_aluno', e.n, btrim(e.j ->> 'aluno'),
             coalesce(e.j ->> 'ativo', 'true')
        from jsonb_array_elements(v_d -> 'turma_modular_aluno') with ordinality e(j, n)
    ) x
    join lateral (
      select coalesce(
        (select coalesce(a.j ->> 'status', 'ATIVO')
           from jsonb_array_elements(v_d -> 'aluno') a(j)
          where btrim(a.j ->> 'codigo') = x.aluno limit 1),
        (select a.status from public.aluno a
          where a.unidade_id = v_unidade and a.codigo_sgf = x.aluno)) as status
    ) s on true
   where x.ativo <> 'false'
     and s.status is not null
     and s.status not in ('ATIVO', 'ACELERAR');

  -- V10 — saldo negativo. O comentário de v_estoque_atual.saldo diz que negativo
  -- «NÃO deveria» existir, e o critério 4 do marco 6.9 o proíbe; deixar a
  -- importação instalá-lo seria estrear o sistema violando a própria invariante.
  --
  -- ⚠️ O `not exists` sobre importacao_referencia é o que faz a SEGUNDA execução
  --    do mesmo snapshot passar: os movimentos já aplicados continuam no arquivo,
  --    mas não serão inseridos de novo — somá-los ao saldo que eles próprios
  --    formaram acusaria negativo onde não há.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'ERRO', 'movimento_estoque', 'SALDO_NEGATIVO',
         format('O material %s ficaria com saldo %s depois da importação.',
                mv.chave, coalesce(ea.saldo, 0) + mv.soma), mv.chave
    from (
      select concat_ws('/', e.j ->> 'metodo', btrim(e.j ->> 'material')) as chave,
             sum(coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0)) as soma
        from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
       where not exists (
             select 1 from public.importacao_referencia r
              where r.unidade_id = v_unidade
                and r.entidade = 'movimento_estoque'
                and r.chave_externa = btrim(e.j ->> 'chave'))
       group by 1
    ) mv
    left join (
      select concat_ws('/', mo.codigo, v.codigo) as chave, v.saldo
        from public.v_estoque_atual v
        join public.metodo mo on mo.id = v.metodo_id
       where v.unidade_id = v_unidade
    ) ea on ea.chave = mv.chave
   where coalesce(ea.saldo, 0) + mv.soma < 0;

  -- V11 — aluno sem turma. É o "20 sem turma ⚠" do wireframes.md §16 e a
  -- primeira linha da lista de exceções do card 9.3. AVISO, nunca ERRO: aluno
  -- sem turma é situação REAL da escola, e a rotina diária abre ALUNO_SEM_TURMA
  -- para ele no dia seguinte — a pendência é o destino certo, não o bloqueio.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'ALUNO_SEM_TURMA',
         format('O aluno %s (%s) não aparece em turma nenhuma no arquivo.',
                e.j ->> 'nome', e.j ->> 'codigo'), e.j ->> 'codigo'
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
   where coalesce(e.j ->> 'status', 'ATIVO') in ('ATIVO', 'ACELERAR')
     and not exists (select 1 from jsonb_array_elements(v_d -> 'bloco_aluno') b(j)
                      where btrim(b.j ->> 'aluno') = btrim(e.j ->> 'codigo'))
     and not exists (select 1 from jsonb_array_elements(v_d -> 'turma_modular_aluno') t(j)
                      where btrim(t.j ->> 'aluno') = btrim(e.j ->> 'codigo'));

  -- V12 — previsão atípica: as "3 previsões atípicas" do §16 e o "2023, 2050,
  -- vencidas" da nota do card 9.3. A borda de baixo é o SNAPSHOT, não hoje —
  -- comparar com hoje faria a mesma planilha mudar de veredito conforme o dia em
  -- que alguém a importa.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'PREVISAO_ATIPICA',
         format('O aluno %s tem previsão de conclusão em %s, fora da janela do snapshot (%s).',
                e.j ->> 'codigo',
                to_char(public.fn_importacao_data(e.j ->> 'prev_conclusao_curso'), 'DD/MM/YYYY'),
                to_char(v_snapshot, 'DD/MM/YYYY')),
         e.j ->> 'prev_conclusao_curso'
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
   where public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') is not null
     and (public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') < v_snapshot
       or public.fn_importacao_data(e.j ->> 'prev_conclusao_curso') > v_snapshot + interval '3 years');

  -- V13 — as duas metades da divergência "saídas × flag Entregue" do plano §8.
  -- Elas se conferem uma contra a outra dentro do MESMO arquivo, que é o único
  -- lugar onde as duas existem juntas.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno_material', e.n, 'ENTREGA_SEM_SAIDA',
         format('A trilha diz que o aluno %s recebeu o material %s, e não há saída de estoque correspondente.',
                e.j ->> 'aluno', e.j ->> 'material'),
         concat_ws('/', e.j ->> 'aluno', e.j ->> 'material')
    from jsonb_array_elements(v_d -> 'aluno_material') with ordinality e(j, n)
   where coalesce(e.j ->> 'entregue', 'false') = 'true'
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'movimento_estoque') m(j)
            where m.j ->> 'tipo' = 'SAIDA'
              and btrim(coalesce(m.j ->> 'aluno', '')) = btrim(e.j ->> 'aluno')
              and btrim(coalesce(m.j ->> 'material', '')) = btrim(e.j ->> 'material'));

  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'movimento_estoque', e.n, 'SAIDA_SEM_ENTREGA',
         format('Há saída do material %s para o aluno %s, e a trilha não marca a entrega.',
                e.j ->> 'material', e.j ->> 'aluno'),
         concat_ws('/', e.j ->> 'aluno', e.j ->> 'material')
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where e.j ->> 'tipo' = 'SAIDA'
     and nullif(btrim(coalesce(e.j ->> 'aluno', '')), '') is not null
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'aluno_material') t(j)
            where btrim(t.j ->> 'aluno') = btrim(e.j ->> 'aluno')
              and btrim(t.j ->> 'material') = btrim(e.j ->> 'material')
              and coalesce(t.j ->> 'entregue', 'false') = 'true');

  -- V14 — a divergência 3 do cabeçalho: pc.status derivado sem a linha que o
  -- deriva. Sem este aviso, a capacidade do bloco sobe sozinha às 03:10.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'pc', e.n, 'PC_SEM_MANUTENCAO',
         format('O PC %s vem como MANUTENCAO e não há manutenção aberta para ele — a rotina diária o devolverá a OPERACIONAL.',
                e.j ->> 'identificador'), e.j ->> 'identificador'
    from jsonb_array_elements(v_d -> 'pc') with ordinality e(j, n)
   where e.j ->> 'status' = 'MANUTENCAO'
     and not exists (
           select 1 from jsonb_array_elements(v_d -> 'pc_manutencao') m(j)
            where btrim(m.j ->> 'pc') = btrim(e.j ->> 'identificador')
              and public.fn_importacao_data(m.j ->> 'data_fim') is null);

  -- V15 — saída sem aluno. O plano §8 manda transformá-la em AJUSTE, e quem faz
  -- isso é o extrator do card 9.2; aqui ela só é registrada, porque uma SAIDA
  -- sem aluno entra no banco sem erro nenhum e some da conferência.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'movimento_estoque', e.n, 'SAIDA_SEM_ALUNO',
         format('Saída de %s do material %s sem aluno — o plano §8 manda que ela vire AJUSTE.',
                abs(coalesce(public.fn_importacao_int(e.j ->> 'quantidade'), 0)),
                e.j ->> 'material'), e.j ->> 'chave'
    from jsonb_array_elements(v_d -> 'movimento_estoque') with ordinality e(j, n)
   where e.j ->> 'tipo' = 'SAIDA'
     and nullif(btrim(coalesce(e.j ->> 'aluno', '')), '') is null;

  -- V16 — status do arquivo diferente do status no sistema. A aplicação NÃO
  -- reescreve status de aluno que já existe (ver o passo 11 de
  -- fn_importacao_aplicar), e sem este aviso a diferença sumiria: a tela diria
  -- "265 alunos aplicados" e o aluno continuaria ATIVO no sistema e TRANCADO na
  -- planilha. Mudar status é transição, e transição se faz na tela 3.
  insert into public.importacao_ocorrencia
         (unidade_id, importacao_id, severidade, entidade, linha, codigo, mensagem, valor)
  select v_unidade, p_importacao_id, 'AVISO', 'aluno', e.n, 'STATUS_DIVERGENTE',
         format('O aluno %s está %s no sistema e %s no arquivo — a importação não muda status; use a tela de Alunos.',
                e.j ->> 'codigo', a.status, coalesce(e.j ->> 'status', 'ATIVO')),
         coalesce(e.j ->> 'status', 'ATIVO')
    from jsonb_array_elements(v_d -> 'aluno') with ordinality e(j, n)
    join public.aluno a on a.unidade_id = v_unidade
                       and a.codigo_sgf = btrim(e.j ->> 'codigo')
   where a.status <> coalesce(e.j ->> 'status', 'ATIVO');
end $$;

comment on function public.fn_importacao_validar(uuid) is
  'As dezesseis verificações do passo 3 (docs/importacao.md §4). Escreve em importacao_ocorrencia e NÃO decide nada: quem transforma ERRO em recusa é fn_importacao_aplicar. Chamada por fn_importacao_registrar logo depois de criar o lote — não é RPC de tela, mas precisa de grant porque quem a chama é `invoker`.';

revoke execute on function public.fn_importacao_validar(uuid) from public;
revoke execute on function public.fn_importacao_validar(uuid) from anon;
-- Precisa do grant mesmo não sendo RPC de tela: quem a chama é
-- fn_importacao_registrar, que é `invoker` — e chamada de função dentro de outra
-- exige EXECUTE do usuário, ao contrário de função de TRIGGER, cuja permissão é
-- conferida no `create trigger` (card 3.3 (c)).
grant  execute on function public.fn_importacao_validar(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- 10. fn_importacao_total — acumulador dos totais do passo 4
-- -----------------------------------------------------------------------------
create or replace function public.fn_importacao_total(
  p_totais    jsonb,
  p_entidade  text,
  p_arquivo   integer,
  p_aplicadas integer
)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  select coalesce(p_totais, '{}'::jsonb) || jsonb_build_object(p_entidade,
           jsonb_build_object('arquivo',   coalesce(p_arquivo, 0),
                              'aplicadas', coalesce(p_aplicadas, 0),
                              'ignoradas', greatest(coalesce(p_arquivo, 0)
                                                  - coalesce(p_aplicadas, 0), 0)));
$$;

comment on function public.fn_importacao_total(jsonb, text, integer, integer) is
  'Acumula {arquivo, aplicadas, ignoradas} de uma entidade nos totais do lote. "ignoradas" é diferença, não contagem própria: linha que o arquivo traz e a aplicação não escreveu — alocação de aluno inativo filtrada, movimento que a importação anterior já gravou. Ver "no_sistema" para o número que se compara com o Dashboard da planilha.';

revoke execute on function public.fn_importacao_total(jsonb, text, integer, integer) from public;
revoke execute on function public.fn_importacao_total(jsonb, text, integer, integer) from anon;
grant  execute on function public.fn_importacao_total(jsonb, text, integer, integer) to authenticated;

-- -----------------------------------------------------------------------------
-- 11. fn_importacao_aplicar — o passo 4, numa transação só
-- -----------------------------------------------------------------------------
-- A SIMULAÇÃO ESCREVE DE VERDADE E DESFAZ. O bloco `begin … exception` do
-- PL/pgSQL abre uma SUBTRANSAÇÃO: levantar exceção dentro dele desfaz tudo o que
-- ele escreveu e devolve o controle ao handler, com a transação de fora intacta.
-- É o que permite o "dry-run primeiro" do §16 sem uma segunda implementação de
-- coisa nenhuma — o que a simulação mede é o que os TRIGGERS REAIS disseram.
--
-- O mesmo bloco serve para o erro: se um trigger recusar uma linha na décima
-- sétima entidade, tudo volta e o motivo vira ocorrência, escrita DEPOIS do
-- bloco (dentro dele seria desfeita junto). É por isso que o handler existe em
-- vez de deixar a exceção subir: exceção que sobe leva o relatório com ela.
create or replace function public.fn_importacao_aplicar(
  p_importacao_id uuid,
  p_simular       boolean default true
)
returns jsonb
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_unidade uuid;
  v_dados   jsonb;
  v_status  text;
  v_d       jsonb;
  v_totais  jsonb := '{}'::jsonb;
  v_n       integer;
  v_m       integer;
  v_estado  text;
  v_msg     text;
  v_detalhe text;
  v_codigo  text;
  v_entidades constant text[] := array[
    'professor','sala','pc','pc_manutencao','material','curso','curso_material',
    'modulo','combo','combo_curso','aluno','bloco_horario','bloco_aluno',
    'turma_modular','turma_modular_modulo','turma_modular_aluno',
    'aluno_material','movimento_estoque'];
begin
  perform public.fn_importacao_exigir();

  select i.unidade_id, i.dados, i.status
    into v_unidade, v_dados, v_status
    from public.importacao i
   where i.id = p_importacao_id;

  if v_unidade is null then
    raise exception using
      errcode = 'PT404',
      message = 'Esta importação não foi encontrada.',
      detail  = json_build_object('codigo', 'IMPORTACAO_INEXISTENTE',
                                  'importacao', p_importacao_id)::text;
  end if;

  if v_status = 'APLICADA' then
    raise exception using
      errcode = 'PT409',
      message = 'Esta importação já foi aplicada. Para reexecutar o snapshot, envie o arquivo de novo.',
      detail  = json_build_object('codigo', 'IMPORTACAO_JA_APLICADA',
                                  'importacao', p_importacao_id)::text;
  end if;

  if exists (select 1 from public.importacao_ocorrencia o
              where o.importacao_id = p_importacao_id and o.severidade = 'ERRO') then
    raise exception using
      errcode = 'PT422',
      message = 'Esta importação tem erros que precisam ser corrigidos no arquivo antes de aplicar.',
      detail  = json_build_object('codigo', 'IMPORTACAO_REPROVADA',
                                  'importacao', p_importacao_id)::text;
  end if;

  select coalesce(jsonb_object_agg(e.nome,
           case when jsonb_typeof(v_dados -> e.nome) = 'array'
                then v_dados -> e.nome else '[]'::jsonb end), '{}'::jsonb)
    into v_d
    from unnest(v_entidades) e(nome);

  begin
    -- 1. professor ------------------------------------------------------------
    insert into public.professor (unidade_id, nome, ativo)
    select v_unidade, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'professor') e(j)
        on conflict (unidade_id, nome) do update set ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'professor',
                  jsonb_array_length(v_d -> 'professor'), v_n);

    -- 2. sala -----------------------------------------------------------------
    insert into public.sala (unidade_id, nome, tipo, capacidade_nominal, ativo)
    select v_unidade, btrim(e.j ->> 'nome'), e.j ->> 'tipo',
           public.fn_importacao_int(e.j ->> 'capacidade_nominal'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'sala') e(j)
        on conflict (unidade_id, nome) do update
       set tipo = excluded.tipo,
           capacidade_nominal = excluded.capacidade_nominal,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'sala',
                  jsonb_array_length(v_d -> 'sala'), v_n);

    -- 3. pc -------------------------------------------------------------------
    insert into public.pc (unidade_id, sala_id, identificador, status, observacao)
    select v_unidade, s.id, btrim(e.j ->> 'identificador'),
           coalesce(e.j ->> 'status', 'OPERACIONAL'), e.j ->> 'observacao'
      from jsonb_array_elements(v_d -> 'pc') e(j)
      join public.sala s on s.unidade_id = v_unidade
                        and s.nome = btrim(e.j ->> 'sala')
        on conflict (unidade_id, identificador) do update
       set sala_id = excluded.sala_id,
           status  = excluded.status,
           observacao = excluded.observacao;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'pc',
                  jsonb_array_length(v_d -> 'pc'), v_n);

    -- 4. pc_manutencao --------------------------------------------------------
    -- Sem chave natural: idempotente por (pc, data_inicio), que é o que
    -- distingue duas manutenções do mesmo PC.
    insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio,
                                      data_fim, descricao)
    select v_unidade, p.id, coalesce(e.j ->> 'tipo', 'CORRETIVA'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           public.fn_importacao_data(e.j ->> 'data_fim'), e.j ->> 'descricao'
      from jsonb_array_elements(v_d -> 'pc_manutencao') e(j)
      join public.pc p on p.unidade_id = v_unidade
                      and p.identificador = btrim(e.j ->> 'pc')
     where not exists (
           select 1 from public.pc_manutencao pm
            where pm.pc_id = p.id
              and pm.data_inicio = coalesce(
                    public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()));
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'pc_manutencao',
                  jsonb_array_length(v_d -> 'pc_manutencao'), v_n);

    -- 5. material -------------------------------------------------------------
    insert into public.material (unidade_id, metodo_id, codigo, nome, categoria,
                                 estoque_minimo, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'codigo'), btrim(e.j ->> 'nome'),
           e.j ->> 'categoria',
           coalesce(public.fn_importacao_int(e.j ->> 'estoque_minimo'), 0),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'material') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade
                           and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, metodo_id, codigo) do update
       set nome = excluded.nome,
           categoria = excluded.categoria,
           estoque_minimo = excluded.estoque_minimo,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'material',
                  jsonb_array_length(v_d -> 'material'), v_n);

    -- 6. curso ----------------------------------------------------------------
    insert into public.curso (unidade_id, metodo_id, nome, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'curso') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade
                           and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, metodo_id, nome) do update set ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'curso',
                  jsonb_array_length(v_d -> 'curso'), v_n);

    -- 7. curso_material -------------------------------------------------------
    -- `on conflict` na unique NÃO deferrable (curso_material_uk); a de `ordem` é
    -- deferrable e o Postgres não a aceita para inferência — o que é bom, porque
    -- é justamente ela que precisa adiar a checagem quando a sequência muda.
    insert into public.curso_material (unidade_id, curso_id, material_id, ordem)
    select v_unidade, c.id, m.id, public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'curso_material') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
        on conflict (curso_id, material_id) do update set ordem = excluded.ordem;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'curso_material',
                  jsonb_array_length(v_d -> 'curso_material'), v_n);

    -- 8. modulo ---------------------------------------------------------------
    -- Update e insert separados: a única unique de `modulo` é (curso, ordem) e é
    -- DEFERRABLE, então não serve de alvo para `on conflict`.
    update public.modulo md
       set nome = btrim(e.j ->> 'nome'), material_id = m.id
      from jsonb_array_elements(v_d -> 'modulo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
     where md.curso_id = c.id
       and md.ordem = public.fn_importacao_int(e.j ->> 'ordem');
    get diagnostics v_n = row_count;

    insert into public.modulo (unidade_id, curso_id, material_id, nome, ordem)
    select v_unidade, c.id, m.id, btrim(e.j ->> 'nome'),
           public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'modulo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
     where not exists (select 1 from public.modulo md
                        where md.curso_id = c.id
                          and md.ordem = public.fn_importacao_int(e.j ->> 'ordem'));
    get diagnostics v_m = row_count;
    v_n := v_n + v_m;
    v_totais := public.fn_importacao_total(v_totais, 'modulo',
                  jsonb_array_length(v_d -> 'modulo'), v_n);

    -- 9. combo ----------------------------------------------------------------
    insert into public.combo (unidade_id, metodo_id, nome, ativo)
    select v_unidade, mo.id, btrim(e.j ->> 'nome'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'combo') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
        on conflict (unidade_id, nome) do update
       set ativo = excluded.ativo, metodo_id = excluded.metodo_id;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'combo',
                  jsonb_array_length(v_d -> 'combo'), v_n);

    -- 10. combo_curso ---------------------------------------------------------
    insert into public.combo_curso (unidade_id, combo_id, curso_id, ordem)
    select v_unidade, cb.id, c.id, public.fn_importacao_int(e.j ->> 'ordem')
      from jsonb_array_elements(v_d -> 'combo_curso') e(j)
      join public.combo cb  on cb.unidade_id = v_unidade
                           and cb.nome = btrim(e.j ->> 'combo')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
        on conflict (combo_id, curso_id) do update set ordem = excluded.ordem;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'combo_curso',
                  jsonb_array_length(v_d -> 'combo_curso'), v_n);

    -- 11. aluno ---------------------------------------------------------------
    -- ⚠️ `status` só entra no INSERT. No update ele fica de fora de propósito:
    --    mudar status é transição, tg_aluno_status_valida a examina e o gate de
    --    FORMADO (card 8.3) pode recusá-la — e uma importação que reprova porque
    --    um aluno se formou entre dois snapshots é uma importação que não se
    --    consegue repetir. A divergência entre arquivo e sistema vira AVISO na
    --    validação (V16), e a mudança se faz na tela, que é onde a regra mora.
    insert into public.aluno (unidade_id, codigo_sgf, nome, metodo_id, combo_id,
                              status, data_inicio, prev_conclusao_curso, observacoes)
    select v_unidade, btrim(e.j ->> 'codigo'), btrim(e.j ->> 'nome'), mo.id, cb.id,
           coalesce(e.j ->> 'status', 'ATIVO'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           public.fn_importacao_data(e.j ->> 'prev_conclusao_curso'),
           e.j ->> 'observacoes'
      from jsonb_array_elements(v_d -> 'aluno') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      left join public.combo cb on cb.unidade_id = v_unidade
                               and cb.nome = btrim(e.j ->> 'combo')
        on conflict (unidade_id, codigo_sgf) where codigo_sgf is not null do update
       set nome = excluded.nome,
           combo_id = excluded.combo_id,
           data_inicio = excluded.data_inicio,
           prev_conclusao_curso = excluded.prev_conclusao_curso,
           observacoes = excluded.observacoes;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'aluno',
                  jsonb_array_length(v_d -> 'aluno'), v_n);

    -- 12. bloco_horario -------------------------------------------------------
    insert into public.bloco_horario (unidade_id, dia_semana, hora_inicio, metodo_id,
                                      professor_id, sala_id, capacidade_override, ativo)
    select v_unidade, public.fn_importacao_int(e.j ->> 'dia_semana')::smallint,
           public.fn_importacao_hora(e.j ->> 'hora_inicio'), mo.id, pr.id, s.id,
           public.fn_importacao_int(e.j ->> 'capacidade_override'),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'bloco_horario') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.sala s    on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
      left join public.professor pr on pr.unidade_id = v_unidade
                                   and pr.nome = btrim(e.j ->> 'professor')
        on conflict (unidade_id, sala_id, dia_semana, hora_inicio) do update
       set metodo_id = excluded.metodo_id,
           professor_id = excluded.professor_id,
           capacidade_override = excluded.capacidade_override,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'bloco_horario',
                  jsonb_array_length(v_d -> 'bloco_horario'), v_n);

    -- 13. bloco_aluno ---------------------------------------------------------
    -- A capacidade NÃO é conferida aqui: quem confere é tg_bloco_aluno_admissao,
    -- e é ele quem tem a única implementação de fn_capacidade_efetiva. Bloco
    -- lotado no arquivo derruba a transação inteira e vira ocorrência com o
    -- texto do próprio trigger — que já diz quantos cabem e quantos vieram.
    insert into public.bloco_aluno (unidade_id, bloco_id, aluno_id, tipo,
                                    data_inicio_prevista)
    select v_unidade, b.id, a.id, e.j ->> 'tipo',
           public.fn_importacao_data(e.j ->> 'data_inicio_prevista')
      from jsonb_array_elements(v_d -> 'bloco_aluno') e(j)
      join public.aluno a on a.unidade_id = v_unidade
                         and a.codigo_sgf = btrim(e.j ->> 'aluno')
      join public.sala s  on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
      join public.bloco_horario b
             on b.unidade_id = v_unidade and b.sala_id = s.id
            and b.dia_semana = public.fn_importacao_int(e.j ->> 'dia_semana')::smallint
            and b.hora_inicio = public.fn_importacao_hora(e.j ->> 'hora_inicio')
     where coalesce(e.j ->> 'ativo', 'true') <> 'false'
        on conflict (bloco_id, aluno_id) where ativo do update
       set tipo = excluded.tipo,
           data_inicio_prevista = excluded.data_inicio_prevista;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'bloco_aluno',
                  jsonb_array_length(v_d -> 'bloco_aluno'), v_n);

    -- 14. turma_modular -------------------------------------------------------
    insert into public.turma_modular (unidade_id, curso_id, nome, sala_id,
                                      capacidade, data_inicio, ativo)
    select v_unidade, c.id, btrim(e.j ->> 'nome'), s.id,
           public.fn_importacao_int(e.j ->> 'capacidade'),
           coalesce(public.fn_importacao_data(e.j ->> 'data_inicio'), public.fn_hoje()),
           coalesce(e.j ->> 'ativo', 'true') <> 'false'
      from jsonb_array_elements(v_d -> 'turma_modular') e(j)
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.sala s    on s.unidade_id = v_unidade and s.nome = btrim(e.j ->> 'sala')
        on conflict (unidade_id, nome) do update
       set curso_id = excluded.curso_id,
           sala_id = excluded.sala_id,
           capacidade = excluded.capacidade,
           data_inicio = excluded.data_inicio,
           ativo = excluded.ativo;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular',
                  jsonb_array_length(v_d -> 'turma_modular'), v_n);

    -- 15. turma_modular_modulo ------------------------------------------------
    insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id,
                                             data_inicio, prev_conclusao, concluido)
    select v_unidade, t.id, md.id,
           public.fn_importacao_data(e.j ->> 'data_inicio'),
           public.fn_importacao_data(e.j ->> 'prev_conclusao'),
           coalesce(e.j ->> 'concluido', 'false') = 'true'
      from jsonb_array_elements(v_d -> 'turma_modular_modulo') e(j)
      join public.turma_modular t on t.unidade_id = v_unidade
                                 and t.nome = btrim(e.j ->> 'turma')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.curso c   on c.unidade_id = v_unidade and c.metodo_id = mo.id
                           and c.nome = btrim(e.j ->> 'curso')
      join public.modulo md on md.curso_id = c.id
                           and md.ordem = public.fn_importacao_int(e.j ->> 'modulo_ordem')
        on conflict (turma_id, modulo_id) do update
       set data_inicio = excluded.data_inicio,
           prev_conclusao = excluded.prev_conclusao,
           concluido = excluded.concluido;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular_modulo',
                  jsonb_array_length(v_d -> 'turma_modular_modulo'), v_n);

    -- 16. turma_modular_aluno -------------------------------------------------
    insert into public.turma_modular_aluno (unidade_id, turma_id, aluno_id, data_entrada)
    select v_unidade, t.id, a.id,
           coalesce(public.fn_importacao_data(e.j ->> 'data_entrada'), public.fn_hoje())
      from jsonb_array_elements(v_d -> 'turma_modular_aluno') e(j)
      join public.turma_modular t on t.unidade_id = v_unidade
                                 and t.nome = btrim(e.j ->> 'turma')
      join public.aluno a on a.unidade_id = v_unidade
                        and a.codigo_sgf = btrim(e.j ->> 'aluno')
     where coalesce(e.j ->> 'ativo', 'true') <> 'false'
        on conflict (turma_id, aluno_id) where ativo do update
       set data_entrada = excluded.data_entrada;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'turma_modular_aluno',
                  jsonb_array_length(v_d -> 'turma_modular_aluno'), v_n);

    -- 17. aluno_material ------------------------------------------------------
    -- ⚠️ A trilha do aluno com combo JÁ NASCEU no passo 11: tg_aluno_trilha_inicial
    --    chama fn_trilha_gerar no insert do aluno. O que o arquivo traz aqui é o
    --    ESTADO DE ENTREGA dessas linhas (e as manuais que a planilha tiver), e é
    --    por isso que este passo é um `update` na maioria das vezes. Regerar a
    --    trilha aqui seria a segunda implementação de combo → curso → material.
    insert into public.aluno_material (unidade_id, aluno_id, material_id, ordem,
                                       origem, entregue, data_entrega)
    select v_unidade, a.id, m.id, public.fn_importacao_int(e.j ->> 'ordem'),
           coalesce(e.j ->> 'origem', 'COMBO'),
           coalesce(e.j ->> 'entregue', 'false') = 'true',
           case when coalesce(e.j ->> 'entregue', 'false') = 'true'
                then coalesce(public.fn_importacao_data(e.j ->> 'data_entrega'),
                              public.fn_hoje())
                else null end
      from jsonb_array_elements(v_d -> 'aluno_material') e(j)
      join public.aluno a   on a.unidade_id = v_unidade
                          and a.codigo_sgf = btrim(e.j ->> 'aluno')
      join public.metodo mo on mo.unidade_id = v_unidade and mo.codigo = e.j ->> 'metodo'
      join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                            and m.codigo = btrim(e.j ->> 'material')
        on conflict (aluno_id, material_id) do update
       set ordem = excluded.ordem,
           origem = excluded.origem,
           entregue = excluded.entregue,
           data_entrega = excluded.data_entrega;
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'aluno_material',
                  jsonb_array_length(v_d -> 'aluno_material'), v_n);

    -- 18. movimento_estoque ---------------------------------------------------
    -- A única entidade sem chave natural, e a única IMUTÁVEL: importar duas vezes
    -- não se corrige com update, só com estorno. Daí o mapa importacao_referencia
    -- e o `id` gerado no SELECT — é o que permite gravar chave → linha sem
    -- precisar que o `returning` devolva uma coluna que a tabela não tem.
    with novos as (
      select gen_random_uuid() as id,
             btrim(e.j ->> 'chave') as chave,
             e.j as item
        from jsonb_array_elements(v_d -> 'movimento_estoque') e(j)
       where not exists (
             select 1 from public.importacao_referencia r
              where r.unidade_id = v_unidade
                and r.entidade = 'movimento_estoque'
                and r.chave_externa = btrim(e.j ->> 'chave'))
    ),
    gravados as (
      insert into public.movimento_estoque (id, unidade_id, material_id, tipo,
                                            quantidade, ocorrido_em, aluno_id, observacao)
      select n.id, v_unidade, m.id, n.item ->> 'tipo',
             public.fn_importacao_int(n.item ->> 'quantidade'),
             coalesce(public.fn_importacao_data(n.item ->> 'ocorrido_em'),
                      public.fn_hoje())::timestamptz,
             a.id, n.item ->> 'observacao'
        from novos n
        join public.metodo mo on mo.unidade_id = v_unidade
                             and mo.codigo = n.item ->> 'metodo'
        join public.material m on m.unidade_id = v_unidade and m.metodo_id = mo.id
                              and m.codigo = btrim(n.item ->> 'material')
        left join public.aluno a on a.unidade_id = v_unidade
                                and a.codigo_sgf = nullif(btrim(coalesce(n.item ->> 'aluno', '')), '')
      returning id
    )
    insert into public.importacao_referencia (unidade_id, entidade, chave_externa, registro_id)
    select v_unidade, 'movimento_estoque', n.chave, n.id
      from novos n
     where n.id in (select id from gravados);
    get diagnostics v_n = row_count;
    v_totais := public.fn_importacao_total(v_totais, 'movimento_estoque',
                  jsonb_array_length(v_d -> 'movimento_estoque'), v_n);

    -- O número que se compara com o Dashboard da planilha (card 9.4). Vem depois
    -- de tudo escrito, e conta o que EXISTE — não o que este lote aplicou.
    v_totais := v_totais || jsonb_build_object('no_sistema', jsonb_build_object(
      'professor',           (select count(*) from public.professor           where unidade_id = v_unidade),
      'sala',                (select count(*) from public.sala                where unidade_id = v_unidade),
      'pc',                  (select count(*) from public.pc                  where unidade_id = v_unidade),
      'pc_manutencao',       (select count(*) from public.pc_manutencao       where unidade_id = v_unidade),
      'material',            (select count(*) from public.material            where unidade_id = v_unidade),
      'curso',               (select count(*) from public.curso               where unidade_id = v_unidade),
      'curso_material',      (select count(*) from public.curso_material      where unidade_id = v_unidade),
      'modulo',              (select count(*) from public.modulo              where unidade_id = v_unidade),
      'combo',               (select count(*) from public.combo               where unidade_id = v_unidade),
      'combo_curso',         (select count(*) from public.combo_curso         where unidade_id = v_unidade),
      'aluno',               (select count(*) from public.aluno               where unidade_id = v_unidade),
      'bloco_horario',       (select count(*) from public.bloco_horario       where unidade_id = v_unidade),
      'bloco_aluno',         (select count(*) from public.bloco_aluno         where unidade_id = v_unidade and ativo),
      'turma_modular',       (select count(*) from public.turma_modular       where unidade_id = v_unidade),
      'turma_modular_modulo',(select count(*) from public.turma_modular_modulo where unidade_id = v_unidade),
      'turma_modular_aluno', (select count(*) from public.turma_modular_aluno where unidade_id = v_unidade and ativo),
      'aluno_material',      (select count(*) from public.aluno_material      where unidade_id = v_unidade),
      'movimento_estoque',   (select count(*) from public.movimento_estoque   where unidade_id = v_unidade)));

    if p_simular then
      -- Não é erro: é o único jeito de desfazer o que a subtransação escreveu
      -- levando o resultado junto. O `detail` volta no handler abaixo.
      raise exception using
        errcode = 'PT299',
        message = 'simulação concluída',
        detail  = v_totais::text;
    end if;

  exception
    when sqlstate 'PT299' then
      get stacked diagnostics v_detalhe = pg_exception_detail;
      v_totais := v_detalhe::jsonb;
      v_estado := 'SIMULADA';

    when others then
      get stacked diagnostics v_estado  = returned_sqlstate,
                              v_msg     = message_text,
                              v_detalhe = pg_exception_detail;
      -- O `codigo` do DETAIL é o contrato do card 2.2 §12; nem todo erro tem um
      -- (violação de check vem sem), e aí fica o SQLSTATE, que é o que se manda
      -- ao suporte.
      begin
        v_codigo := coalesce(v_detalhe::jsonb ->> 'codigo', v_estado);
      exception when others then
        v_codigo := v_estado;
      end;
      v_estado := 'FALHOU';
  end;

  if v_estado = 'FALHOU' then
    insert into public.importacao_ocorrencia
           (unidade_id, importacao_id, severidade, entidade, codigo, mensagem, valor)
    values (v_unidade, p_importacao_id, 'ERRO', 'importacao', v_codigo,
            format('O banco recusou uma linha e a importação inteira foi desfeita: %s', v_msg),
            v_detalhe);

    update public.importacao i
       set status = 'FALHOU'
     where i.id = p_importacao_id;

    return jsonb_build_object('status', 'FALHOU', 'codigo', v_codigo,
                              'mensagem', v_msg);
  end if;

  if p_simular then
    update public.importacao i
       set simulado_em = now(), totais = v_totais
     where i.id = p_importacao_id;
    return jsonb_build_object('status', 'SIMULADA', 'totais', v_totais);
  end if;

  update public.importacao i
     set status = 'APLICADA',
         totais = v_totais,
         aplicado_em = now(),
         aplicado_por = (select u.id from public.usuario u where u.id = auth.uid())
   where i.id = p_importacao_id;

  return jsonb_build_object('status', 'APLICADA', 'totais', v_totais);
end $$;

comment on function public.fn_importacao_aplicar(uuid, boolean) is
  'O passo 4 do wireframes.md §16, numa transação só. p_simular (o padrão) escreve tudo e DESFAZ por subtransação, devolvendo os totais que os triggers reais produziram; p_simular = false aplica. Recusa lote REPROVADO (IMPORTACAO_REPROVADA) e lote já aplicado (IMPORTACAO_JA_APLICADA). Erro do banco não sobe: vira ocorrência, o lote fica FALHOU e nada foi escrito.';

revoke execute on function public.fn_importacao_aplicar(uuid, boolean) from public;
revoke execute on function public.fn_importacao_aplicar(uuid, boolean) from anon;
grant  execute on function public.fn_importacao_aplicar(uuid, boolean) to authenticated;

-- -----------------------------------------------------------------------------
-- 12. As duas views de leitura da tela (views-leitura.md §12.1)
-- -----------------------------------------------------------------------------
create view public.v_importacao with (security_invoker = on) as
select i.id,
       i.unidade_id,
       i.arquivo,
       i.snapshot_em,
       i.status,
       i.totais,
       i.simulado_em,
       i.aplicado_em,
       i.criado_em,
       u.nome as aplicado_por_nome,
       (select count(*) from public.importacao_ocorrencia o
         where o.importacao_id = i.id and o.severidade = 'ERRO')::integer  as erros,
       (select count(*) from public.importacao_ocorrencia o
         where o.importacao_id = i.id and o.severidade = 'AVISO')::integer as avisos
  from public.importacao i
  left join public.usuario u on u.id = i.aplicado_por;

comment on view public.v_importacao is
  'Lote de importação com as duas contagens do passo 3 (erros e avisos) e o nome de quem aplicou. NÃO devolve a coluna `dados`: o arquivo inteiro numa lista de lotes seriam megabytes por linha, e quem precisa dele lê a tabela. `left join` em usuario porque lote não aplicado não tem autor — e nulo ali é "ainda não foi aplicado", não falta de dado.';

create view public.v_importacao_ocorrencia with (security_invoker = on) as
select o.id,
       o.unidade_id,
       o.importacao_id,
       o.severidade,
       o.entidade,
       o.linha,
       o.codigo,
       o.mensagem,
       o.valor,
       o.criado_em
  from public.importacao_ocorrencia o;

comment on view public.v_importacao_ocorrencia is
  'O relatório do passo 3, uma linha por ocorrência. Existe como view (e não leitura direta da tabela) pelo mesmo motivo das outras onze do card 2.3: a tela lê contrato, não tabela — e o dia em que a ocorrência ganhar coluna, a tela não muda.';
