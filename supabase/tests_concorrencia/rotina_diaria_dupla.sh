#!/usr/bin/env bash
# =============================================================================
# Duas execuções da rotina diária ao mesmo tempo — card 9.2,65
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/estrategia-testes.md §7
#
# O que se mede: a direção aperta "Recalcular agora" enquanto outra execução da
# rotina da MESMA unidade ainda está rodando (o cron das 03:10, ou um segundo
# clique). Sem o `pg_try_advisory_xact_lock` de `fn_rotina_diaria_executar` e de
# `rt_diaria`, as duas recalculam projeção, pedido sugerido e pendências por
# cima uma da outra — e quem chegou depois espera as travas de linha da primeira
# para refazer o mesmo trabalho.
#
# A trava é `try`, e não a espera do `pg_advisory_xact_lock`, de propósito: quem
# chega depois NÃO espera — recebe JA_EM_EXECUCAO na hora e a tela diz isso.
#
# Por que fora do pgTAP: o advisory lock é REENTRANTE na mesma sessão. Na suíte
# de conexão única a segunda chamada pegaria a trava que a primeira já tem e
# passaria — o arquivo 092 prova a permissão e o filtro de unidade; este aqui
# prova a trava.
#
# A asserção é pelo que cada sessão DEVOLVEU, não por tempo: sem a trava a
# segunda sessão devolve EXECUTADA (depois de esperar as linhas da primeira), e
# o teste reprova por isso. O `statement_timeout` de 20 s existe só para que uma
# espera patológica vire vermelho em vez de pendurar o CI.
#
# As duas sessões entram NA PELE da direção (JWT de `direcao@escola-a.test` e
# `role authenticated`), e não no contexto de rotina: a função exige
# `parametros.gerir` e tira a unidade da sessão de quem chama.
#
# Roda a partir da RAIZ do repositório, contra o stack local (`supabase start`),
# e por último na pasta (ordem alfabética): a rotina recalcula capacidades e
# pendências da Escola A, e nenhum script depois dele depende disso.
# =============================================================================
set -uo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Mesmo arranjo dos irmãos: `psql` do PATH, ou o de dentro do container.
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

# O JWT é montado como postgres (auth.users não é legível por authenticated) e
# SÓ ENTÃO a sessão troca de papel — a ordem inversa não acharia o usuário.
DIRECAO="$(cat <<'SQL'
set statement_timeout = '20s';
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from auth.users
                             where email = 'direcao@escola-a.test'),
                    'role', 'authenticated')::text,
  false);
set role authenticated;
SQL
)"

# Pré-condição: a direção da fixture existe e a função responde a ela. Sem isso
# as duas sessões falhariam por SEM_PERMISSAO e o teste reprovaria pela razão
# errada — ou, pior, uma asserção frouxa passaria.
cat > "$TMP/previa.sql" <<SQL
${DIRECAO}
select 'unidade=' || coalesce(public.fn_unidade_atual()::text, 'NENHUMA');
SQL
PREVIA="$(psql_exec "$TMP/previa.sql" | tr -d ' \r' | grep -E '^unidade=' | head -1)"
if [ -z "$PREVIA" ] || [ "$PREVIA" = "unidade=NENHUMA" ]; then
  echo "REPROVADO: a sessao de direcao@escola-a.test nao resolveu unidade (${PREVIA:-<vazio>})."
  echo "           A escola-fixture (supabase/seed.sql) mudou, ou o stack local nao tem o seed."
  exit 1
fi

# ---------------------------------------------------------------------------
# A corrida. A executa e segura a transação (e a trava) por 4 s; B chama 1 s
# depois. Com a trava, B devolve JA_EM_EXECUCAO sem esperar nada.
# ---------------------------------------------------------------------------
cat > "$TMP/sessao_a.sql" <<SQL
${DIRECAO}
begin;
select 'A=' || public.fn_rotina_diaria_executar();
select pg_sleep(4);
commit;
SQL

cat > "$TMP/sessao_b.sql" <<SQL
${DIRECAO}
select 'B=' || public.fn_rotina_diaria_executar();
SQL

psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
PID_A=$!
sleep 1
psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
wait "$PID_A"

echo "── sessao A ──"; sed 's/^/   /' "$TMP/a.log"
echo "── sessao B ──"; sed 's/^/   /' "$TMP/b.log"

# ---------------------------------------------------------------------------
# As asserções. A de B é a que denuncia a ausência da trava; a de A impede que
# ela passe porque as duas falharam.
# ---------------------------------------------------------------------------
grep -q 'A=EXECUTADA' "$TMP/a.log" \
  || { echo "REPROVADO: a primeira execucao nao devolveu EXECUTADA — sem ela a corrida nao mediu nada."; exit 1; }

grep -q 'B=JA_EM_EXECUCAO' "$TMP/b.log" \
  || { echo "REPROVADO: a segunda execucao nao devolveu JA_EM_EXECUCAO — a trava nao esta segurando duas rotinas da mesma unidade."; exit 1; }

# Depois que A terminou, a trava tem de ter saído com a transação: uma terceira
# chamada roda normalmente. Uma trava de SESSÃO (sem _xact) ficaria presa até a
# conexão cair e a direção nunca mais conseguiria recalcular.
cat > "$TMP/sessao_c.sql" <<SQL
${DIRECAO}
select 'C=' || public.fn_rotina_diaria_executar();
SQL
psql_exec "$TMP/sessao_c.sql" > "$TMP/c.log"
grep -q 'C=EXECUTADA' "$TMP/c.log" \
  || { echo "REPROVADO: depois do fim da primeira, uma nova execucao nao rodou:"; sed 's/^/   /' "$TMP/c.log"; exit 1; }

echo "OK: a primeira execucao rodou, a segunda recebeu JA_EM_EXECUCAO sem esperar, e a trava saiu com a transacao."
