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

/**
 * O backup semanal de produção (card 3.11), vigiado a partir daqui desde o card
 * 3.12.
 *
 * ⚠️ POR QUE ESTA VERIFICAÇÃO EXISTE, e ela é o oposto de zelo: o card 3.11
 * registrou um modo de falha silencioso do próprio backup — **o GitHub desativa
 * workflow agendado em repositório com 60 dias sem commit**, e o risco vira real
 * justamente quando o desenvolvimento parar, que é quando ninguém mais está
 * olhando o painel de Actions. O backup pararia de sair sem uma linha de aviso,
 * e a descoberta seria no dia em que ele fizesse falta. Quem vigia o vigia é
 * outra infraestrutura: o backup mora no GitHub, isto roda no Cloudflare.
 *
 * A idade sai do **prefixo de data da cópia**, não do `uploaded` do objeto: o
 * prefixo é a data do DUMP, e é essa que responde "quão velho é o dado que eu
 * teria de volta". `uploaded` responde outra coisa — recopiar um backup velho o
 * deixaria novinho, e a idade mentiria exatamente na hora errada.
 */
export const BACKUP = {
  /** `s3://<bucket>/producao/YYYY-MM-DD/…` (backup-semanal.yml, "Publicar no R2"). */
  prefixo: 'producao/',
  /**
   * Asserção POSITIVA, pela mesma razão que a sonda não se contenta com "não
   * deu erro": prefixo que existe passaria com a pasta vazia. `data.sql.gz` é
   * a razão de o backup existir — o card 3.11 anota que dump de schema sem dado
   * é o jeito mais comum de um backup ser inútil — e o MANIFESTO é o que o
   * workflow escreve por último a mais, marcando cópia completa.
   */
  exigidos: ['data.sql.gz', 'MANIFESTO.txt'],
  /**
   * O backup é semanal (domingo). Em operação normal a cópia mais nova tem no
   * máximo 7 dias; 9 dá folga para uma execução atrasada sem alarme falso e
   * ainda denuncia a PRIMEIRA semana perdida, em vez de esperar a segunda.
   */
  idadeMaximaDias: 9,
};

/**
 * Decide sobre o backup a partir da lista de chaves. Pura de propósito: é o que
 * permite exercitar bucket vazio, cópia incompleta e cópia velha sem R2 nenhum.
 */
export function avaliarBackup(chaves, opcoes = {}) {
  const { quando = new Date(), idadeMaximaDias = BACKUP.idadeMaximaDias } = opcoes;

  const porData = new Map();
  for (const chave of chaves) {
    const partes = /^producao\/(\d{4}-\d{2}-\d{2})\/(.+)$/.exec(chave);
    if (!partes) continue;
    if (!porData.has(partes[1])) porData.set(partes[1], new Set());
    porData.get(partes[1]).add(partes[2]);
  }

  if (porData.size === 0) {
    return { ok: false, motivo: 'o bucket não tem nenhuma cópia em `producao/`' };
  }

  // Prefixos são datas ISO, então ordem alfabética é ordem cronológica — a
  // mesma propriedade de que a retenção do card 3.11 depende.
  const data = [...porData.keys()].sort().at(-1);
  const arquivos = porData.get(data);
  const idadeDias = Math.floor((quando.getTime() - Date.parse(`${data}T00:00:00Z`)) / 86400000);

  const faltando = BACKUP.exigidos.filter((nome) => !arquivos.has(nome));
  if (faltando.length) {
    return { ok: false, data, idadeDias, motivo: `a cópia de ${data} está incompleta: falta ${faltando.join(', ')}` };
  }
  if (idadeDias < 0) {
    return { ok: false, data, idadeDias, motivo: `a cópia mais nova é de ${data}, uma data no futuro` };
  }
  if (idadeDias > idadeMaximaDias) {
    return { ok: false, data, idadeDias, motivo: `a cópia mais nova é de ${data}, ${idadeDias} dias atrás (limite: ${idadeMaximaDias})` };
  }
  return { ok: true, data, idadeDias };
}

/**
 * Lê o bucket e avalia.
 *
 * **Não lança, e isso é decisão**: qualquer problema aqui — binding ausente, R2
 * fora do ar — vira `ok: false` com motivo, e não uma exceção. Uma exceção
 * derrubaria a execução ANTES das sondas do Supabase, trocando uma proteção que
 * funciona por outra que acabou de nascer. Falhar aqui alerta; falhar aqui não
 * cega o resto.
 */
export async function conferirBackup(env, opcoes = {}) {
  const balde = opcoes.balde ?? env?.BACKUP;
  if (!balde) {
    return {
      ok: false,
      motivo: 'o binding R2 `BACKUP` não existe neste Worker — ver worker-vigia/wrangler.toml e docs/backup-restauracao.md §6',
    };
  }

  try {
    const chaves = [];
    let cursor;
    do {
      const pagina = await balde.list({ prefix: BACKUP.prefixo, limit: 1000, cursor });
      for (const objeto of pagina.objects ?? []) chaves.push(objeto.key);
      cursor = pagina.truncated ? pagina.cursor : undefined;
    } while (cursor);
    return avaliarBackup(chaves, opcoes);
  } catch (erro) {
    return { ok: false, motivo: `não consegui ler o bucket: ${erro?.message ?? erro}` };
  }
}

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

