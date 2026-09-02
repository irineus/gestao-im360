// Vigia — a lógica (card 3.10). O ponto de entrada do Worker é `src/index.js`.
//
// ⚠️ Este arquivo NÃO pode ser o `main` do wrangler. O workerd exige que todo
// export nomeado do módulo de entrada seja função ou handler, e recusa o Worker
// INTEIRO com "Incorrect type for map entry 'CAMINHO_SONDA': the provided value
// is not of type 'function or ExportedHandler'" (medido em 02/09/2026 com
// `wrangler dev`). Daí a separação: aqui ficam as constantes e as funções, que
// é o que a suíte e o `conferir.mjs` importam; lá fica só o `export default`.
//
// Faz duas coisas com a MESMA requisição diária:
//
//   1. mantém os dois projetos Supabase acordados — o free tier pausa projeto
//      com 7 dias sem atividade, e projeto pausado é o app fora do ar
//      (Decisões vigentes §1, "Free tier", e risco 1 do plano §4);
//   2. vigia — se a requisição não devolver o que tem de devolver, manda
//      e-mail. É a mesma sonda: se o `select` diário NÃO estiver evitando a
//      pausa, quem descobre é este próprio Worker, no dia em que a resposta
//      deixar de vir. A medida e a verificação da medida são o mesmo ato.
//
// Sem dependência nenhuma de propósito: `fetch`, `JSON` e `Intl` bastam, então
// não há `node_modules`, não há build e o arquivo roda igual no workerd (produção),
// no `wrangler dev` (local) e no `node --test` (suíte). Ver docs/worker-vigia.md.

/**
 * Os dois ambientes vigiados. As URLs são públicas — estão no bundle que todo
 * visitante baixa e em `.github/workflows/deploy-web.yml`. As chaves não ficam
 * aqui: entram por secret do Worker, pelo mesmo motivo do card 3.9 (rotacionar
 * a chave não pode exigir um commit).
 */
export const AMBIENTES = [
  {
    nome: 'homologacao',
    rotulo: 'homologação',
    url: 'https://ncdfolxdupbbfvtydngx.supabase.co',
    chave: 'SUPABASE_ANON_KEY_DEV',
    app: 'https://homolog.gestaoim360.com',
  },
  {
    nome: 'producao',
    rotulo: 'produção',
    url: 'https://aqfuawrygxsiopyppjza.supabase.co',
    chave: 'SUPABASE_ANON_KEY_PROD',
    app: 'https://app.gestaoim360.com',
  },
];

/**
 * A sonda: um `select` de uma coluna e uma linha em `parametro`, com a chave
 * publicável.
 *
 * A resposta CERTA é `[]`, e isso é a especificação, não um sintoma: `anon` não
 * satisfaz nenhuma política de `select` (card 3.4), então a RLS devolve zero
 * linhas. O que a resposta prova é o que interessa aqui — o PostgREST executou
 * uma consulta num Postgres vivo. Sem banco de pé ele não responde 200: devolve
 * 503/PGRST001, e projeto pausado não responde nem isso.
 *
 * Medido em 02/09/2026 contra o projeto de desenvolvimento:
 *   sonda com chave válida ...... 200  []
 *   chave inválida .............. 401  {"message":"Invalid API key"}
 *   sem chave nenhuma ........... 401  {"message":"No API key found in request"}
 *   tabela inexistente .......... 404  PGRST205 (vem do cache de schema, não do banco)
 *
 * Por isso a asserção é POSITIVA — 200 **e** corpo que é uma lista JSON. Modo de
 * falha que ninguém previu continua reprovando, porque não precisa ser previsto.
 */
export const CAMINHO_SONDA = '/rest/v1/parametro?select=chave&limit=1';

/** Remetente do alerta. O Resend do card 3.8 serve `gestaoim360.com`; o nome
 *  distingue quem mandou, como já distingue dev de prod na caixa de entrada. */
export const REMETENTE_PADRAO = 'Gestão IM360 (Vigia) <nao-responda@gestaoim360.com>';

/**
 * O que precisa estar configurado. Conferido no INÍCIO de toda execução, e não
 * no dia em que der problema: `RESEND_API_KEY` ausente só apareceria na primeira
 * falha real — justamente o dia em que o alerta tem de sair.
 */
export function conferirConfiguracao(env, { alertar = true } = {}) {
  const obrigatorias = AMBIENTES.map((a) => a.chave);
  if (alertar) obrigatorias.push('RESEND_API_KEY', 'ALERTA_PARA');
  return obrigatorias.filter((nome) => !env?.[nome]);
}

const dormirDeVerdade = (ms) => new Promise((resolver) => setTimeout(resolver, ms));

