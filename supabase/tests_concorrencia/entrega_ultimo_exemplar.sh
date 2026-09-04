#!/usr/bin/env bash
# =============================================================================
# Entrega simultânea do último exemplar — card 6.3
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/estrategia-testes.md §7
#
# O que se mede: dois monitores registram a entrega da MESMA apostila, ao mesmo
# tempo, quando resta UM exemplar. Sem o `pg_advisory_xact_lock` do card 2.2 §6.2
# as duas transações leem saldo 1 — em `read committed` nenhuma enxerga a linha
# ainda não commitada da outra — e gravam SAIDA −1 cada uma: o saldo fecha em −1
# e dois alunos recebem um livro que só existia uma vez.
#
# NENHUMA constraint pega isso: saldo é regra de AGREGADO, não de linha. O
# `movimento_sinal_ck` continua satisfeito (SAIDA < 0 nas duas), a
# `aluno_material_uk` também (alunos diferentes), e `v_estoque_atual` passaria a
# mostrar −1 sem que nada tivesse errado sozinho.
#
# Por que fora do pgTAP: aquela suíte roda numa conexão só, então o `select` que
# lê o saldo e o `insert` que grava a saída acontecem na mesma transação e a
# corrida não existe. O teste C13 (asserção de que a chamada do lock não sumiu)
# mora no arquivo 052 e é o guarda-chuva barato; este aqui é a prova.
#
# A asserção é por SALDO e por CONTAGEM, não por tempo: sem o lock as duas passam
# e o teste tem de reprovar por −1 ≠ 0, e não travar o CI para sempre. O
# `statement_timeout` de 10 s existe só para que uma espera patológica vire
# vermelho em vez de pendurar a execução.
#
# Roda a partir da RAIZ do repositório, contra o stack local (`supabase start`).
# Limpa o que criou — e aqui a limpeza é mais cara do que no irmão
# `admissao_ultima_vaga.sh`, pela razão explicada na seção "limpar".
# =============================================================================
set -uo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Mesma escada do `admissao_ultima_vaga.sh`: o cliente `psql` existe no runner do
# GitHub e pode não existir na máquina de quem desenvolve (é o caso do Windows).
# O container do stack local sempre tem um. Teste que só roda no CI é teste que
# ninguém roda antes de abrir o PR.
if command -v psql >/dev/null 2>&1; then
  psql_exec() { psql "$DB_URL" -X -q -v ON_ERROR_STOP=0 -f "$1" 2>&1; }
else
  PROJETO="$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' supabase/config.toml | head -1)"
  CONTAINER="supabase_db_${PROJETO}"
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERRO: sem psql no PATH e sem o container ${CONTAINER}."
    echo "      Suba o stack local com \`supabase start\` ou instale o cliente psql."
    exit 1
  fi
  psql_exec() {
    docker exec -i "$CONTAINER" \
      psql "postgresql://postgres:postgres@127.0.0.1:5432/postgres" \
      -X -q -v ON_ERROR_STOP=0 -f - < "$1" 2>&1
  }
fi

# O material e os dois alunos vêm da escola-fixture (card 3.4.5, camada
# `trilha_estoque`) e são escolhidos por CHAVE NATURAL, nunca por `limit`
# (docs/estrategia-testes.md §11). Sem acento nenhum de propósito: o SQL atravessa
# shell, docker exec e psql, e uma camada com encoding diferente transformaria
# "Informática" num `where` que não casa com nada — e o teste passaria por não
# achar o material.
#   • material: INTERATIVO 03, o do saldo 1 (seed §8, escolha (b))
#   • alunos: codigo_sgf 3001 (Ana Paula) e 3002 (Bruno), os dois com 01 e 02
#     entregues e o 03 como PRÓXIMO — e sem nenhum outro item pendente, então
#     quem perde a corrida cai em BLOQUEADA_SEM_ESTOQUE
#
# O contexto de rotina (card 2.2 §2.2) é o mesmo que o irmão usa, e pela mesma
# razão: sem sessão não há `auth.uid()`, e `fn_registrar_entrega` exige
# `estoque.lancar_saida` — dentro do contexto `tem_permissao` responde verdadeiro
# e `fn_unidade_atual` sai da GUC, que é o que `fn_pendencia_abrir` precisa.
CONTEXTO="$(cat <<'SQL'
set statement_timeout = '10s';
set app.rotina = 'on';
select set_config('app.rotina_unidade',
                  (select id::text from public.unidade where codigo = 'ESCOLA_A'),
                  false);
SQL
)"

ALVO="$(cat <<'SQL'
create temporary view alvo as
  select (select m.id from public.material m
            join public.metodo me on me.id = m.metodo_id
           where m.unidade_id = current_setting('app.rotina_unidade')::uuid
             and me.codigo = 'INTERATIVO' and m.codigo = '03')  as material,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '3001')                         as aluno_a,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '3002')                         as aluno_b;
SQL
)"

# A marca que identifica o que ESTE script criou. `observacao` é parâmetro de
# fn_registrar_entrega, então a marca entra pela porta da frente — nada aqui
# escreve em movimento_estoque por fora da função.
MARCA='teste de concorrencia 6.3'

saldo() {
  cat > "$TMP/saldo.sql" <<SQL
${CONTEXTO}
${ALVO}
select public.fn_saldo_material(alvo.material) from alvo;
SQL
  psql_exec "$TMP/saldo.sql" | tr -d ' \r' | grep -E '^-?[0-9]+$' | head -1
}