/**
 * Monta o e-mail. `backup` é opcional e só entra quando reprovou.
 *
 * Continua sendo **um e-mail por execução** (decisão do card 3.10): dois
 * assuntos num envelope, e não dois envelopes. Alerta que se multiplica é
 * alerta que se aprende a arquivar sem ler.
 */
export function montarAlerta(falhas, quando = new Date(), backup = null) {
  const nomes = falhas.map((f) => f.rotulo).join(' e ');
  const backupRuim = backup && !backup.ok;

  const abertura = falhas.length
    ? `O vigia diário não conseguiu falar com o Supabase de ${nomes}.`
    : 'O vigia diário encontrou um problema no backup de produção.';

  const linhas = [abertura, '', `Quando: ${emSaoPaulo(quando)} (São Paulo)`, ''];

  for (const falha of falhas) {
    linhas.push(`── ${falha.rotulo}`);
    linhas.push(`   ${falha.alvo}`);
    falha.tentativas.forEach((t, i) => linhas.push(`   tentativa ${i + 1}: ${descreverTentativa(t)}`));
    linhas.push('');
  }

  if (backupRuim) {
    linhas.push('── backup semanal de produção');
    linhas.push(`   ${backup.motivo}`);
    linhas.push('');
  }

  if (falhas.length) {
    linhas.push('O que verificar no Supabase, nesta ordem:');
    linhas.push('1. O projeto está pausado? Painel do Supabase → Restore project.');
    linhas.push('   Projeto pausado é o app fora do ar, não só a sonda falhando.');
    linhas.push('2. A chave publicável foi rotacionada? Então o alerta é falso, e o');
    linhas.push('   segredo SUPABASE_ANON_KEY_* do repositório precisa ser atualizado');
    linhas.push('   junto com o bundle publicado (docs/worker-vigia.md §3).');
    linhas.push('3. Fora isso, é indisponibilidade do Supabase — status.supabase.com.');
    linhas.push('');
  }

  if (backupRuim) {
    linhas.push('O que verificar no backup, nesta ordem:');
    linhas.push('1. O workflow `backup-semanal` foi DESATIVADO? O GitHub desliga');
    linhas.push('   workflow agendado em repositório com 60 dias sem commit, e não');
    linhas.push('   avisa — é o modo de falha que este aviso existe para pegar.');
    linhas.push('   Actions → backup-semanal → Enable workflow.');
    linhas.push('2. A última execução ficou vermelha? O log diz em que passo parou;');
    linhas.push('   dump reprovado NÃO é publicado, de propósito (card 3.11).');
    linhas.push('3. O bucket ou os segredos do R2 mudaram? docs/backup-restauracao.md §6.');
    linhas.push('');
    linhas.push('Um `workflow_dispatch` do backup-semanal resolve a semana corrente;');
    linhas.push('só não resolve a causa, e a causa volta no domingo seguinte.');
    linhas.push('');
  }

  linhas.push('Enquanto durar, este e-mail chega uma vez por dia. Silêncio amanhã');
  linhas.push('significa que voltou — o vigia não guarda estado e não avisa recuperação.');

  const assunto = falhas.length
    ? `[Gestão IM360] Supabase de ${nomes} não respondeu${backupRuim ? ' — e o backup está atrasado' : ''}`
    : '[Gestão IM360] O backup de produção não está saindo';

  return { assunto, texto: linhas.join('\n') };
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

export function resumir(resultados, backup = null) {
  const sondas = resultados
    .map((r) => `${r.rotulo}: ${r.ok ? 'ok' : 'FALHOU'} (${r.tentativas.map(descreverTentativa).join(' | ')})`)
    .join(' — ');
  if (!backup) return sondas;
  const dito = backup.ok
    ? `backup: ok (cópia de ${backup.data}, ${backup.idadeDias} dia(s))`
    : `backup: FALHOU (${backup.motivo})`;
  return `${sondas} — ${dito}`;
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

  // O backup é conferido DEPOIS das sondas e sem poder derrubá-las (card 3.12):
  // `conferirBackup` devolve motivo em vez de lançar. Vigia novo não pode custar
  // a vigilância que já funcionava.
  const backup = await conferirBackup(env, { ...resto, quando });

  const falhas = resultados.filter((r) => !r.ok);
  const algoRuim = falhas.length > 0 || !backup.ok;
  let alertaEnviado = false;

  if (algoRuim && alertar) {
    try {
      await enviarAlerta(env, montarAlerta(falhas, quando, backup), resto.buscar ?? fetch);
      alertaEnviado = true;
    } catch (erro) {
      // O alerta que não sai é a falha mais cara das duas: a primeira alguém
      // ainda descobre abrindo o app, a segunda ninguém descobre nunca.
      throw new Error(`${resumir(resultados, backup)} — E O ALERTA NÃO SAIU: ${erro.message}`, {
        cause: erro,
      });
    }
  }

  return { resultados, falhas, backup, algoRuim, alertaEnviado };
}
