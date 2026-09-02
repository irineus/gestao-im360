-- =============================================================================
-- Infraestrutura física e credenciais de PC — card 4.3
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O card é de "Schema" E de "Função de aplicação" (as duas do card 2.9), então o
-- §13 cobra as duas listas: suíte de catálogo verde com as tabelas novas (010 e
-- 011 fazem sozinhas, derivando do catálogo do Postgres) + um teste por
-- check/unique que expresse regra de negócio; e, para cada função, caminho feliz
-- com EFEITO conferido, um `codigo` por erro possível, negativo de permissão e o
-- teste de camada 2 — o caminho que contorna a função.
--
-- Aqui a camada 2 tem uma forma própria e é o achado do card: o caminho que
-- contorna não é um PATCH no PostgREST, é a **cascata de uma FK**. Ela não passa
-- pela RLS da tabela referenciadora, então apagar um PC levava junto, sem erro,
-- a manutenção registrada e o log de quem leu a senha — duas tabelas que não têm
-- política de delete para ninguém. A prova está na seção 7, nos dois mundos.
--
-- Roda com begin/rollback: nada daqui sobrevive para o próximo arquivo.
-- =============================================================================

begin;
select plan(50);

-- ===========================================================================
-- 1. A fixture chegou (camada `infra_fisica` do card 3.4.5)
-- ===========================================================================
select is(
  (select count(*)::bigint from public.sala s
     join public.unidade u on u.id = s.unidade_id where u.codigo = 'ESCOLA_A'),
  3::bigint,
  'tres salas na unidade A: dois laboratorios e uma sala modular');

select is(
  (select string_agg(distinct s.tipo, ',' order by s.tipo) from public.sala s
     join public.unidade u on u.id = s.unidade_id where u.codigo = 'ESCOLA_A'),
  'LABORATORIO,SALA_MODULAR',
  'os DOIS tipos de sala estao representados');

-- A borda que o card 5.3 vai exercitar: dez vagas, o décimo primeiro aluno
-- recusado. Fixture com nove ou doze PCs passaria sem testar lotação nenhuma.
select is(
  (select count(*)::bigint from public.pc p
     join public.sala s on s.id = p.sala_id
     join public.unidade u on u.id = p.unidade_id
    where u.codigo = 'ESCOLA_A' and s.nome = 'Laboratório 1' and p.status = 'OPERACIONAL'),
  10::bigint,
  'dez PCs OPERACIONAIS no Laboratorio 1 — a capacidade real, e a borda 10/11 do card 5.3');

-- Capacidade nominal, total de PCs e PCs operacionais são TRÊS números
-- distintos de propósito. Com os três iguais, fn_capacidade_efetiva (card 5.2)
-- passaria somando qualquer coluna.
select is(
  (select s.capacidade_nominal::text || '/' ||
          (select count(*) from public.pc p where p.sala_id = s.id)::text || '/' ||
          (select count(*) from public.pc p where p.sala_id = s.id and p.status = 'OPERACIONAL')::text
     from public.sala s
     join public.unidade u on u.id = s.unidade_id
    where u.codigo = 'ESCOLA_A' and s.nome = 'Laboratório 2'),
  '6/6/4',
  'nominal 6, seis PCs, quatro operacionais: tres numeros distintos no Laboratorio 2');

select is(
  (select count(*) filter (where m.data_fim is null)::text || ' aberta, ' ||
          count(*) filter (where m.data_fim is not null)::text || ' fechada'
     from public.pc_manutencao m
     join public.unidade u on u.id = m.unidade_id where u.codigo = 'ESCOLA_A'),
  '1 aberta, 1 fechada',
  'as duas manutencoes sao de estados opostos — aberta derruba capacidade, fechada e historico');

select is(
  (select count(*) filter (where pr.ativo)::text || '/' || count(*)::text
     from public.professor pr
     join public.unidade u on u.id = pr.unidade_id where u.codigo = 'ESCOLA_A'),
  '2/3',
  'tres professores, um inativo — o inativo prova que a grade do card 5.6 filtra por ativo');