# ---------------------------------------------------------------------------
# A limpeza é mais cara do que a do irmão, e a diferença é o assunto do card:
# `movimento_estoque` é IMUTÁVEL, e `tg_movimento_imutavel` (card 6.1) recusa
# DELETE inclusive para quem tem BYPASSRLS — que é justamente o ponto dele. Um
# `delete` direto morreria em PT409 / MOVIMENTO_IMUTAVEL e a limpeza falharia em
# silêncio (`ON_ERROR_STOP=0`), deixando a fixture com o saldo errado para a
# próxima execução da suíte pgTAP na MESMA máquina — que é exatamente o que
# alguém faz depois de rodar este script.
#
# Estornar em vez de apagar não serve aqui: o estorno é o comportamento em teste
# no arquivo 052 e deixaria DUAS linhas onde a fixture espera zero. A saída é
# desligar o trigger pelo tempo do `delete`, no banco local descartável, e dizer
# em voz alta que é isto que está acontecendo.
# ---------------------------------------------------------------------------
limpar() {
  cat > "$TMP/limpar.sql" <<SQL
${CONTEXTO}
${ALVO}

update public.aluno_material am
   set entregue = false, data_entrega = null, movimento_estoque_id = null
  from alvo
 where am.material_id = alvo.material
   and am.aluno_id in (alvo.aluno_a, alvo.aluno_b);

alter table public.movimento_estoque disable trigger tg_movimento_imutavel;
delete from public.movimento_estoque mv where mv.observacao = '${MARCA}';
alter table public.movimento_estoque enable trigger tg_movimento_imutavel;

delete from public.pendencia p
 using alvo
 where p.chave_dedup in ('COMPRA_SEM_ESTOQUE:' || alvo.aluno_a::text,
                         'COMPRA_SEM_ESTOQUE:' || alvo.aluno_b::text,
                         'ULTIMO_LIVRO:'       || alvo.aluno_a::text,
                         'ULTIMO_LIVRO:'       || alvo.aluno_b::text,
                         'ESTOQUE_ZERO:'       || alvo.material::text);
SQL
  psql_exec "$TMP/limpar.sql" >/dev/null
}

falhar() { echo "REPROVADO: $*"; limpar; exit 1; }

# ---------------------------------------------------------------------------
# Pré-condição: o cenário é UM exemplar. Sem esta conferência, um material com
# folga faria as duas entregas passarem e o teste ficaria verde sem medir nada.
# ---------------------------------------------------------------------------
limpar
ANTES="$(saldo)"
if [ "$ANTES" != "1" ]; then
  echo "REPROVADO: INTERATIVO 03 tem saldo ${ANTES:-<vazio>}, e o cenario exige exatamente 1."
  echo "           A escola-fixture (supabase/seed.sql, camada \`trilha_estoque\`) mudou, ou o"
  echo "           stack local esta com dados de outra execucao — \`supabase db reset\`."
  exit 1
fi

# ---------------------------------------------------------------------------
# A corrida. A segura o lock por 3 s; B entra 1 s depois e fica esperando. Sem o
# lock, B não espera nada e as duas gravam.
# ---------------------------------------------------------------------------
cat > "$TMP/sessao_a.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
select (public.fn_registrar_entrega(alvo.aluno_a, null, '${MARCA}')).status from alvo;
select pg_sleep(3);
commit;
SQL

cat > "$TMP/sessao_b.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
select (public.fn_registrar_entrega(alvo.aluno_b, null, '${MARCA}')).status from alvo;
commit;
SQL

psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
PID_A=$!
sleep 1
psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
wait "$PID_A"

DEPOIS="$(saldo)"

echo "── sessao A ──"; sed 's/^/   /' "$TMP/a.log"
echo "── sessao B ──"; sed 's/^/   /' "$TMP/b.log"
echo "── saldo final: ${DEPOIS} ──"

ENTREGUES="$(cat "$TMP/a.log" "$TMP/b.log" | grep -c 'ENTREGUE')"
BLOQUEADAS="$(cat "$TMP/a.log" "$TMP/b.log" | grep -c 'BLOQUEADA_SEM_ESTOQUE')"

# ---------------------------------------------------------------------------
# As asserções, e a ordem importa: o saldo é o que denuncia a ausência do lock, e
# as outras impedem que ele passe por acaso — um saldo 0 com ZERO entregas
# também fecharia a conta, e seria o desfecho oposto ao desejado.
# ---------------------------------------------------------------------------
[ "$DEPOIS" = "0" ] || falhar "o material do ultimo exemplar fechou com saldo ${DEPOIS} — o advisory lock nao esta segurando a corrida."

[ "$ENTREGUES" = "1" ] || falhar "houve ${ENTREGUES} entrega(s) com status ENTREGUE, e o unico exemplar so pode virar UMA."

[ "$BLOQUEADAS" = "1" ] || falhar "a segunda sessao devia sair com BLOQUEADA_SEM_ESTOQUE (nenhum outro item pendente tem estoque) e saiu com ${BLOQUEADAS}."

grep -qi 'ERROR' "$TMP/a.log" "$TMP/b.log" \
  && falhar "nenhuma das duas sessoes devia ERRAR: a que perde a corrida devolve STATUS, nao excecao (decisao 2.2 (b)) — senao a pendencia de compra iria embora no rollback."

limpar
echo "OK: uma entrega ENTREGUE, uma BLOQUEADA_SEM_ESTOQUE, e o saldo fechou em 0 — nunca -1."
