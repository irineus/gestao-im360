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
#   --apenas-schemas public,auth
#                     restaura só os blocos COPY desses schemas. O ARQUIVO
#                     continua completo; o que muda é o que se aplica AGORA.
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
APENAS_SCHEMAS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --somente-dados)  SOMENTE_DADOS=1 ;;
    --com-papeis)     COM_PAPEIS=1 ;;
    --apenas-schemas) shift; APENAS_SCHEMAS="${1:-}"
                      [ -n "$APENAS_SCHEMAS" ] || { echo "--apenas-schemas exige uma lista" >&2; exit 64; } ;;
    *) echo "modo desconhecido: $1" >&2; exit 64 ;;
  esac
  shift
done

# Devolve o caminho do arquivo, seja ele .sql ou .sql.gz; vazio se não existir.
localizar() {
  local nome="$1"
  if   [ -f "$DIR/$nome.sql" ];    then echo "$DIR/$nome.sql"
  elif [ -f "$DIR/$nome.sql.gz" ]; then echo "$DIR/$nome.sql.gz"
  fi
}

# Deixa passar só os blocos COPY dos schemas pedidos. Um bloco COPY termina numa
# linha com `\.` sozinha, e `pg_dump` escapa esse par quando ele aparece dentro
# de um valor — então o delimitador é confiável.
filtrar_schemas() {
  awk -v alvos="$APENAS_SCHEMAS" '
    # `fim` é a linha que encerra um bloco COPY: contrabarra seguida de ponto.
    # Montada com sprintf de propósito — escrita como literal, ela atravessaria
    # as camadas de escape do shell, do awk e do YAML, e basta uma delas comê-la
    # para o filtro parar de reconhecer o fim do bloco e engolir TODO o resto do
    # arquivo em silêncio. Foi o que aconteceu na primeira versão deste filtro.
    BEGIN { n = split(alvos, a, ","); for (i = 1; i <= n; i++) ok[a[i]] = 1
            fim = sprintf("%c.", 92) }
    pulando { if ($0 == fim) pulando = 0; next }
    /^COPY / {
      linha = $0
      sub(/^COPY +/, "", linha); gsub(/"/, "", linha)
      split(linha, parte, ".")
      if (!(parte[1] in ok)) { pulando = 1; next }
    }
    { print }
  '
}

aplicar() {
  local arquivo="$1"
  local filtrar="${2:-nao}"
  if [ "$filtrar" = "sim" ] && [ -n "$APENAS_SCHEMAS" ]; then
    echo "── aplicando $arquivo (apenas os schemas: $APENAS_SCHEMAS)"
  else
    echo "── aplicando $arquivo"
    filtrar="nao"
  fi
  # `--single-transaction`: ou entra tudo, ou não entra nada. Restauração parcial
  # é a pior das três hipóteses, porque parece sucesso.
  local ler=(cat "$arquivo")
  [[ "$arquivo" == *.gz ]] && ler=(gzip -dc "$arquivo")
  if [ "$filtrar" = "sim" ]; then
    "${ler[@]}" | filtrar_schemas | psql "$URL" -v ON_ERROR_STOP=1 --single-transaction -q -f -
  else
    "${ler[@]}" | psql "$URL" -v ON_ERROR_STOP=1 --single-transaction -q -f -
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

aplicar "$(exigir data)" sim

echo "Restauração concluída em $(echo "$URL" | sed 's#://[^@]*@#://***@#')"
