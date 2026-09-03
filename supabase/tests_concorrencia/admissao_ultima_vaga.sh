#!/usr/bin/env bash
# =============================================================================
# Admissão simultânea no último lugar — card 5.3
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/estrategia-testes.md §7
#
# O que se mede: duas secretarias admitem alunos DIFERENTES no mesmo bloco de
# 9/10, ao mesmo tempo. Sem o `pg_advisory_xact_lock` do card 2.2 §4.5 as duas
# passam pela checagem de capacidade — em `read committed` nenhuma enxerga a
# linha ainda não commitada da outra — e o bloco fica com 11 alunos em 10 PCs.
# NENHUMA constraint pega isso: lotação é regra de AGREGADO, não de linha, e a
# unique parcial `bloco_aluno_ativo_uk` só proíbe o MESMO aluno duas vezes.
#
# Por que fora do pgTAP: aquela suíte roda numa conexão só, então o `select` que
# conta e o `insert` que grava acontecem na mesma transação e a corrida não
# existe. O teste C13 (asserção de que a chamada do lock não sumiu) mora no
# arquivo 042 e é o guarda-chuva barato; este aqui é a prova.
#
# A asserção é por CONTAGEM, não por tempo: sem o lock os dois passam e o teste
# tem de reprovar por 11 ≠ 10, e não travar o CI para sempre. O
# `statement_timeout` de 10 s existe só para que uma espera patológica vire
# vermelho em vez de pendurar a execução.
#
# Roda a partir da RAIZ do repositório, contra o stack local (`supabase start`).
# Limpa o que criou: é a única suíte do projeto que não roda dentro de uma
# transação com rollback — por definição, já que precisa de duas.
# =============================================================================
set -uo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# O cliente `psql` existe no runner do GitHub e pode não existir na máquina de
# quem desenvolve (é o caso do Windows). O container do stack local sempre tem
# um, e usá-lo é preferível a exigir instalação: o teste que só roda no CI é o
# teste que ninguém roda antes de abrir o PR.
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

# O bloco e os dois alunos vêm da escola-fixture (card 3.4.5, camada `turmas`) e
# são escolhidos por CHAVE NATURAL, nunca por `limit` (docs/estrategia-testes.md
# §11). Sem acento nenhum de propósito: o SQL atravessa shell, docker exec e
# psql, e uma camada com encoding diferente transformaria "Laboratório" num
# `where` que não casa com nada — e o teste passaria por não achar o bloco.
#   • bloco: ESCOLA_A, dia_semana = 2 — o de 9 alunos em 10 vagas
#   • alunos: codigo_sgf 9001 e 9002, os dois no bloco de 10, nenhum no de 9
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
  select (select b.id from public.bloco_horario b
           where b.unidade_id = current_setting('app.rotina_unidade')::uuid
             and b.dia_semana = 2)                          as bloco,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '9001')                     as aluno_a,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '9002')                     as aluno_b;
SQL
)"

ocupacao() {
  cat > "$TMP/ocupacao.sql" <<SQL
${CONTEXTO}
${ALVO}
select count(*) from public.bloco_aluno ba, alvo
 where ba.bloco_id = alvo.bloco and ba.ativo;
SQL
  psql_exec "$TMP/ocupacao.sql" | tr -d ' \r' | grep -E '^[0-9]+$' | head -1
}

limpar() {
  cat > "$TMP/limpar.sql" <<SQL
${CONTEXTO}
${ALVO}
delete from public.bloco_aluno ba
 using alvo
 where ba.bloco_id = alvo.bloco
   and ba.aluno_id in (alvo.aluno_a, alvo.aluno_b);
SQL
  psql_exec "$TMP/limpar.sql" >/dev/null
}

falhar() { echo "REPROVADO: $*"; limpar; exit 1; }

# ---------------------------------------------------------------------------
# Pré-condição: o cenário é 9 de 10. Sem esta conferência, um bloco com folga
# faria as duas admissões passarem e o teste ficaria verde sem medir nada.
# ---------------------------------------------------------------------------
limpar
ANTES="$(ocupacao)"
if [ "$ANTES" != "9" ]; then
  echo "REPROVADO: o bloco de partida tem ${ANTES:-<vazio>} alocacoes ativas, e o cenario exige 9."
  echo "           A escola-fixture (supabase/seed.sql, camada \`turmas\`) mudou, ou o stack local"
  echo "           esta com dados de outra execucao — \`supabase stop --no-backup\` e \`start\`."
  exit 1
fi

# ---------------------------------------------------------------------------
# A corrida. A segura o lock por 3 s; B entra 1 s depois e fica esperando. Sem
# o lock, B não espera nada e as duas gravam.
# ---------------------------------------------------------------------------
cat > "$TMP/sessao_a.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
select public.fn_bloco_admitir(alvo.bloco, alvo.aluno_a, 'REM') from alvo;
select pg_sleep(3);
commit;
SQL

cat > "$TMP/sessao_b.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
select public.fn_bloco_admitir(alvo.bloco, alvo.aluno_b, 'REM') from alvo;
commit;
SQL

psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
PID_A=$!
sleep 1
psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
wait "$PID_A"

DEPOIS="$(ocupacao)"

echo "── sessao A ──"; sed 's/^/   /' "$TMP/a.log"
echo "── sessao B ──"; sed 's/^/   /' "$TMP/b.log"
echo "── ocupacao final: ${DEPOIS} ──"

# ---------------------------------------------------------------------------
# As três asserções, e a ordem importa: a contagem é a que denuncia a ausência
# do lock, e as outras duas impedem que ela passe por acaso.
# ---------------------------------------------------------------------------
[ "$DEPOIS" = "10" ] || falhar "o bloco de 10 vagas ficou com ${DEPOIS} alocacoes ativas — o advisory lock nao esta segurando a corrida."

grep -q 'BLOCO_LOTADO' "$TMP/b.log" \
  || falhar "a segunda sessao nao recebeu BLOCO_LOTADO. Ela precisa ser RECUSADA, e com o codigo do catalogo."

grep -qi 'ERROR' "$TMP/a.log" \
  && falhar "a primeira sessao devia ter passado, e falhou. Uma das duas admissoes tem de ser aceita, senao a vaga que existia se perdeu."

limpar
echo "OK: uma admissao aceita, uma recusada com BLOCO_LOTADO, e o bloco fechou em 10/10 — nunca 11."
