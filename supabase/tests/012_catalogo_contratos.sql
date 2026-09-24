-- =============================================================================
-- C12, o lado SQL — o catálogo de códigos de erro (card 9.2,73)
-- (mapa suíte → card: docs/estrategia-testes.md §17)
--
-- O contrato do card 2.8 §10: o conjunto de `codigo` que as funções levantam no
-- DETAIL é EXATAMENTE o de `test/fixtures/codigos_erro.txt`, e todo código dele
-- tem mensagem em `app/lib/erros/catalogo_erros.dart`. Até o 9.2,73 só existia
-- o lado Dart (catalogo_erros_test, fixture ↔ catálogo do app): um código novo
-- levantado no banco e esquecido nos outros dois chegaria à tela como o texto
-- cru do Postgres — o REPROVA do marco 4.8.
--
-- O banco não lê arquivo do repositório, então o contrato fecha em dois elos:
--   • AQUI: o que as funções levantam = a lista entre as marcas abaixo;
--   • `app/test/catalogo_erros_test.dart`: a lista entre as marcas = o fixture.
-- Um código novo mexe em quatro lugares — função, esta lista, fixture e
-- catálogo do app — e os dois testes reprovam enquanto faltar um.
--
-- A extração lê o corpo das funções do schema public (`'codigo', 'X'` dentro
-- do json_build_object do DETAIL), que é a forma de levantar erro de regra no
-- projeto (card 2.2 §1.2).
-- =============================================================================

begin;
select plan(3);

create temporary table t_catalogo (codigo text primary key);
insert into t_catalogo values
-- <catalogo>
  ('ALOCACAO_INEXISTENTE'), ('ALUNO_INATIVO'), ('ALUNO_INEXISTENTE'),
  ('ALUNO_NAO_MODULAR'), ('ALUNO_SEM_COMBO'), ('ARQUIVO_INVALIDO'),
  ('BLOCO_COM_ALOCACAO'), ('BLOCO_INEXISTENTE'), ('BLOCO_LOTADO'),
  ('CERTIFICADO_INEXISTENTE'), ('COMPOSICAO_METODO_DIVERGENTE'), ('DATA_OBRIGATORIA'),
  ('DATA_PREVISTA_OBRIGATORIA'), ('EMAIL_IMUTAVEL'), ('ESTORNO_SINAL_INVALIDO'),
  ('FORMATURA_SEM_CERTIFICADO'), ('IMPORTACAO_INEXISTENTE'), ('IMPORTACAO_JA_APLICADA'),
  ('IMPORTACAO_JA_VALIDADA'), ('IMPORTACAO_REPROVADA'), ('ITEM_CERTIFICADO_INVALIDO'),
  ('ITEM_FORA_DO_PEDIDO'), ('ITEM_JA_ENTREGUE'), ('MATERIAL_FORA_DA_TRILHA'),
  ('MATERIAL_INEXISTENTE'), ('MATERIAL_JA_NA_TRILHA'), ('MATERIAL_JA_NO_PEDIDO'),
  ('METODO_INCOMPATIVEL'), ('MOTIVO_OBRIGATORIO'), ('MOVIMENTO_IMUTAVEL'),
  ('MOVIMENTO_INEXISTENTE'), ('MOVIMENTO_JA_ESTORNADO'), ('MOVIMENTO_NAO_ESTORNAVEL'),
  ('PARAMETRO_AUSENTE'), ('PC_COM_HISTORICO'), ('PC_INEXISTENTE'),
  ('PEDIDO_INEXISTENTE'), ('PEDIDO_NAO_CANCELAVEL'), ('PEDIDO_NAO_ENVIAVEL'),
  ('PEDIDO_NAO_RASCUNHO'), ('PEDIDO_NAO_RECEBIVEL'), ('PEDIDO_SEM_ITEM'),
  ('PENDENCIA_INEXISTENTE'), ('PENDENCIA_JA_RESOLVIDA'), ('QUANTIDADE_INVALIDA'),
  ('RECEBIMENTO_EXCEDE_PEDIDO'), ('REPOSICAO_INEXISTENTE'), ('REPOSICAO_NAO_PREVISTA'),
  ('REP_JA_CONTINUO'), ('REP_NAO_CONTINUO'), ('RESOLUCAO_INVALIDA'),
  ('SALDO_INSUFICIENTE'), ('SEM_PERMISSAO'), ('STATUS_CERTIFICADO_INVALIDO'),
  ('TRANSICAO_INVALIDA'), ('TRILHA_COM_ENTREGA'), ('TRILHA_EM_FIM'),
  ('TRILHA_JA_EXISTE'), ('TURMA_COM_ALUNO'), ('TURMA_INEXISTENTE'),
  ('TURMA_LOTADA'), ('TURMA_SEM_CRONOGRAMA'), ('TURMA_SEM_MODULO_CORRENTE'),
  ('USUARIO_SEM_EMAIL'), ('USUARIO_SEM_UNIDADE')
-- </catalogo>
;

create temporary view t_levantados as
  select distinct m[1] as codigo
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace,
         lateral regexp_matches(p.prosrc, '''codigo''\s*,\s*''([A-Z0-9_]+)''', 'g') m
   where n.nspname = 'public';

select cmp_ok((select count(*) from t_levantados), '>=', 50::bigint,
  'premissa: a extracao acha os codigos no corpo das funcoes (sem ela, as duas assercoes de baixo passariam vazias)');

select is(
  (select coalesce(string_agg(codigo, ', ' order by codigo), '')
     from (select codigo from t_levantados except select codigo from t_catalogo) x),
  '',
  'todo codigo levantado por funcao esta no catalogo (e, pelo teste Dart, no fixture e no app)');

select is(
  (select coalesce(string_agg(codigo, ', ' order by codigo), '')
     from (select codigo from t_catalogo except select codigo from t_levantados) x),
  '',
  'nenhum codigo do catalogo esta morto: toda entrada ainda e levantada por alguma funcao');

select * from finish();
rollback;
