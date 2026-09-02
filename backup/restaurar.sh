#!/usr/bin/env bash
#
# Restaura um backup do card 3.11 num banco VAZIO.
#
#   backup/restaurar.sh <diretório-do-backup> <url-do-banco-destino> [--com-papeis]
#
# Aceita os arquivos como saíram do dump (`.sql`) ou como estão no R2 (`.sql.gz`).
#
# ESTE SCRIPT É O PROCEDIMENTO DE RESTAURAÇÃO E O TESTE DE RESTAURAÇÃO AO MESMO
# TEMPO, de propósito. O workflow `backup-semanal` chama exatamente estas linhas
# toda semana, contra um banco novo, antes de publicar o backup no R2. Um
# procedimento escrito à parte envelhece calado — este não tem como, porque se
# ele parar de funcionar o backup fica vermelho no domingo seguinte.
#
# `roles.sql` NÃO é aplicado por padrão. Papel no Postgres é objeto de CLUSTER, e
# num projeto Supabase novo (que é o destino real de uma restauração) `anon`,
# `authenticated`, `service_role` e companhia já existem. Aplicá-lo por padrão
# testaria criação de papel, não recuperação de dado, e faria a restauração
# quebrar no primeiro `CREATE ROLE` de papel existente. Use `--com-papeis` só
# quando o destino for um Postgres cru, fora do Supabase.
#
# ⚠️ NADA de `|| true` aqui, e `ON_ERROR_STOP=1` sempre: restauração que engole
# erro devolve um banco pela metade dizendo que deu certo — que é o modo de falha
# exato que se está tentando evitar ao ter backup.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "uso: $0 <diretório-do-backup> <url-do-banco-destino> [--com-papeis]" >&2
  exit 64
fi

DIR="$1"
URL="$2"
COM_PAPEIS="${3:-}"

# Devolve o caminho do arquivo, seja ele .sql ou .sql.gz; vazio se não existir.
localizar() {
  local nome="$1"
  if   [ -f "$DIR/$nome.sql" ];    then echo "$DIR/$nome.sql"
  elif [ -f "$DIR/$nome.sql.gz" ]; then echo "$DIR/$nome.sql.gz"
  fi
}

aplicar() {
  local arquivo="$1"
  echo "── aplicando $arquivo"
  # `--single-transaction`: ou entra tudo, ou não entra nada. Restauração parcial
  # é a pior das três hipóteses, porque parece sucesso.
  if [[ "$arquivo" == *.gz ]]; then
    gzip -dc "$arquivo" | psql "$URL" -v ON_ERROR_STOP=1 --single-transaction -q -f -
  else
    psql "$URL" -v ON_ERROR_STOP=1 --single-transaction -q -f "$arquivo"
  fi
}

if [ "$COM_PAPEIS" = "--com-papeis" ]; then
  papeis="$(localizar roles)"
  [ -n "$papeis" ] || { echo "roles.sql não encontrado em $DIR" >&2; exit 66; }
  aplicar "$papeis"
fi

schema="$(localizar schema)"
dados="$(localizar data)"
[ -n "$schema" ] || { echo "schema.sql não encontrado em $DIR" >&2; exit 66; }
[ -n "$dados" ]  || { echo "data.sql não encontrado em $DIR"   >&2; exit 66; }

aplicar "$schema"
aplicar "$dados"

echo "Restauração concluída em $(echo "$URL" | sed 's#://[^@]*@#://***@#')"
