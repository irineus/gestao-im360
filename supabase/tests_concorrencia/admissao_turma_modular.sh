#!/usr/bin/env bash
# =============================================================================
# Admissão simultânea na última vaga da turma Modular — card 7.4,5
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/estrategia-testes.md §7
#
# O que se mede: duas secretarias admitem alunos DIFERENTES na mesma turma
# Modular, que tem UMA vaga, ao mesmo tempo. Sem o `pg_advisory_xact_lock` de
# `fn_turma_modular_admitir` (card 2.2 §4.5, que a cita nominalmente) as duas
# passam pela checagem de capacidade do `tg_turma_modular_aluno_admissao` — em
# `read committed` nenhuma enxerga a linha ainda não commitada da outra — e a
# turma fica com `capacidade + 1` alunos.
#
# NENHUMA constraint pega isso, e a razão é a mesma do irmão de blocos: lotação é
# regra de AGREGADO, não de linha. A unique parcial `turma_modular_aluno_ativo_uk`
# é `(turma_id, aluno_id) where ativo` e só proíbe o MESMO aluno duas vezes na
# mesma turma — dois alunos diferentes a satisfazem sem esforço. E a capacidade
# aqui é COLUNA (`turma_modular.capacidade`), não conta de PC: não há nem o
# consolo de um recurso físico que acabe.
#
# Por que fora do pgTAP: aquela suíte roda numa conexão só, então o `select` que
# conta e o `insert` que grava acontecem na mesma transação e a corrida não
# existe. O teste C13 do arquivo 071 (asserção de que a chamada do lock não
# sumiu) é o guarda-chuva barato; este aqui é a prova.
#
# A asserção é por CONTAGEM, não por tempo: sem o lock os dois passam e o teste
# tem de reprovar por 2 ≠ 1, e não travar o CI para sempre. O `statement_timeout`
# de 10 s existe só para que uma espera patológica vire vermelho em vez de
# pendurar a execução.
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

# A turma e os dois alunos vêm da escola-fixture (card 3.4.5, camada `modular`) e
# são escolhidos por CHAVE NATURAL, nunca por `limit` (docs/estrategia-testes.md
# §11). Sem acento nenhum de propósito: o SQL atravessa shell, docker exec e
# psql, e uma camada com encoding diferente transformaria "Eletricista" com
# acento num `where` que não casa com nada — e o teste passaria por não achar a
# turma.
#   • turma: `Eletricista Individual 2026` — capacidade 1, VAZIA (0 de 1)
#   • alunos: codigo_sgf 3005 (Eduarda Lima, na turma 2026.1) e 9101 (Aluno
#     Modular 01, sem turma). Os dois são MODULAR e ATIVOS, que é o que o
#     trigger exige antes de chegar à capacidade — sem isso a segunda sessão
#     seria recusada por ALUNO_NAO_MODULAR e o teste ficaria verde sem medir
#     lotação nenhuma.
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
  select (select t.id from public.turma_modular t
           where t.unidade_id = current_setting('app.rotina_unidade')::uuid
             and t.nome = 'Eletricista Individual 2026')  as turma,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '3005')                   as aluno_a,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '9101')                   as aluno_b;
SQL
)"

# `capacidade/ocupacao` numa string só: as duas metades do cenário se conferem
# juntas, e uma capacidade que mudou na fixture é tão fatal quanto uma ocupação
# suja de execução anterior.
cenario() {
  cat > "$TMP/cenario.sql" <<SQL
${CONTEXTO}
${ALVO}
select format('%s/%s', t.capacidade,
              (select count(*) from public.turma_modular_aluno ta
                where ta.turma_id = t.id and ta.ativo))
  from public.turma_modular t, alvo
 where t.id = alvo.turma;
SQL
  psql_exec "$TMP/cenario.sql" | tr -d ' \r' | grep -E '^[0-9]+/[0-9]+$' | head -1
}

ocupacao() {
  cat > "$TMP/ocupacao.sql" <<SQL
${CONTEXTO}
${ALVO}
select count(*) from public.turma_modular_aluno ta, alvo
 where ta.turma_id = alvo.turma and ta.ativo;
SQL
  psql_exec "$TMP/ocupacao.sql" | tr -d ' \r' | grep -E '^[0-9]+$' | head -1
}

# `delete` e não `ativo = false`: a linha inativa faria a próxima execução achar
# uma alocação antiga e REATIVÁ-LA (card 7.2, seção 4) em vez de inserir — a
# corrida seguinte mediria um `update`, que não disputa vaga nenhuma, e o teste
# ficaria verde sem lock nenhum. Banco local descartável; `turma_modular_aluno`
# não é imutável, ao contrário de `movimento_estoque` (card 6.3).
limpar() {
  cat > "$TMP/limpar.sql" <<SQL
${CONTEXTO}
${ALVO}
delete from public.turma_modular_aluno ta
 using alvo
 where ta.turma_id = alvo.turma;
SQL
  psql_exec "$TMP/limpar.sql" >/dev/null
}

falhar() { echo "REPROVADO: $*"; limpar; exit 1; }

# ---------------------------------------------------------------------------
# Pré-condição: o cenário é 0 de 1. Sem esta conferência, uma turma com folga
# faria as duas admissões passarem e o teste ficaria verde sem medir nada.
# ---------------------------------------------------------------------------
limpar
ANTES="$(cenario)"
if [ "$ANTES" != "1/0" ]; then
  echo "REPROVADO: a turma de partida esta em ${ANTES:-<vazio>} (capacidade/ocupacao), e o cenario exige 1/0."
  echo "           A escola-fixture (supabase/seed.sql, camada \`modular\`) mudou, ou o stack local"
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
select public.fn_turma_modular_admitir(alvo.turma, alvo.aluno_a) from alvo;
select pg_sleep(3);
commit;
SQL

cat > "$TMP/sessao_b.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
select public.fn_turma_modular_admitir(alvo.turma, alvo.aluno_b) from alvo;
commit;
SQL

psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
PID_A=$!
sleep 1
psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
# ⚠️ ESPERAR AS DUAS ANTES DE CONTAR (lição do card 6.3): a sessão que segura o
# lock ainda está dentro do `pg_sleep`, e `read committed` não enxerga a linha
# não commitada dela. Contar antes do `wait` daria VERDE NA SABOTAGEM.
wait "$PID_A"

DEPOIS="$(ocupacao)"

echo "── sessao A ──"; sed 's/^/   /' "$TMP/a.log"
echo "── sessao B ──"; sed 's/^/   /' "$TMP/b.log"
echo "── ocupacao final: ${DEPOIS} ──"

# ---------------------------------------------------------------------------
# As três asserções, e a ordem importa: a contagem é a que denuncia a ausência
# do lock, e as outras duas impedem que ela passe por acaso.
# ---------------------------------------------------------------------------
[ "$DEPOIS" = "1" ] || falhar "a turma de 1 vaga ficou com ${DEPOIS} alocacoes ativas — o advisory lock nao esta segurando a corrida."

grep -q 'TURMA_LOTADA' "$TMP/b.log" \
  || falhar "a segunda sessao nao recebeu TURMA_LOTADA. Ela precisa ser RECUSADA, e com o codigo do catalogo."

grep -qi 'ERROR' "$TMP/a.log" \
  && falhar "a primeira sessao devia ter passado, e falhou. Uma das duas admissoes tem de ser aceita, senao a vaga que existia se perdeu."

limpar
echo "OK: uma admissao aceita, uma recusada com TURMA_LOTADA, e a turma fechou em 1/1 — nunca 2."
