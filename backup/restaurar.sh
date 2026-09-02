#!/usr/bin/env bash
#
# Restaura um backup do card 3.11.
#
#   backup/restaurar.sh <diretório-do-backup> <url-do-banco-destino> [modo…]
#
#   (sem modo)        aplica schema.sql e depois data.sql
#   --somente-dados   aplica só data.sql — é o modo do ensaio semanal e o do
#                     procedimento real de restauração deste projeto
#   --com-papeis      aplica roles.sql antes de tudo
#
# Aceita os arquivos como saíram do dump (`.sql`) ou como estão no R2 (`.sql.gz`).
#
# ESTE SCRIPT É O PROCEDIMENTO DE RESTAURAÇÃO E O TESTE DE RESTAURAÇÃO AO MESMO
# TEMPO, de propósito. O workflow `backup-semanal` chama exatamente estas linhas
# toda semana, antes de publicar o backup no R2. Um procedimento escrito à parte
# envelhece calado — este não tem como, porque se ele parar de funcionar o backup
# fica vermelho no domingo seguinte.
#
# ⚠️ POR QUE O MODO NORMAL É `--somente-dados` (aprendido em 02/09/2026, na
# estreia): o `schema.sql` do CLI é escrito para um destino que já tem a CASCA do
# Supabase — ele emite `CREATE EXTENSION … WITH SCHEMA extensions` e conta com os
# schemas `extensions`, `auth`, `storage`, `graphql` e `vault` já existindo.
# Esses schemas são criados POR BANCO, não por cluster (ao contrário dos papéis),
# então um `createdb` dentro de um Postgres do Supabase NÃO é um projeto novo: é
# um banco cru, e a restauração morre na linha 20 com `schema "extensions" does
# not exist`. O destino de verdade é um PROJETO Supabase novo com as migrações
# de `supabase/migrations/` já aplicadas — e aí a estrutura já está no lugar e o
# que falta é só o dado, que é justamente o que o Git não guarda.
#
# ⚠️ NADA de `|| true` aqui, e `ON_ERROR_STOP=1` sempre: restauração que engole
# erro devolve um banco pela metade dizendo que deu certo — que é o modo de falha
# exato que se está tentando evitar ao ter backup.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "uso: $0 <diretório-do-backup> <url-do-banco-destino> [--somente-dados] [--com-papeis]" >&2
  exit 64
fi

DIR="$1"
URL="$2"
shift 2

SOMENTE_DADOS=0
COM_PAPEIS=0
for modo in "$@"; do
  case "$modo" in
    --somente-dados) SOMENTE_DADOS=1 ;;
    --com-papeis)    COM_PAPEIS=1 ;;
    *) echo "modo desconhecido: $modo" >&2; exit 64 ;;
  esac
done

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

exigir() {
  local caminho
  caminho="$(localizar "$1")"
  [ -n "$caminho" ] || { echo "$1.sql não encontrado em $DIR" >&2; exit 66; }
  echo "$caminho"
}

if [ "$COM_PAPEIS" -eq 1 ]; then
  # Só faz sentido num Postgres cru, fora do Supabase: num projeto Supabase os
  # papéis são da plataforma e já existem. E neste projeto o arquivo é só
  # cabeçalho, porque não há papel próprio nenhum (ver docs §8).
  aplicar "$(exigir roles)"
fi

if [ "$SOMENTE_DADOS" -eq 0 ]; then
  aplicar "$(exigir schema)"
fi

aplicar "$(exigir data)"

echo "Restauração concluída em $(echo "$URL" | sed 's#://[^@]*@#://***@#')"
