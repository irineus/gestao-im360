#!/usr/bin/env bash
# =============================================================================
# Duas aplicações simultâneas do MESMO lote de importação — card 9.2,68
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/estrategia-testes.md §7
#
# O que se mede: a direção aperta "Aplicar" em duas abas (ou o PostgREST é
# chamado duas vezes) para o mesmo lote VALIDADA. Sem o `for update` na leitura
# do lote em `fn_importacao_aplicar`, as duas sessões leem VALIDADA e correm
# juntas: a segunda aplica o lote DE NOVO e também devolve APLICADA (medido na
# contraprova de 24/09/2026), ou para numa chave única com
# erro técnico — nunca com o status legível. Com a trava, a segunda espera a
# primeira terminar, lê APLICADA e recebe IMPORTACAO_JA_APLICADA.
#
# Por que fora do pgTAP: numa conexão só não há duas transações simultâneas.
# O 101_importacao_guardas confere que o `for update` está no corpo (guarda-
# chuva barato); este aqui é a prova.
#
# A asserção é pelo que cada sessão DEVOLVEU. O `statement_timeout` de 20 s
# existe só para que uma espera patológica vire vermelho.
#
# O lote é da Escola A e só traz um professor com nome de marca — o menor
# arquivo que exercita a aplicação inteira e se limpa com `delete` (movimento
# de estoque é imutável, e é por isso que ele não entra aqui). Roda a partir da
# RAIZ do repositório, contra o stack local, e limpa o que criou.
# =============================================================================
set -uo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

MARCA='Prof. Concorrencia Importacao 9268'

if command -v psql >/dev/null 2>&1; then
  psql_exec() { psql "$DB_URL" -X -q -v ON_ERROR_STOP=0 -f "$1" 2>&1; }
else
  PROJETO="$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' supabase/config.toml | head -1)"
  CONTAINER="supabase_db_${PROJETO}"
  if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "ERRO: sem psql no PATH e sem o container ${CONTAINER}."
    exit 1
  fi
  psql_exec() {
    docker exec -i "$CONTAINER" \
      psql "postgresql://postgres:postgres@127.0.0.1:5432/postgres" \
      -X -q -v ON_ERROR_STOP=0 -f - < "$1" 2>&1
  }
fi

# Na pele da direção da Escola A: o JWT é montado como postgres e só então a
# sessão troca de papel (o mesmo arranjo do rotina_diaria_dupla.sh).
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

limpar() {
  cat > "$TMP/limpar.sql" <<SQL
delete from public.importacao where arquivo = 'concorrencia-9268.json';
delete from public.professor where nome = '${MARCA}';
SQL
  psql_exec "$TMP/limpar.sql" >/dev/null
}

falhar() { echo "REPROVADO: $*"; limpar; exit 1; }

# ---------------------------------------------------------------------------
# O lote, VALIDADA e commitado — as duas sessões precisam enxergá-lo.
# ---------------------------------------------------------------------------
limpar
cat > "$TMP/registrar.sql" <<SQL
${DIRECAO}
select 'LOTE=' || public.fn_importacao_registrar(
  'concorrencia-9268.json', '2026-08-29'::date,
  jsonb_build_object('professor', jsonb_build_array(jsonb_build_object('nome', '${MARCA}'))));
SQL
LOTE="$(psql_exec "$TMP/registrar.sql" | tr -d ' \r' | sed -n 's/^LOTE=//p' | head -1)"
[ -n "$LOTE" ] || falhar "nao consegui registrar o lote de partida."

# ---------------------------------------------------------------------------
# A corrida. A aplica e segura a transação por 3 s; B chama 1 s depois.
# ---------------------------------------------------------------------------
cat > "$TMP/sessao_a.sql" <<SQL
${DIRECAO}
begin;
select 'A=' || (public.fn_importacao_aplicar('${LOTE}'::uuid, false) ->> 'status');
select pg_sleep(3);
commit;
SQL

cat > "$TMP/sessao_b.sql" <<SQL
${DIRECAO}
select 'B=' || (public.fn_importacao_aplicar('${LOTE}'::uuid, false) ->> 'status');
SQL

psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
PID_A=$!
sleep 1
psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
wait "$PID_A"

cat > "$TMP/estado.sql" <<SQL
select 'STATUS=' || status from public.importacao where id = '${LOTE}'::uuid;
select 'PROFESSORES=' || count(*) from public.professor where nome = '${MARCA}';
SQL
psql_exec "$TMP/estado.sql" > "$TMP/estado.log"

echo "── sessao A ──"; grep -E "A=|ERROR|DETAIL" "$TMP/a.log" | sed 's/^/   /'
echo "── sessao B ──"; grep -E "B=|ERROR|DETAIL" "$TMP/b.log" | sed 's/^/   /'
echo "── estado ──";   grep -E "STATUS=|PROFESSORES=" "$TMP/estado.log" | sed 's/^/   /'

grep -q 'A=APLICADA' "$TMP/a.log" \
  || falhar "a primeira aplicacao nao devolveu APLICADA — sem ela a corrida nao mediu nada."

grep -q 'IMPORTACAO_JA_APLICADA' "$TMP/b.log" \
  || falhar "a segunda aplicacao nao recebeu IMPORTACAO_JA_APLICADA — o lote nao esta travado."

grep -q 'STATUS=APLICADA' "$TMP/estado.log" \
  || falhar "o lote terminou fora de APLICADA — a segunda sessao mexeu no que a primeira deixou."

grep -q 'PROFESSORES=1' "$TMP/estado.log" \
  || falhar "o professor do arquivo nao ficou exatamente uma vez no sistema."

limpar
echo "OK: a primeira aplicou, a segunda esperou e recebeu IMPORTACAO_JA_APLICADA, e o lote ficou APLICADA."
