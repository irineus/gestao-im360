#!/usr/bin/env node
// Guarda de comandos destrutivos — card 5.5,5 (cadeia de execução headless).
//
// POR QUE ESTE ARQUIVO EXISTE
// --------------------------
// Até 03/09/2026 o `.claude/settings.json` negava `supabase db reset` por
// prefixo. A negação era certa no motivo e errada na forma: o que destrói banco
// é `db reset --linked` (ou com `--db-url` / `--project-ref`), que aplica pgTAP
// e a escola-fixture no banco REMOTO — o `db reset` local é justamente o passo
// que o `testes.yml` roda para provar que a sequência de migrações sobe limpa.
//
// Negar os dois juntos custava um clique por sessão interativa. Em sessão
// NÃO INTERATIVA (a cadeia do card 5.5,5) não há clique: a negação mata a
// execução no primeiro card, e o sintoma é uma sessão que não consegue rodar a
// suíte. Este hook separa os dois casos — libera o local, recusa o remoto — e
// de quebra fecha buracos que a negação por prefixo nunca pegou: o comando
// encadeado (`algo && supabase db reset --linked`) passava batido.
//
// CONTRATO DO HOOK
// ----------------
// Recebe o evento PreToolUse em JSON no stdin. Sai com 0 para deixar passar e
// com 2 para BLOQUEAR — nesse caso o stderr volta para o Claude como motivo.
// Qualquer erro interno sai com 0: um hook quebrado não pode virar um portão
// que reprova tudo (falha aberta é ruim; falha que trava o projeto é pior, e
// aqui o resto das proteções — allow/deny do settings — continua de pé).

let bruto = '';
process.stdin.on('data', (p) => (bruto += p));
process.stdin.on('end', () => {
  try {
    avaliar(JSON.parse(bruto));
  } catch {
    process.exit(0); // ver nota acima: hook quebrado não bloqueia.
  }
});

/** Flags que apontam o comando para um banco que não é o stack local. */
const ALVO_REMOTO = /(^|\s)(--linked|--db-url(=|\s)|--project-ref(=|\s)|-p\s+[a-z]{20})/;

/** Subcomandos do CLI do Supabase que escrevem no banco de destino. */
const SUPABASE_ESCRITA = /^supabase\s+db\s+(reset|push|dump)(\s|$)/;

function avaliar(evento) {
  if (evento?.tool_name !== 'Bash') process.exit(0);
  const comando = String(evento?.tool_input?.command ?? '');

  for (const trecho of fatiar(comando)) {
    const motivo = recusar(trecho);
    if (motivo) {
      process.stderr.write(motivo);
      process.exit(2);
    }
  }
  process.exit(0);
}

/**
 * Quebra a linha nos operadores de encadeamento antes de olhar cada pedaço.
 *
 * Sem isto a checagem é enganável por `git status && supabase db reset --linked`
 * — a negação por prefixo do settings.json só olhava o começo da linha, e era
 * exatamente essa a brecha.
 */
function fatiar(comando) {
  return semHeredoc(comando)
    .split(/&&|\|\||;|\||\n/)
    .map((t) => semPrefixoEnv(t.trim()))
    .filter(Boolean);
}

/**
 * Apaga o corpo de `<<EOF … EOF`, preservando a linha do comando.
 *
 * Achado na ESTREIA do hook (03/09/2026): o corpo do PR que documentava este
 * guarda continha a forma remota do `db reset`, viajava dentro de
 * `gh pr create <<EOF`, e o guarda leu prosa como se fosse ordem. Comando não é
 * o texto que ele carrega — sem isto, escrever documentação sobre migração
 * vira ação proibida, e as sessões deste projeto escrevem isso o tempo todo.
 */
function semHeredoc(comando) {
  return comando.replace(
    /<<-?\s*(['"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n[\s\S]*?^\s*\2\s*$/gm,
    ' <heredoc> '
  );
}

/** Tira `VAR=valor ` da frente, senão a âncora do §1 seria contornável. */
function semPrefixoEnv(trecho) {
  return trecho.replace(/^(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)+/, '');
}

/** Devolve o motivo da recusa, ou `null` para deixar passar. */
function recusar(trecho) {
  if (SUPABASE_ESCRITA.test(trecho) && ALVO_REMOTO.test(trecho)) {
    return (
      'BLOQUEADO pelo guarda-destrutivos: `supabase db reset/push/dump` apontado para banco REMOTO ' +
      '(--linked / --db-url / --project-ref).\n' +
      'Migração em dev e prod entra SOMENTE pelo CI/CD (.github/workflows/db-migrations.yml): ' +
      'push em `develop` aplica no dev, merge em `main` aplica no prod.\n' +
      'Para rodar a suíte local, use `supabase db reset` SEM alvo remoto, contra o stack do ' +
      '`supabase start`.'
    );
  }

  if (/^git\s+push\b/.test(trecho) && /(^|\s|:)main(\s|$)/.test(trecho)) {
    return (
      'BLOQUEADO pelo guarda-destrutivos: `git push` mirando `main`.\n' +
      'A promoção develop → main é manual e de Irineu (aplica migração em PRODUÇÃO). ' +
      'Nenhuma sessão promove sozinha — nem interativa, nem na cadeia do card 5.5,5.'
    );
  }

  if (/^gh\s+pr\s+create\b/.test(trecho) && /--base(=|\s+)main(\s|$)/.test(trecho)) {
    return (
      'BLOQUEADO pelo guarda-destrutivos: `gh pr create --base main`.\n' +
      'PR de promoção para produção é aberto por Irineu, não por sessão automática.'
    );
  }

  return null;
}