-- Isolamento: os identificadores de PC se repetem entre as unidades. É o caso
-- que `pc_identificador_uk (unidade_id, identificador)` precisa ACEITAR, e que
-- recusaria se a unique estivesse escrita sem o unidade_id.
select is(
  (select count(*)::bigint from public.pc where identificador = 'LAB1-01'),
  2::bigint,
  'o mesmo identificador existe nas duas unidades — a unique e por unidade');

-- ===========================================================================
-- 2. Os checks que expressam regra, não digitação (§13 do card 2.8)
-- ===========================================================================
select throws_ok(
  $$insert into public.sala (unidade_id, nome, tipo, capacidade_nominal)
    values ((select id from public.unidade where codigo = 'ESCOLA_A'), '  ', 'LABORATORIO', 4)$$,
  '23514',
  null,
  'sala com nome em branco e recusada: string vazia nao e nula e passaria pelo not null');

select throws_ok(
  $$insert into public.sala (unidade_id, nome, tipo, capacidade_nominal)
    values ((select id from public.unidade where codigo = 'ESCOLA_A'), 'Sala X', 'LABORATORIO', 0)$$,
  '23514',
  null,
  'sala com capacidade nominal zero e recusada');

select throws_ok(
  $$insert into public.pc_manutencao (unidade_id, pc_id, tipo, data_inicio, data_fim)
    select u.id, p.id, 'CORRETIVA', public.fn_hoje(), public.fn_hoje() - 1
      from public.unidade u join public.pc p on p.unidade_id = u.id
     where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-04'$$,
  '23514',
  null,
  'manutencao que termina antes de comecar e recusada');

select throws_ok(
  $$insert into public.pc_manutencao (unidade_id, pc_id, tipo, pc_substituto_id)
    select u.id, p.id, 'CORRETIVA', p.id
      from public.unidade u join public.pc p on p.unidade_id = u.id
     where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-05'$$,
  '23514',
  null,
  'um PC nao pode ser substituto de si mesmo');

-- `pc_credencial_ck` não está no DDL do card 2.1 e é deste card. Sem ele, a
-- ficha do PC (card 2.9 §8) mostraria "credencial cadastrada · atualizada em
-- dd/mm" para um PC sem credencial nenhuma, e o monitor descobriria no
-- laboratório, com o diálogo abrindo vazio.
select throws_ok(
  $$update public.pc set credencial_em = now()
     where identificador = 'LAB1-06' and credencial_secret_id is null$$,
  '23514',
  null,
  'carimbo de credencial sem ponteiro para o Vault e recusado — a ficha nao pode mentir');

select throws_ok(
  $$insert into public.pc (unidade_id, sala_id, identificador, status)
    select s.unidade_id, s.id, 'LAB1-99', 'QUEBRADO'
      from public.sala s join public.unidade u on u.id = s.unidade_id
     where u.codigo = 'ESCOLA_A' and s.nome = 'Laboratório 1'$$,
  '23514',
  null,
  'status fora do conjunto fechado e recusado (text + check, nunca enum — card 2.1)');

-- ===========================================================================
-- 3. Paridade de leitura (card 2.8 §6.3) e isolamento entre unidades
-- ===========================================================================
-- A RLS reduz linhas em SILÊNCIO. "Não deu erro" não prova nada: o que prova é
-- que os quatro perfis autorizados leem a MESMA contagem, e que a da direção é
-- garantidamente > 0 (paridade de zero contra zero passa sempre).
select is(
  tests.conta_como(tests.uid('direcao@escola-a.test'), 'select id from public.pc'),
  16::bigint,
  'a direcao le os dezesseis PCs da unidade A — a contagem de referencia da paridade');

select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.pc') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis com salas.ler leem a MESMA contagem de PCs');

-- `professores.ler` também é dos quatro, e não por generosidade: sem ela o
-- `left join` de v_bloco_vagas_semana degrada para nulo e a grade fica sem
-- professor — não quebra, mente (card 2.4 §6).
select is(
  (select count(distinct n) from (
     select tests.conta_como(tests.uid(e), 'select id from public.professor') as n
       from (values ('direcao@escola-a.test'), ('pedagogico@escola-a.test'),
                    ('secretaria@escola-a.test'), ('monitor@escola-a.test')) as u(e)
   ) t)::bigint,
  1::bigint,
  'paridade: os quatro perfis leem a MESMA contagem de professores');

