// Ponto de entrada do Worker vigia (card 3.10). A lógica está em `vigia.js`.
//
// ⚠️ ESTE ARQUIVO SÓ PODE EXPORTAR HANDLERS. O workerd recusa o Worker inteiro
// quando o módulo de entrada tem export nomeado que não seja função ou handler:
//
//   Uncaught TypeError: Incorrect type for map entry 'CAMINHO_SONDA':
//   the provided value is not of type 'function or ExportedHandler'.
//
// Medido em 02/09/2026 com `wrangler dev`, com tudo num arquivo só. Não é
// preciosismo de organização: é a diferença entre o vigia rodar e o vigia não
// existir. E o modo de falha é da família que este projeto já catalogou — quem
// não abrisse o painel do Cloudflare não saberia; o sintoma seria a ausência de
// e-mail, que é exatamente o que se espera quando está tudo bem.

import { executar, resumir } from './vigia.js';

export default {
  async scheduled(_evento, env) {
    const { resultados, backup, algoRuim, alertaEnviado } = await executar(env);
    const resumo = resumir(resultados, backup);
    console.log(resumo);
    if (algoRuim) {
      // Lançar DEPOIS de alertar deixa a execução vermelha no painel do
      // Cloudflare — segundo sinal, para o caso de o e-mail se perder.
      throw new Error(`${resumo}${alertaEnviado ? ' — alerta enviado' : ''}`);
    }
  },

  // Só para conferir à mão (`wrangler dev`, docs/worker-vigia.md §5). Nunca manda
  // e-mail, e `workers_dev = false` deixa a rota inalcançável em produção.
  async fetch(_requisicao, env) {
    const resultado = await executar(env, { alertar: false });
    return new Response(JSON.stringify(resultado, null, 2), {
      status: resultado.algoRuim ? 503 : 200,
      headers: { 'content-type': 'application/json; charset=utf-8' },
    });
  },
};
