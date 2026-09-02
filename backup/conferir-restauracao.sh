#!/usr/bin/env bash
#
# Confere um banco recém-restaurado (card 3.11).
#
#   backup/conferir-restauracao.sh <url-do-banco-restaurado> [tabelas-esperadas.txt]
#
# POR QUE ISTO EXISTE: `pg_dump` e `psql` saem com 0 numa porção de situações em
# que o backup não serve para nada — dump de schema sem dado, dump tirado do
# banco errado, dump truncado no meio. "Restaurou sem erro" é asserção vazia,
# pela mesma razão que o card 2.8 (b) recusa "a view não deu erro" como teste. O
# que prova alguma coisa é a asserção POSITIVA: as tabelas que se esperava estão
# lá, e as que sustentam o sistema têm linha.
#
# O arquivo de tabelas esperadas, quando informado, sai do banco local com as
# migrações de `main` aplicadas — isto é, do que o REPOSITÓRIO diz que produção
# tem. A comparação é SIMÉTRICA (falta e sobra), como o teste C8: tabela que
# existe em produção e não existe nas migrações é SQL aplicado à mão, que a regra
# inegociável do CLAUDE.md proíbe, e é justamente o que ninguém descobriria de
# outro jeito.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "uso: $0 <url-do-banco-restaurado> [tabelas-esperadas.txt]" >&2
  exit 64
fi

URL="$1"
ESPERADAS="${2:-}"
falhas=0

consulta() { psql "$URL" -Atq -c "$1"; }

reprovar() {
  echo "REPROVADO: $1"
  echo "::error title=Ensaio de restauração::$1"
  falhas=$((falhas + 1))
}

# ---------------------------------------------------------------------------
# 1. As tabelas que as migrações criam estão todas lá — e nenhuma a mais
# ---------------------------------------------------------------------------
consulta "select table_name from information_schema.tables
           where table_schema = 'public' and table_type = 'BASE TABLE' order by 1" \
  > /tmp/tabelas-restauradas.txt

qtd=$(wc -l < /tmp/tabelas-restauradas.txt)
echo "tabelas em public no backup restaurado: $qtd"

if [ "$qtd" -eq 0 ]; then
  reprovar "o banco restaurado não tem NENHUMA tabela em public — o dump não trouxe schema."
fi

if [ -n "$ESPERADAS" ]; then
  # `comm` exige as duas listas ordenadas pelo MESMO critério, e a ordenação do
  # Postgres depende do locale do banco — que não é o do shell. Reordenar as duas
  # com `LC_ALL=C` aqui evita uma divergência que apareceria como tabela faltando
  # e sobrando ao mesmo tempo, sem nada de errado com o backup.
  LC_ALL=C sort "$ESPERADAS" > /tmp/esperadas.txt
  LC_ALL=C sort /tmp/tabelas-restauradas.txt > /tmp/restauradas.txt
  faltando=$(LC_ALL=C comm -23 /tmp/esperadas.txt /tmp/restauradas.txt || true)
  sobrando=$(LC_ALL=C comm -13 /tmp/esperadas.txt /tmp/restauradas.txt || true)
  if [ -n "$faltando" ]; then
    reprovar "tabelas que as migrações de main criam e o backup NÃO tem: $(echo "$faltando" | tr '\n' ' ')"
  fi
  if [ -n "$sobrando" ]; then
    reprovar "tabelas em produção que NÃO vêm das migrações (SQL aplicado à mão?): $(echo "$sobrando" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# 2. As tabelas de configuração têm linha
# ---------------------------------------------------------------------------
# Estas cinco vêm do seed do card 3.6, que é migração: sem elas o sistema sobe e
# `tem_permissao()` é falso para todo mundo — todas as telas vazias, sem erro
# nenhum. São também as únicas que, pela decisão de 02/09/2026, produção tem
# garantidamente preenchidas antes do cutover. Zero aqui significa dump de
# schema sem dado, que é o jeito mais comum de um backup ser inútil.
for tabela in unidade perfil permissao perfil_permissao parametro; do
  if [ -z "$(consulta "select to_regclass('public.$tabela')")" ]; then
    reprovar "tabela public.$tabela não existe no backup restaurado."
    continue
  fi
  linhas=$(consulta "select count(*) from public.$tabela")
  echo "public.$tabela: $linhas linha(s)"
  [ "$linhas" -gt 0 ] || reprovar "public.$tabela veio VAZIA — o dump trouxe schema e não trouxe dado."
done

# ---------------------------------------------------------------------------
# 3. Informativo: quem consegue entrar depois de uma restauração
# ---------------------------------------------------------------------------
# Não reprova, e a razão é estrutural: `usuario.id` referencia `auth.users(id)`
# (card 3.3), então dado de `usuario` sem os usuários do Auth quebra a
# restauração por violação de FK, no passo anterior — a FK já é o guarda. E o que
# resta perder é recuperável por clique: convidar a direção pelo painel refaz o
# vínculo sozinho, porque o bootstrap do card 3.6 é também um trigger em
# `usuario`. Perder `permissao` ou `parametro` não se recupera assim; por isso a
# severidade é diferente.
for alvo in 'auth.users' 'public.usuario' 'supabase_migrations.schema_migrations'; do
  if [ -n "$(consulta "select to_regclass('$alvo')")" ]; then
    echo "$alvo: $(consulta "select count(*) from $alvo") linha(s)"
  else
    echo "$alvo: AUSENTE no backup (informativo — ver docs/backup-restauracao.md §5)"
  fi
done

if [ "$falhas" -gt 0 ]; then
  echo
  echo "Ensaio de restauração REPROVADO em $falhas ponto(s)."
  exit 1
fi

echo
echo "Ensaio de restauração aprovado."