select is(
  tests.conta_como(tests.uid('direcao@escola-b.test'),
                   'select id from public.pc where identificador like ''LAB1-%'''),
  10::bigint,
  'a unidade B ve os seus proprios PCs, nunca os da A — dez de vinte e seis');

select is(
  tests.conta_como(tests.uid('semperfil@escola-a.test'), 'select id from public.sala'),
  0::bigint,
  'quem nao tem salas.ler le zero — a RLS reduz em silencio, nao acusa');

-- Quem NÃO tem `salas.acessar_credencial` não enxerga o log de acesso, mesmo
-- podendo cadastrar PC. É o recorte que Irineu pediu no card 2.9 §5: a
-- secretaria cadastra, não vê credencial.
select is(
  tests.conta_como(tests.uid('secretaria@escola-a.test'),
                   'select id from public.pc_credencial_acesso'),
  0::bigint,
  'a secretaria cadastra PC e NAO enxerga o log de credencial');

-- ===========================================================================
-- 4. fn_pc_credencial_gravar / fn_pc_credencial_ler — caminho feliz e EFEITOS
-- ===========================================================================
-- O monitor é quem usa isto de verdade: de pé no laboratório, com o celular.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$select public.fn_pc_credencial_gravar(
      (select id from public.pc
        where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()),
      'lab1-03@escola.exemplo', 'trocada-na-virada')$$,
  'o monitor grava a credencial do PC');

reset role;

