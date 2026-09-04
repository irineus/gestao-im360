// Bateria do guarda de comandos destrutivos — card 5.5,5.
//
// Roda com:  node --test .claude/hooks/
//
// Guarda sem teste apodrece: o primeiro que mexer na regex não tem como saber
// se afrouxou. Cada caso aqui é uma frase sobre o que o guarda deve fazer, e os
// dois grupos importam pelo mesmo motivo — um guarda que só bloqueia é fácil,
// e um que bloqueia demais para a cadeia inteira sem ninguém entender por quê.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HOOK = join(dirname(fileURLToPath(import.meta.url)), 'guarda-destrutivos.mjs');

/** Devolve o código de saída do hook para um comando Bash. 0 = passa, 2 = bloqueia. */
function avaliar(command, tool_name = 'Bash') {
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({ tool_name, tool_input: { command } }),
    encoding: 'utf8',
  });
  return { codigo: r.status, motivo: r.stderr };
}

// O CLI do Supabase escrito por extenso em cada caso, para o teste não depender
// de uma constante que a próxima pessoa mudaria junto com a regra que ela mede.
const RESET = 'supabase db reset';

test('deixa passar o que a suíte local precisa', () => {
  for (const cmd of [
    RESET,
    'supabase test db',
    'supabase start',
    'flutter test',
    'git push -u origin tarefa/5-6-grade-semanal',
    'gh pr create --base develop --title "Card 5.6"',
    'gh pr merge 93 --merge',
  ]) {
    assert.equal(avaliar(cmd).codigo, 0, `deveria passar: ${cmd}`);
  }
});

test('recusa alvo remoto, inclusive escondido atrás de encadeamento', () => {
  for (const cmd of [
    `${RESET} --linked`,
    `git status && ${RESET} --linked`,
    `git status ; ${RESET} --project-ref abcdefghijklmnopqrst`,
    'supabase db dump --db-url postgres://exemplo',
    'supabase db push --linked',
  ]) {
    const { codigo, motivo } = avaliar(cmd);
    assert.equal(codigo, 2, `deveria bloquear: ${cmd}`);
    assert.match(motivo, /BLOQUEADO/);
  }
});

test('recusa qualquer caminho até a branch de produção', () => {
  for (const cmd of ['git push origin main', 'gh pr create --base main --title promo']) {
    assert.equal(avaliar(cmd).codigo, 2, `deveria bloquear: ${cmd}`);
  }
});

// ---------------------------------------------------------------------------
// Os dois casos que a ESTREIA do hook produziu (03/09/2026).
// ---------------------------------------------------------------------------

test('prosa não é comando: heredoc que descreve o perigo passa', () => {
  // Foi exatamente isto que bloqueou a abertura do PR #93: o corpo do PR
  // documentava o guarda, e o guarda leu a documentação como ordem.
  const cmd = [
    'gh pr create --base develop --body-file - <<EOF',
    'O hook recusa a forma remota deste comando:',
    `${RESET} --linked`,
    'e por isso a suíte local segue funcionando.',
    'EOF',
  ].join('\n');

  assert.equal(avaliar(cmd).codigo, 0, 'corpo de heredoc não pode ser lido como comando');
});

test('e a âncora não pode ser contornável por prefixo de ambiente', () => {
  // A correção do caso acima ancorou o casamento no início do segmento. Sem
  // `semPrefixoEnv`, esta linha deixaria de casar — a correção de um
  // falso-positivo teria aberto um falso-negativo, que é bem pior.
  assert.equal(avaliar(`PGPASSWORD=x ${RESET} --linked`).codigo, 2);
});

test('ferramenta que não é Bash passa direto', () => {
  assert.equal(avaliar('qualquer coisa', 'Read').codigo, 0);
});

test('entrada inválida não vira portão que reprova tudo', () => {
  const r = spawnSync(process.execPath, [HOOK], { input: 'isto não é json', encoding: 'utf8' });
  assert.equal(r.status, 0, 'hook quebrado tem de falhar ABERTO — travar o projeto é pior');
});
