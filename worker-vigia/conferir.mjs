// Roda as duas sondas do vigia com as chaves do ambiente e reprova se alguma
// falhar. Usado em dois lugares:
//
//   - no CI, ANTES de instalar os secrets no Worker (card 3.10): chave errada
//     produziria um e-mail de alarme falso por dia, para sempre, e alarme falso
//     recorrente treina todo mundo a ignorar o alerta de verdade;
//   - na máquina, para conferir os ambientes sem esperar as 06:00.
//
//   SUPABASE_ANON_KEY_DEV=… SUPABASE_ANON_KEY_PROD=… node worker-vigia/conferir.mjs
//
// Importa o MESMO módulo que o Worker executa — se a sonda mudar, muda nos dois.
//
// ⚠️ `process.exitCode` e nunca `process.exit()`: no Windows, sair no meio do
// desmonte do `fetch` derruba o processo com um `Assertion failed` do libuv e um
// código 127 que não tem nada a ver com a sonda (medido em 02/09/2026). Deixar o
// Node terminar sozinho devolve o código certo nos dois sistemas.

import { AMBIENTES, conferirConfiguracao, resumir, sondar } from './src/vigia.js';

const faltando = conferirConfiguracao(process.env, { alertar: false });

if (faltando.length) {
  console.error(`Falta configurar: ${faltando.join(', ')}`);
  process.exitCode = 2;
} else {
  const resultados = [];
  for (const ambiente of AMBIENTES) {
    resultados.push(await sondar(ambiente, process.env));
  }

  console.log(resumir(resultados));

  const falhas = resultados.filter((r) => !r.ok);
  if (falhas.length) {
    console.error(`\nSonda reprovada em: ${falhas.map((f) => f.rotulo).join(', ')}`);
    process.exitCode = 1;
  }
}
