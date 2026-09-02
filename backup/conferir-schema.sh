#!/usr/bin/env bash
#
# Confere o `schema.sql` do backup contra as tabelas que as migrações criam.
#
#   backup/conferir-schema.sh <schema.sql|.gz> <tabelas-esperadas.txt>
#
# POR QUE ESTE ARQUIVO É CONFERIDO E NÃO APLICADO (02/09/2026, card 3.11):
# a estrutura deste sistema já tem backup em três lugares — `supabase/migrations/`
# no Git, no GitHub e em qualquer clone. O que o R2 guarda e o Git não guarda é o
# DADO. Então a restauração de verdade é "projeto Supabase novo → migrações pelo
# CI → `data.sql`", e é isso que o ensaio semanal executa.
#
# O `schema.sql` continua no backup por outro motivo: ele é a foto do que estava
# REALMENTE em produção naquele domingo. E o dia em que ele divergir das
# migrações é o dia em que alguém aplicou SQL à mão, contra a regra inegociável
# do CLAUDE.md — é exatamente isso que a comparação abaixo denuncia, e não há
# nada mais no projeto que denunciaria.
#
# A comparação é SIMÉTRICA, como o teste C8: falta significa dump truncado ou
# migração que não chegou a produção; sobra significa tabela que existe em
# produção e não vem de migração nenhuma.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "uso: $0 <schema.sql|.gz> <tabelas-esperadas.txt>" >&2
  exit 64
fi

SCHEMA="$1"
ESPERADAS="$2"

ler() {
  if [[ "$1" == *.gz ]]; then gzip -dc "$1"; else cat "$1"; fi
}

# `pg_dump` escreve `CREATE TABLE "public"."aluno" (` ou `CREATE TABLE public.aluno (`
# conforme a versão e o uso de `--quote-all-identifiers`; o padrão cobre as duas.
ler "$SCHEMA" \
  | sed -nE 's/^CREATE TABLE (IF NOT EXISTS )?"?public"?\."?([A-Za-z0-9_]+)"?.*/\2/p' \
  | LC_ALL=C sort -u > /tmp/tabelas-no-schema.txt

LC_ALL=C sort -u "$ESPERADAS" > /tmp/tabelas-esperadas-ord.txt

qtd=$(wc -l < /tmp/tabelas-no-schema.txt)
echo "tabelas de public declaradas em $(basename "$SCHEMA"): $qtd"

falhas=0
reprovar() {
  echo "REPROVADO: $1"
  echo "::error title=schema.sql do backup::$1"
  falhas=$((falhas + 1))
}

if [ "$qtd" -eq 0 ]; then
  reprovar "o schema.sql do backup não declara NENHUMA tabela em public — dump truncado ou vazio."
fi

faltando=$(LC_ALL=C comm -23 /tmp/tabelas-esperadas-ord.txt /tmp/tabelas-no-schema.txt || true)
sobrando=$(LC_ALL=C comm -13 /tmp/tabelas-esperadas-ord.txt /tmp/tabelas-no-schema.txt || true)

if [ -n "$faltando" ]; then
  reprovar "as migrações de main criam, e o backup de produção NÃO tem: $(echo "$faltando" | tr '\n' ' ')"
fi
if [ -n "$sobrando" ]; then
  reprovar "produção tem tabela que NÃO vem de migração nenhuma (SQL aplicado à mão?): $(echo "$sobrando" | tr '\n' ' ')"
fi

if [ "$falhas" -gt 0 ]; then
  exit 1
fi

echo "schema.sql confere com as migrações de main."
