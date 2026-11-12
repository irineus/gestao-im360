#!/usr/bin/env bash
# =============================================================================
# Admissão × avanço de módulo na turma em rodízio — card 9.2,886
# Contrato: supabase/tests_concorrencia/README.md; motivo: docs/turma-rodizio.md §11
#
# O que se mede: uma pessoa ADMITE um aluno na turma enquanto outra AVANÇA o
# módulo dela. As duas funções pegam o mesmo `pg_advisory_xact_lock` por turma
# (card 9.2,88) — e sem ele o aluno fica num estado que nenhuma das duas ordens
# produz: entrou pelo módulo que acabou de fechar e NÃO o recebeu.
#
# Com o lock só existem dois desfechos, e cada rodada exige um deles:
#
#   RODADA 1 — o avanço chega primeiro. A admissão espera, e quando roda a
#     turma JÁ está no módulo seguinte: o aluno entra por ELE, e não recebe o
#     módulo que fechou (não estava lá).            → entrada 2, corrente 2, sem o 1
#
#   RODADA 2 — a admissão chega primeiro. O avanço espera, e quando roda o
#     aluno JÁ está na turma, com entrada no módulo corrente: recebe o módulo
#     que fecha.                                    → entrada 1, corrente 2, com o 1
#
# Sem o lock as duas rodadas terminam em "entrada 1, corrente 2, SEM o 1": em
# `read committed` a admissão lê o módulo corrente antigo (o `update` do avanço
# ainda não commitou) e o avanço não enxerga a linha do aluno (ainda não
# commitada). Para o sistema esse aluno "entrou para começar no próximo módulo"
# — e o módulo 1, que ele deveria ter recebido ou nunca ter tido como entrada,
# fica para a próxima volta da turma. NENHUMA constraint pega isso: é uma regra
# entre duas tabelas e o estado de uma terceira.
#
# A asserção é por ESTADO, não por tempo. O `statement_timeout` de 10 s existe
# só para que uma espera patológica vire vermelho em vez de pendurar o CI.
#
# ⚠️ O script cria a PRÓPRIA turma e a apaga no fim. Os scripts deste diretório
# rodam em ordem alfabética, e este vem antes de `admissao_turma_modular.sh`,
# que exige a turma `Eletricista Individual 2026` em 1/0 e com o cronograma da
# fixture — avançar o módulo dela aqui quebraria o cenário do vizinho.
#
# Roda a partir da RAIZ do repositório, contra o stack local (`supabase start`).
# =============================================================================
set -uo pipefail

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# O cliente `psql` do PATH quando há um; senão, o de dentro do container do
# stack local (lição do card 5.3: teste que só roda no CI ninguém roda antes do
# PR).
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

# Sem sessão não há permissão: as duas funções exigem `turmas.editar` e
# `turmas.alocar`, e as duas sessões entram no contexto de rotina (card 2.2
# §2.2), como os outros scripts deste diretório.
CONTEXTO="$(cat <<'SQL'
set statement_timeout = '10s';
set app.rotina = 'on';
select set_config('app.rotina_unidade',
                  (select id::text from public.unidade where codigo = 'ESCOLA_A'),
                  false);
SQL
)"

# Tudo por CHAVE NATURAL e sem acento (o SQL atravessa shell, docker exec e
# psql). O curso e a sala são os da turma `Eletricista 2026.1` da fixture; o
# aluno é o 9101 (Aluno Modular 01), MODULAR, ATIVO e sem turma.
TURMA='Concorrencia Rodizio'
ALVO="$(cat <<SQL
create temporary view alvo as
  select (select t.id from public.turma_modular t
           where t.unidade_id = current_setting('app.rotina_unidade')::uuid
             and t.nome = '${TURMA}')                     as turma,
         (select t.curso_id from public.turma_modular t
           where t.unidade_id = current_setting('app.rotina_unidade')::uuid
             and t.nome = 'Eletricista 2026.1')           as curso,
         (select a.id from public.aluno a
           where a.unidade_id = current_setting('app.rotina_unidade')::uuid
             and a.codigo_sgf = '9101')                   as aluno;
SQL
)"

# `delete`, e não `ativo = false`: a linha inativa seria REATIVADA pela admissão
# seguinte (um `update`), e a rodada 2 mediria outra coisa. A ordem é a das
# dependências — os módulos feitos, a alocação, o cronograma, a turma.
limpar() {
  cat > "$TMP/limpar.sql" <<SQL
${CONTEXTO}
${ALVO}
delete from public.aluno_modulo am
 using alvo, public.modulo m
 where am.aluno_id = alvo.aluno and m.id = am.modulo_id and m.curso_id = alvo.curso;
delete from public.turma_modular_aluno ta using alvo where ta.turma_id = alvo.turma;
delete from public.turma_modular_modulo tm using alvo where tm.turma_id = alvo.turma;
delete from public.turma_modular t using alvo where t.id = alvo.turma;
SQL
  psql_exec "$TMP/limpar.sql" >/dev/null
}

