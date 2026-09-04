#!/usr/bin/env node
// Exercita o guarda-destrutivos com os casos que ele existe para separar.
//
// Roda com `node .claude/hooks/guarda-destrutivos.teste.mjs`. Sai 0 com tudo
// certo, 1 no primeiro caso divergente.
//
// ⚠️ Os comandos proibidos vivem AQUI, num arquivo, e não na linha de comando de
// quem testa: escrever `supabase db push --linked` direto no terminal faz o
// próprio guarda barrar o teste do guarda (medido em 04/09/2026). É a mesma
// lição do `semHeredoc` — comando não é o texto que ele carrega.

import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HOOK = join(dirname(fileURLToPath(import.meta.url)), 'guarda-destrutivos.mjs');

/** `true` = tem de BLOQUEAR; `false` = tem de deixar passar. */
const CASOS = [
  // --- o que este projeto faz o tempo todo, e não pode travar ---------------
  ['supabase db reset', false, 'o reset LOCAL é o passo do testes.yml'],
  ['supabase start', false, 'subir o stack local'],
  ['git push -u origin tarefa/5-11-correcoes', false, 'branch de tarefa'],
  ['gh pr create --base develop --title x', false, 'PR de tarefa'],
  ['gh pr checks 109 --watch', false, 'esperar o CI'],

  // --- banco remoto: migração entra só pelo CI/CD ---------------------------
  ['supabase db reset --linked', true, 'reset no banco remoto'],
  ['supabase db push --linked', true, 'push de migração no remoto'],
  ['git status && supabase db push --linked', true, 'encadeado — a brecha do settings'],
  ['FOO=1 supabase db reset --linked', true, 'prefixo de env não contorna'],

  // --- promoção para produção: é de Irineu ----------------------------------
  ['git push origin HEAD:main', true, 'push mirando main'],
  ['git push origin develop:main', true, 'push mirando main'],
  [
    'git push origin refs/heads/develop:refs/heads/main',
    true,
    'main depois de barra — passava antes de 04/09/2026',
  ],
  ['gh pr create --base main --title x', true, 'abertura do PR de promoção'],
  ['gh pr create -B main --title x', true, 'forma CURTA de --base, que passava antes'],

  // --- documentação sobre o que é proibido continua sendo documentação ------
  [
    ['gh pr create --base develop --body-file - <<EOF', 'roda supabase db reset --linked no CI', 'EOF'].join('\n'),
    false,
    'prosa dentro de heredoc não é ordem',
  ],
];

let falhas = 0;
for (const [comando, deveBloquear, porque] of CASOS) {
  const r = spawnSync(process.execPath, [HOOK], {
    input: JSON.stringify({ tool_name: 'Bash', tool_input: { command: comando } }),
    encoding: 'utf8',
  });
  const bloqueou = r.status === 2;
  const ok = bloqueou === deveBloquear;
  if (!ok) falhas++;
  const rotulo = comando.replace(/\n/g, ' ⏎ ').slice(0, 58).padEnd(58);
  console.log(`${ok ? 'ok  ' : 'FALHA'} ${rotulo} ${deveBloquear ? 'bloqueia' : 'passa'} — ${porque}`);
}

// ⚠️ `gh pr merge` não entra na tabela acima: a base do PR não está no comando,
// então o guarda PERGUNTA ao `gh`, e o resultado depende de rede e de um PR que
// exista. Testá-lo aqui faria a suíte falhar offline — exatamente o que o
// cabeçalho do guarda diz para não fazer. A regra fica coberta pela revisão do
// código e pelo próprio uso.
console.log(`\n${CASOS.length - falhas}/${CASOS.length} casos.`);
process.exit(falhas === 0 ? 0 : 1);