async function umaTentativa(alvo, chave, buscar, timeoutMs) {
  const inicio = Date.now();
  const ms = () => Date.now() - inicio;
  try {
    const resposta = await buscar(alvo, {
      method: 'GET',
      headers: {
        // Os dois cabeçalhos de propósito: a chave publicável (`sb_publishable_…`)
        // funciona só com `apikey`, mas a chave legada é um JWT e é o
        // `Authorization` que lhe dá o papel. Mandar os dois vale para as duas
        // — medido com a chave publicável do dev em 02/09/2026, HTTP 200.
        apikey: chave,
        Authorization: `Bearer ${chave}`,
        Accept: 'application/json',
      },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const texto = (await resposta.text()).slice(0, 300);
    if (resposta.status !== 200) {
      return { ok: false, status: resposta.status, corpo: texto, ms: ms() };
    }
    let corpo;
    try {
      corpo = JSON.parse(texto);
    } catch {
      return { ok: false, status: 200, corpo: texto, motivo: 'a resposta não é JSON', ms: ms() };
    }
    if (!Array.isArray(corpo)) {
      return { ok: false, status: 200, corpo: texto, motivo: 'o JSON não é uma lista', ms: ms() };
    }
    return { ok: true, status: 200, linhas: corpo.length, ms: ms() };
  } catch (erro) {
    return { ok: false, motivo: String(erro?.message ?? erro), ms: ms() };
  }
}

/**
 * Sonda um ambiente, com repetição. Três tentativas porque uma falha isolada de
 * rede não é notícia — e-mail que chega sem motivo é e-mail que se aprende a
 * ignorar, que é o mesmo desfecho de não ter alerta nenhum.
 */
export async function sondar(ambiente, env, opcoes = {}) {
  const {
    buscar = fetch,
    tentativas = 3,
    esperaMs = 1500,
    timeoutMs = 10000,
    dormir = dormirDeVerdade,
  } = opcoes;

  const alvo = ambiente.url + CAMINHO_SONDA;
  const registros = [];

  for (let n = 1; n <= tentativas; n += 1) {
    const registro = await umaTentativa(alvo, env[ambiente.chave], buscar, timeoutMs);
    registros.push(registro);
    if (registro.ok) break;
    if (n < tentativas) await dormir(esperaMs);
  }

  return {
    ambiente: ambiente.nome,
    rotulo: ambiente.rotulo,
    alvo,
    ok: registros[registros.length - 1].ok,
    tentativas: registros,
  };
}

function descreverTentativa(t) {
  const partes = [];
  if (t.status) partes.push(`HTTP ${t.status}`);
  if (t.motivo) partes.push(t.motivo);
  if (t.corpo) partes.push(t.corpo.replace(/\s+/g, ' ').trim());
  if (t.ok) partes.push(`${t.linhas} linha(s)`);
  partes.push(`${t.ms} ms`);
  return partes.join(' · ');
}

function emSaoPaulo(quando) {
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: 'America/Sao_Paulo',
    dateStyle: 'short',
    timeStyle: 'medium',
  }).format(quando);
}

export function montarAlerta(falhas, quando = new Date()) {
  const nomes = falhas.map((f) => f.rotulo).join(' e ');
  const linhas = [
    `O vigia diário não conseguiu falar com o Supabase de ${nomes}.`,
    '',
    `Quando: ${emSaoPaulo(quando)} (São Paulo)`,
    '',
  ];

  for (const falha of falhas) {
    linhas.push(`── ${falha.rotulo}`);
    linhas.push(`   ${falha.alvo}`);
    falha.tentativas.forEach((t, i) => linhas.push(`   tentativa ${i + 1}: ${descreverTentativa(t)}`));
    linhas.push('');
  }

  linhas.push('O que verificar, nesta ordem:');
  linhas.push('1. O projeto está pausado? Painel do Supabase → Restore project.');
  linhas.push('   Projeto pausado é o app fora do ar, não só a sonda falhando.');
  linhas.push('2. A chave publicável foi rotacionada? Então o alerta é falso, e o');
  linhas.push('   segredo SUPABASE_ANON_KEY_* do repositório precisa ser atualizado');
  linhas.push('   junto com o bundle publicado (docs/worker-vigia.md §3).');
  linhas.push('3. Fora isso, é indisponibilidade do Supabase — status.supabase.com.');
  linhas.push('');
  linhas.push('Enquanto durar, este e-mail chega uma vez por dia. Silêncio amanhã');
  linhas.push('significa que voltou — o vigia não guarda estado e não avisa recuperação.');

  return { assunto: `[Gestão IM360] Supabase de ${nomes} não respondeu`, texto: linhas.join('\n') };
}

export async function enviarAlerta(env, alerta, buscar = fetch) {
  const resposta = await buscar('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: env.ALERTA_DE || REMETENTE_PADRAO,
      to: [env.ALERTA_PARA],
      subject: alerta.assunto,
      text: alerta.texto,
    }),
  });
  if (!resposta.ok) {
    const corpo = (await resposta.text()).slice(0, 300);
    throw new Error(`Resend recusou o alerta: HTTP ${resposta.status} ${corpo}`);
  }
  return resposta.status;
}

export function resumir(resultados) {
  return resultados
    .map((r) => `${r.rotulo}: ${r.ok ? 'ok' : 'FALHOU'} (${r.tentativas.map(descreverTentativa).join(' | ')})`)
    .join(' — ');
}

/**
 * Uma execução completa. Devolve o que aconteceu; quem decide ficar vermelho é
 * o chamador.
 */
export async function executar(env, opcoes = {}) {
  const { alertar = true, quando = new Date(), ...resto } = opcoes;

  const faltando = conferirConfiguracao(env, { alertar });
  if (faltando.length) {
    throw new Error(
      `Vigia sem configuração: ${faltando.join(', ')}. Ver docs/worker-vigia.md §3.`,
    );
  }

  const resultados = [];
  for (const ambiente of AMBIENTES) {
    resultados.push(await sondar(ambiente, env, resto));
  }

  const falhas = resultados.filter((r) => !r.ok);
  let alertaEnviado = false;

  if (falhas.length && alertar) {
    try {
      await enviarAlerta(env, montarAlerta(falhas, quando), resto.buscar ?? fetch);
      alertaEnviado = true;
    } catch (erro) {
      // O alerta que não sai é a falha mais cara das duas: a primeira alguém
      // ainda descobre abrindo o app, a segunda ninguém descobre nunca.
      throw new Error(`${resumir(resultados)} — E O ALERTA NÃO SAIU: ${erro.message}`, {
        cause: erro,
      });
    }
  }

  return { resultados, falhas, alertaEnviado };
}