# A turma de partida: capacidade 5, vazia, no módulo 1 do curso (em curso, com
# previsão futura). Os módulos 2 e 3 não têm linha — é o avanço que completa o
# ciclo, como numa turma de verdade.
preparar() {
  limpar
  cat > "$TMP/preparar.sql" <<SQL
${CONTEXTO}
insert into public.turma_modular (unidade_id, curso_id, nome, sala_id, capacidade,
                                  data_inicio, ativo)
select t.unidade_id, t.curso_id, '${TURMA}', t.sala_id, 5, public.fn_hoje() - 30, true
  from public.turma_modular t
 where t.unidade_id = current_setting('app.rotina_unidade')::uuid
   and t.nome = 'Eletricista 2026.1';
${ALVO}
insert into public.turma_modular_modulo (unidade_id, turma_id, modulo_id,
                                         data_inicio, prev_conclusao, concluido)
select m.unidade_id, alvo.turma, m.id, public.fn_hoje() - 30, public.fn_hoje() + 5, false
  from public.modulo m, alvo
 where m.curso_id = alvo.curso and m.ordem = 1;
SQL
  psql_exec "$TMP/preparar.sql" >/dev/null
}

# `entrada/corrente/tem_o_1`, numa string só: as três metades se conferem
# juntas. `-` é "não há" — aluno fora da turma, ou turma sem módulo corrente.
estado() {
  cat > "$TMP/estado.sql" <<SQL
${CONTEXTO}
${ALVO}
select format('%s/%s/%s',
         coalesce((select m.ordem::text
                     from public.turma_modular_aluno ta
                     join public.modulo m on m.id = ta.modulo_entrada_id
                    where ta.turma_id = alvo.turma and ta.aluno_id = alvo.aluno
                      and ta.ativo), '-'),
         coalesce((select m.ordem::text from public.modulo m
                    where m.id = public.fn_turma_modular_modulo_corrente(alvo.turma)), '-'),
         (select count(*) from public.aluno_modulo am
            join public.modulo m on m.id = am.modulo_id
           where am.aluno_id = alvo.aluno and m.curso_id = alvo.curso and m.ordem = 1))
  from alvo;
SQL
  psql_exec "$TMP/estado.sql" | tr -d ' \r' | grep -E '^[0-9-]+/[0-9-]+/[0-9]+$' | head -1
}

falhar() { echo "REPROVADO: $*"; limpar; exit 1; }

AVANCAR="select public.fn_turma_modular_avancar(alvo.turma, public.fn_hoje()) from alvo;"
ADMITIR="select public.fn_turma_modular_admitir(alvo.turma, alvo.aluno) from alvo;"

# Uma rodada: a primeira sessão roda [1], segura o lock por 3 s e commita; a
# segunda entra 1 s depois com [2] e — havendo lock — espera.
rodada() {
  local nome="$1" primeira="$2" segunda="$3" esperado="$4" porque="$5"

  preparar
  local antes
  antes="$(estado)"
  if [ "$antes" != "-/1/0" ]; then
    echo "REPROVADO: a turma de partida esta em ${antes:-<vazio>} (entrada/corrente/tem_o_1), e o cenario exige -/1/0."
    echo "           A escola-fixture mudou (curso de Eletricista, aluno 9101), ou o stack local"
    echo "           esta com dados de outra execucao — \`supabase stop --no-backup\` e \`start\`."
    limpar
    exit 1
  fi

  cat > "$TMP/sessao_a.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
${primeira}
select pg_sleep(3);
commit;
SQL
  cat > "$TMP/sessao_b.sql" <<SQL
${CONTEXTO}
begin;
${ALVO}
${segunda}
commit;
SQL

  psql_exec "$TMP/sessao_a.sql" > "$TMP/a.log" &
  local pid_a=$!
  sleep 1
  psql_exec "$TMP/sessao_b.sql" > "$TMP/b.log"
  # ⚠️ ESPERAR AS DUAS ANTES DE LER O ESTADO (lição do card 6.3): quem segura o
  # lock ainda está no `pg_sleep`, e ler antes do `wait` daria verde na sabotagem.
  wait "$pid_a"

  local depois
  depois="$(estado)"
  echo "── ${nome} ──"
  echo "   primeira sessao:"; sed 's/^/      /' "$TMP/a.log"
  echo "   segunda sessao:";  sed 's/^/      /' "$TMP/b.log"
  echo "   estado final (entrada/corrente/tem_o_1): ${depois}"

  grep -qi 'ERROR' "$TMP/a.log" && falhar "${nome}: a primeira sessao falhou — as duas operacoes tem de passar."
  grep -qi 'ERROR' "$TMP/b.log" && falhar "${nome}: a segunda sessao falhou — ela tem de ESPERAR a primeira e passar, nao ser recusada."
  [ "$depois" = "$esperado" ] \
    || falhar "${nome}: o estado final foi ${depois}, e o esperado e ${esperado}. ${porque}"
}

rodada "rodada 1 — o avanco chega primeiro" "$AVANCAR" "$ADMITIR" "2/2/0" \
  "A admissao tem de esperar o avanco e entrar pelo modulo NOVO; entrada 1 com corrente 2 e o aluno que entrou pelo modulo que ja fechou — o advisory lock nao esta segurando a corrida."

rodada "rodada 2 — a admissao chega primeiro" "$ADMITIR" "$AVANCAR" "1/2/1" \
  "O avanco tem de esperar a admissao e dar o modulo que fechou ao aluno que entrou por ele; sem o modulo 1, o avanco nao enxergou o aluno — o advisory lock nao esta segurando a corrida."

limpar
echo "OK: nas duas ordens o aluno fica num estado que uma ordem serial produz — entrou pelo modulo novo (sem o antigo) ou pelo antigo (e o recebeu). Nunca o do meio."