select is(
  (select (p.credencial_secret_id is not null)::text || '/' ||
          (p.credencial_em is not null)::text || '/' ||
          (p.credencial_por = tests.uid('monitor@escola-a.test'))::text
     from public.pc p join public.unidade u on u.id = p.unidade_id
    where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-03'),
  'true/true/true',
  'efeito 1: as tres colunas de credencial andam juntas, e credencial_por e o auth.uid() de quem gravou');

-- O que fica em `pc` é ponteiro. O que fica em `vault.secrets` é TEXTO CIFRADO
-- — é o que faz o pg_dump semanal do card 3.11 carregar cifra, e não senha.
select isnt(
  (select s.secret from vault.secrets s
     join public.pc p on p.credencial_secret_id = s.id
     join public.unidade u on u.id = p.unidade_id
    where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-03'),
  '{"usuario" : "lab1-03@escola.exemplo", "senha" : "trocada-na-virada"}',
  'efeito 2: o que esta gravado no Vault e cifra, nao o par em claro');

select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is(
  (select public.fn_pc_credencial_ler(
     (select id from public.pc
       where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()))->>'usuario'),
  'lab1-03@escola.exemplo',
  'a leitura devolve o usuario gravado');

select is(
  (select public.fn_pc_credencial_ler(
     (select id from public.pc
       where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()))->>'senha'),
  'trocada-na-virada',
  'e a senha gravada — o par inteiro e UM segredo (card 2.9 §3)');

reset role;

-- Duas leituras acima, duas linhas de log. O log é PRÉ-CONDIÇÃO da leitura, não
-- efeito colateral: não existe caminho que devolva a senha sem gravar a linha.
select is(
  (select count(*)::bigint from public.pc_credencial_acesso a
     join public.pc p on p.id = a.pc_id
    where p.identificador = 'LAB1-03' and p.unidade_id = tests.unidade('ESCOLA_A')),
  2::bigint,
  'duas leituras, duas linhas de log — uma por leitura, nao uma por PC');

select is(
  (select distinct a.criado_por from public.pc_credencial_acesso a
     join public.pc p on p.id = a.pc_id
    where p.identificador = 'LAB1-03' and p.unidade_id = tests.unidade('ESCOLA_A')),
  tests.uid('monitor@escola-a.test'),
  'o log registra QUEM leu, pela auditoria padrao — sem colunas proprias que possam divergir');

-- PC sem credencial devolve null e NÃO grava log: ler a ficha de um PC que não
-- tem senha não é acesso a credencial nenhuma.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select is(
  public.fn_pc_credencial_ler(
    (select id from public.pc
      where identificador = 'LAB1-04' and unidade_id = public.fn_unidade_atual())),
  null::jsonb,
  'PC sem credencial devolve null');

reset role;

select is(
  (select count(*)::bigint from public.pc_credencial_acesso a
     join public.pc p on p.id = a.pc_id
    where p.identificador = 'LAB1-04' and p.unidade_id = tests.unidade('ESCOLA_A')),
  0::bigint,
  'e nao grava log: nao houve credencial a proteger');

-- ===========================================================================
-- 5. Os negativos — e a metade que importa é a SEGUNDA
-- ===========================================================================
select is(
  tests.codigo_do_erro(
    $$select public.fn_pc_credencial_ler(
        (select id from public.pc
          where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()))$$,
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'a secretaria nao le credencial, mesmo cadastrando o PC');

select is(
  (select count(*)::bigint from public.pc_credencial_acesso a
     where a.criado_por = tests.uid('secretaria@escola-a.test')),
  0::bigint,
  'e a tentativa recusada NAO deixa linha no log — permissao barra antes de tudo');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pc_credencial_gravar(
        (select id from public.pc
          where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()),
        'x@y.z', 'qualquer')$$,
    tests.uid('secretaria@escola-a.test')),
  'SEM_PERMISSAO',
  'um codigo cobre ler E gravar: quem grava a senha esta digitando a senha');

-- PC de outra unidade responde o MESMO que PC inexistente: quem não pode ver
-- não descobre que existe (card 2.9 §4).
select is(
  tests.codigo_do_erro(
    $$select public.fn_pc_credencial_ler(
        (select p.id from public.pc p
           join public.unidade u on u.id = p.unidade_id
          where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-03'))$$,
    tests.uid('direcao@escola-b.test')),
  'PC_INEXISTENTE',
  'PC de outra unidade responde PC_INEXISTENTE, e nao "sem permissao"');

select is(
  tests.codigo_do_erro(
    $$select public.fn_pc_credencial_ler('00000000-0000-0000-0000-000000000000'::uuid)$$,
    tests.uid('monitor@escola-a.test')),
  'PC_INEXISTENTE',
  'PC que nao existe responde o mesmo codigo — os dois casos sao indistinguiveis de fora, de proposito');

select is(
  (select count(*)::bigint from public.pc_credencial_acesso a
     where a.criado_por = tests.uid('direcao@escola-b.test')),
  0::bigint,
  'e a tentativa de outra unidade tambem nao deixa linha');

-- ===========================================================================
-- 6. Rotação e limpeza
-- ===========================================================================
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$select public.fn_pc_credencial_gravar(
      (select id from public.pc
        where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()),
      'lab1-03@escola.exemplo', 'rotacionada')$$,
  'rotacionar a senha do mesmo PC');

select is(
  (select public.fn_pc_credencial_ler(
     (select id from public.pc
       where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()))->>'senha'),
  'rotacionada',
  'a rotacao substitui o segredo no lugar — sem criar um segundo');

reset role;

select is(
  (select count(*)::bigint from vault.secrets s
     join public.pc p on p.credencial_secret_id = s.id
     join public.unidade u on u.id = p.unidade_id
    where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-03'),
  1::bigint,
  'um segredo por PC: rotacionar nao deixa o anterior vivo no Vault');

-- Limpar: p_senha nula apaga o registro no Vault E o ponteiro. Deixar o segredo
-- com o ponteiro nulo seria uma senha viva que ninguém mais alcança nem apaga.
select tests.autenticar(tests.uid('monitor@escola-a.test'));

select lives_ok(
  $$select public.fn_pc_credencial_gravar(
      (select id from public.pc
        where identificador = 'LAB1-03' and unidade_id = public.fn_unidade_atual()),
      null, null)$$,
  'limpar a credencial do PC');

reset role;

select is(
  (select (p.credencial_secret_id is null)::text || '/' ||
          (p.credencial_em is null)::text || '/' || (p.credencial_por is null)::text
     from public.pc p join public.unidade u on u.id = p.unidade_id
    where u.codigo = 'ESCOLA_A' and p.identificador = 'LAB1-03'),
  'true/true/true',
  'limpar zera as tres colunas juntas — o check pc_credencial_ck nao aceitaria meio caminho');

-- ===========================================================================
-- 7. A guarda de exclusão e os DOIS MUNDOS (o achado do card)
-- ===========================================================================
-- LAB1-01 tem manutenção fechada; LAB1-02 não tem histórico nenhum.
select is(
  tests.codigo_do_erro(
    $$delete from public.pc
       where identificador = 'LAB1-01' and unidade_id = public.fn_unidade_atual()$$,
    tests.uid('direcao@escola-a.test')),
  'PC_COM_HISTORICO',
  'PC com manutencao registrada nao pode ser apagado — "excluir sem historico" vira estrutura');

select tests.autenticar(tests.uid('direcao@escola-a.test'));

select lives_ok(
  $$delete from public.pc
     where identificador = 'LAB1-02' and unidade_id = public.fn_unidade_atual()$$,
  'PC sem historico continua apagavel — a guarda nao esvazia salas.excluir');

reset role;

select is(
  (select count(*)::bigint from public.pc
    where identificador = 'LAB1-02' and unidade_id = tests.unidade('ESCOLA_A')),
  0::bigint,
  'e some de verdade');

-- CONTRAPROVA: o mundo sem a guarda. O trigger cai dentro desta transação e
-- volta no rollback. Sem ele, apagar um PC leva junto a manutenção e o log de
-- credencial — em SILÊNCIO, e apesar de as duas tabelas não terem política de
-- delete para ninguém: a ação em cascata de uma FK não passa pela RLS da tabela
-- referenciadora. Guarda que nunca foi vista fazendo diferença é decoração.
select is(
  (select count(*)::bigint from public.pc_manutencao m
     join public.pc p on p.id = m.pc_id
    where p.identificador = 'LAB1-01' and p.unidade_id = tests.unidade('ESCOLA_A')),
  1::bigint,
  'antes da contraprova, LAB1-01 tem a sua manutencao');

drop trigger tg_pc_exclusao_valida on public.pc;

select tests.autenticar(tests.uid('direcao@escola-a.test'));
delete from public.pc where identificador = 'LAB1-01' and unidade_id = public.fn_unidade_atual();
reset role;

select is(
  (select count(*)::bigint from public.pc_manutencao m
     where m.pc_id not in (select id from public.pc)),
  0::bigint,
  'SEM a guarda, a cascata apagou a manutencao junto com o PC — sem erro e sem politica de delete');

-- ===========================================================================
-- 8. O log é imutável, e a imutabilidade É a ausência de política
-- ===========================================================================
-- `update`/`delete` em tabela sem a política correspondente NÃO levantam erro:
-- devolvem zero linhas afetadas (card 3.4 (d)). É o silêncio que se escreve
-- como asserção, senão ninguém sabe que a decisão está viva.
select tests.autenticar(tests.uid('direcao@escola-a.test'));

with d as (delete from public.pc_credencial_acesso where true returning 1)
select is((select count(*) from d)::bigint, 0::bigint,
  'ninguem apaga linha do log de credencial — nem a direcao');

with u as (update public.pc_credencial_acesso set pc_id = pc_id where true returning 1)
select is((select count(*) from u)::bigint, 0::bigint,
  'e ninguem a altera');

reset role;

-- ===========================================================================
-- 9. O Vault fica fora do alcance do app (card 2.9 §3)
-- ===========================================================================
-- O schema `vault` não está nos `schemas` expostos do PostgREST
-- (supabase/config.toml §api), mas isso é configuração e configuração se muda
-- num clique. O que sustenta a política é o privilégio, e é ele que se asserta.
select ok(
  not has_schema_privilege('authenticated', 'vault', 'usage'),
  'authenticated NAO tem usage no schema vault');

select ok(
  not has_schema_privilege('anon', 'vault', 'usage'),
  'anon tambem nao');

select ok(
  not has_table_privilege('authenticated', 'vault.decrypted_secrets', 'select'),
  'e authenticated nao le vault.decrypted_secrets — a decifra so acontece dentro da funcao definer');

-- A premissa do desenho inteiro do card 2.9, que o §12 deixou em aberto PARA
-- ESTE CARD: o dono das funções enxerga a view de decifra. Se um dia deixar de
-- enxergar, o certo não é criptografia própria — é voltar a `credencial_ref`
-- com cofre externo, com o custo de adoção do §2 assumido. Esta linha é o que
-- avisa no dia.
select ok(
  has_table_privilege('postgres', 'vault.decrypted_secrets', 'select'),
  'o dono das funcoes de credencial LE vault.decrypted_secrets (premissa do card 2.9 §12)');

select * from finish();
rollback;
