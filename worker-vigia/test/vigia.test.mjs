// Suíte do vigia (card 3.10). `node --test`, sem dependência nenhuma —
// nem vitest, nem node_modules, nem passo de instalação no CI.
//
// O que estes testes protegem é o modo de falha que o resto do projeto já
// catalogou meia dúzia de vezes: a resposta que passa com cara de certo. Um
// vigia que aceita qualquer 200 é pior do que nenhum, porque dá a impressão de
// que alguém está olhando.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import * as entrada from '../src/index.js';
import {
  AMBIENTES,
  BACKUP,
  BATIMENTO,
  CAMINHO_SONDA,
  ROTINA,
  avaliarBackup,
  avaliarRotina,
  baterPonto,
  conferirBackup,
  conferirConfiguracao,
  conferirRotina,
  descreverBatimento,
  executar,
  montarAlerta,
  resumir,
  sondar,
} from '../src/vigia.js';

const padrao = entrada.default;

const AMBIENTE_COMPLETO = {
  SUPABASE_ANON_KEY_DEV: 'chave-dev',
  SUPABASE_ANON_KEY_PROD: 'chave-prod',
  RESEND_API_KEY: 'chave-resend',
  ALERTA_PARA: 'alguem@exemplo.test',
};

const semEspera = { dormir: async () => {}, esperaMs: 0 };

/** Data fixa: o vigia roda 09:00 UTC = 06:00 em São Paulo. */
const AGORA = new Date('2026-09-02T09:00:00Z');

/** Chaves de uma cópia completa naquela data. */
const copia = (data) =>
  ['roles.sql.gz', 'schema.sql.gz', 'data.sql.gz', 'MANIFESTO.txt'].map(
    (nome) => `producao/${data}/${nome}`,
  );

/** Bucket R2 de mentira, com a paginação que o `list` de verdade tem. */
function baldeFalso(chaves, { porPagina = 1000, quebrar = null } = {}) {
  return {
    async list({ cursor } = {}) {
      if (quebrar) throw quebrar;
      const inicio = cursor ? Number(cursor) : 0;
      const fatia = chaves.slice(inicio, inicio + porPagina);
      const fim = inicio + fatia.length;
      return {
        objects: fatia.map((key) => ({ key })),
        truncated: fim < chaves.length,
        cursor: String(fim),
      };
    },
  };
}

/** Backup saudável: cópia de anteontem, completa. */
const backupBom = { balde: baldeFalso(copia('2026-08-31')), quando: AGORA };

/** A rotina de hoje: 03:10 em São Paulo = 06:10 UTC, ~3 h antes do vigia. */
const ROTINA_DE_HOJE = JSON.stringify('2026-09-02T06:10:00.123+00:00');

/**
 * Embrulha um fetch de mentira para responder à pergunta da rotina (card
 * 9.2,66) — POST em `/rpc/` — e deixar o resto com quem já respondia.
 */
function comRotina(buscar, corpo = ROTINA_DE_HOJE) {
  const embrulhado = async (url, opcoes) =>
    url.includes('/rpc/') ? resposta(200, corpo) : buscar(url, opcoes);
  embrulhado.chamadas = buscar.chamadas;
  return embrulhado;
}

function resposta(status, corpo) {
  return { status, ok: status >= 200 && status < 300, text: async () => corpo };
}

/** fetch de mentira: devolve as respostas na ordem, guardando as chamadas. */
function buscarFalso(respostas) {
  const chamadas = [];
  const fila = [...respostas];
  const buscar = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    const proxima = fila.length > 1 ? fila.shift() : fila[0];
    if (proxima instanceof Error) throw proxima;
    return proxima;
  };
  buscar.chamadas = chamadas;
  return buscar;
}

test('o módulo de entrada só exporta handler', () => {
  // Portão do defeito medido em 02/09/2026: com as constantes exportadas no
  // `main`, o workerd recusa o Worker INTEIRO — "Incorrect type for map entry
  // 'CAMINHO_SONDA': the provided value is not of type 'function or
  // ExportedHandler'" — e o vigia simplesmente não existe. O sintoma é a
  // ausência de e-mail, que é exatamente o que se espera quando está tudo bem.
  // Uma linha `export const` de volta em `src/index.js` reprova aqui.
  for (const [nome, valor] of Object.entries(entrada)) {
    if (nome === 'default') continue;
    assert.equal(typeof valor, 'function', `export nomeado '${nome}' não é função — o workerd recusa`);
  }
  assert.equal(typeof padrao.scheduled, 'function');
  assert.equal(typeof padrao.fetch, 'function');
});

test('conferirConfiguracao nomeia o que falta, e só o que vai ser usado', () => {
  assert.deepEqual(conferirConfiguracao(AMBIENTE_COMPLETO), []);
  assert.deepEqual(conferirConfiguracao({}), [
    'SUPABASE_ANON_KEY_DEV',
    'SUPABASE_ANON_KEY_PROD',
    'RESEND_API_KEY',
    'ALERTA_PARA',
  ]);
  // Sem alertar, a chave do Resend não é exigida: é o modo do `wrangler dev`.
  assert.deepEqual(conferirConfiguracao({ ...AMBIENTE_COMPLETO, RESEND_API_KEY: '' }, { alertar: false }), []);
  // Mas no modo do cron ela é — e é conferida ANTES de haver falha, senão a
  // ausência só apareceria no dia em que o alerta precisasse sair.
  assert.deepEqual(conferirConfiguracao({ ...AMBIENTE_COMPLETO, RESEND_API_KEY: '' }), ['RESEND_API_KEY']);
});

test('sonda: 200 com lista JSON passa, numa tentativa só', async () => {
  const buscar = buscarFalso([resposta(200, '[]')]);
  const r = await sondar(AMBIENTES[0], AMBIENTE_COMPLETO, { buscar, ...semEspera });

  assert.equal(r.ok, true);
  assert.equal(r.tentativas.length, 1);
  assert.equal(r.alvo, AMBIENTES[0].url + CAMINHO_SONDA);
  assert.equal(buscar.chamadas[0].opcoes.headers.apikey, 'chave-dev');
  assert.equal(buscar.chamadas[0].opcoes.headers.Authorization, 'Bearer chave-dev');
});

test('sonda: 200 que não é lista REPROVA', async () => {
  // O caso que justifica a asserção positiva: uma página de erro ou um objeto de
  // erro devolvido com 200 é resposta plausível de intermediário (proxy, WAF,
  // página de manutenção) e não prova banco nenhum de pé.
  for (const corpo of ['<html>manutenção</html>', '{"message":"algo"}', '']) {
    const r = await sondar(AMBIENTES[1], AMBIENTE_COMPLETO, {
      buscar: buscarFalso([resposta(200, corpo)]),
      ...semEspera,
    });
    assert.equal(r.ok, false, `corpo ${JSON.stringify(corpo)} deveria reprovar`);
    assert.equal(r.tentativas.length, 3, 'reprovado tem de tentar as três vezes');
  }
});

test('sonda: 401 reprova e registra o corpo, para o e-mail dizer o que veio', async () => {
  const r = await sondar(AMBIENTES[0], AMBIENTE_COMPLETO, {
    buscar: buscarFalso([resposta(401, '{"message":"Invalid API key"}')]),
    ...semEspera,
  });
  assert.equal(r.ok, false);
  assert.equal(r.tentativas.length, 3);
  assert.equal(r.tentativas[0].status, 401);
  assert.match(r.tentativas[0].corpo, /Invalid API key/);
});

test('sonda: falha de rede intermitente não vira alerta', async () => {
  const buscar = buscarFalso([new Error('connection reset'), resposta(200, '[]')]);
  const r = await sondar(AMBIENTES[0], AMBIENTE_COMPLETO, { buscar, ...semEspera });

  assert.equal(r.ok, true);
  assert.equal(r.tentativas.length, 2);
  assert.equal(r.tentativas[0].ok, false);
  assert.match(r.tentativas[0].motivo, /connection reset/);
});

test('alerta: assunto nomeia o ambiente e o texto carrega o que a sonda viu', () => {
  const falha = {
    rotulo: 'produção',
    alvo: 'https://exemplo.supabase.co' + CAMINHO_SONDA,
    tentativas: [{ ok: false, status: 401, corpo: '{"message":"Invalid API key"}', ms: 12 }],
  };
  const { assunto, texto } = montarAlerta([falha], new Date('2026-09-02T09:00:00Z'));

  assert.match(assunto, /produção/);
  assert.match(texto, /HTTP 401/);
  assert.match(texto, /Invalid API key/);
  assert.match(texto, /Restore project/);
  // 09:00 UTC = 06:00 em São Paulo. Data no e-mail em UTC mandaria alguém
  // procurar log na hora errada.
  assert.match(texto, /06:00:00/);
});

test('execução verde: nenhuma chamada ao Resend', async () => {
  const buscar = buscarFalso([resposta(200, '[]')]);
  const r = await executar(AMBIENTE_COMPLETO, { buscar: comRotina(buscar), ...semEspera, ...backupBom });

  assert.equal(r.falhas.length, 0);
  assert.equal(r.backup.ok, true);
  assert.deepEqual(r.rotinas.map((x) => x.ok), [true, true], 'a rotina dos dois ambientes rodou');
  assert.equal(r.algoRuim, false);
  assert.equal(r.alertaEnviado, false);
  assert.equal(r.resultados.length, AMBIENTES.length);
  assert.equal(buscar.chamadas.some((c) => c.url.includes('resend')), false);
});

test('execução com falha: um e-mail, com destinatário e assunto certos', async () => {
  const buscar = async (url) => {
    if (url.includes('resend')) return resposta(200, '{"id":"abc"}');
    if (url.includes(AMBIENTES[1].url)) return resposta(503, 'unavailable');
    return resposta(200, '[]');
  };
  const chamadas = [];
  const espiao = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    return buscar(url, opcoes);
  };

  const r = await executar(AMBIENTE_COMPLETO, { buscar: comRotina(espiao), ...semEspera, ...backupBom });

  assert.equal(r.falhas.length, 1);
  assert.equal(r.falhas[0].ambiente, 'producao');
  // Com o banco de produção fora do ar, a rotina de lá nem é perguntada.
  assert.deepEqual(r.rotinas.map((x) => x.ambiente), ['homologacao']);
  assert.equal(r.alertaEnviado, true);

  const email = chamadas.filter((c) => c.url.includes('resend'));
  assert.equal(email.length, 1, 'um e-mail por execução, não um por tentativa');
  const corpo = JSON.parse(email[0].opcoes.body);
  assert.deepEqual(corpo.to, ['alguem@exemplo.test']);
  assert.match(corpo.subject, /produção/);
  assert.match(corpo.from, /nao-responda@gestaoim360\.com/);
});

test('alerta recusado pelo Resend derruba a execução, dizendo as duas coisas', async () => {
  const buscar = async (url) => {
    if (url.includes('resend')) return resposta(422, '{"message":"domain not verified"}');
    return resposta(500, 'boom');
  };

  await assert.rejects(
    () => executar(AMBIENTE_COMPLETO, { buscar, ...semEspera, ...backupBom }),
    (erro) => {
      assert.match(erro.message, /FALHOU/);
      assert.match(erro.message, /ALERTA NÃO SAIU/);
      assert.match(erro.message, /domain not verified/);
      return true;
    },
  );
});

test('sem configuração, a execução falha alto na primeira vez', async () => {
  await assert.rejects(
    () => executar({ SUPABASE_ANON_KEY_DEV: 'x' }, { buscar: buscarFalso([resposta(200, '[]')]), ...semEspera }),
    /SUPABASE_ANON_KEY_PROD/,
  );
});

test('scheduled fica vermelho quando alguma sonda reprova', async () => {
  const buscar = async (url) => (url.includes('resend') ? resposta(200, '{}') : resposta(540, 'paused'));
  const env = AMBIENTE_COMPLETO;

  // O handler real não recebe opções — troca-se o fetch global, que é o que o
  // workerd também expõe.
  const original = globalThis.fetch;
  globalThis.fetch = buscar;
  try {
    await assert.rejects(() => padrao.scheduled({}, env), /FALHOU/);
  } finally {
    globalThis.fetch = original;
  }
});

// ---------------------------------------------------------------------------
// Vigilância do backup semanal — card 3.12
//
// O que estes testes protegem é o modo de falha que o card 3.11 registrou sobre
// o PRÓPRIO backup: o GitHub desativa workflow agendado em repositório com 60
// dias sem commit, e o backup para de sair sem uma linha de aviso. O risco vira
// real justamente quando o desenvolvimento parar — quando ninguém mais abre o
// painel de Actions.
// ---------------------------------------------------------------------------

test('backup: cópia recente e completa passa', () => {
  const r = avaliarBackup(copia('2026-08-31'), { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-08-31');
  assert.equal(r.idadeDias, 2);
});

test('backup: bucket vazio REPROVA', () => {
  // Não é caso de laboratório: é o estado do bucket enquanto o backup nunca
  // tiver rodado com sucesso, e o desfecho silencioso seria acreditar que sim.
  const r = avaliarBackup([], { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /nenhuma cópia/);
});

test('backup: cópia velha REPROVA, nomeando a data e o limite', () => {
  const r = avaliarBackup(copia('2026-08-01'), { quando: AGORA });
  assert.equal(r.ok, false);
  assert.equal(r.idadeDias, 32);
  assert.match(r.motivo, /2026-08-01/);
  assert.match(r.motivo, /limite: 9/);
});

test('backup: 9 dias passa, 10 reprova — o limite é o limite', () => {
  assert.equal(avaliarBackup(copia('2026-08-24'), { quando: AGORA }).ok, true, '9 dias');
  assert.equal(avaliarBackup(copia('2026-08-23'), { quando: AGORA }).ok, false, '10 dias');
});

test('backup: cópia INCOMPLETA reprova, ainda que seja de hoje', () => {
  // A asserção é positiva pela mesma razão que a sonda não aceita qualquer 200:
  // prefixo que existe passaria com a pasta vazia, e `data.sql.gz` é a razão de
  // o backup existir — dump de schema sem dado é o jeito mais comum de um
  // backup ser inútil (card 3.11).
  const semDado = ['producao/2026-09-02/schema.sql.gz', 'producao/2026-09-02/MANIFESTO.txt'];
  const r = avaliarBackup(semDado, { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /incompleta/);
  assert.match(r.motivo, /data\.sql\.gz/);
});

test('backup: a cópia MAIS NOVA é que manda, mesmo com velhas no bucket', () => {
  const chaves = [...copia('2026-06-01'), ...copia('2026-07-01'), ...copia('2026-08-31')];
  const r = avaliarBackup(chaves, { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-08-31');
});

test('backup: chave fora do padrão é ignorada, não confundida com cópia', () => {
  const r = avaliarBackup(['producao/', 'lixo.txt', 'producao/rascunho/x', ...copia('2026-08-31')], {
    quando: AGORA,
  });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-08-31');
});

test('backup: sem o binding R2, REPROVA — e não lança', async () => {
  // Fail-closed sem cegar o resto: "não consegui conferir" é falha, mas uma
  // exceção aqui derrubaria a execução antes das sondas do Supabase e trocaria
  // uma proteção que funciona por outra que acabou de nascer.
  const r = await conferirBackup({}, { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /binding R2/);
});

test('backup: R2 fora do ar REPROVA com o motivo, sem lançar', async () => {
  const r = await conferirBackup(
    { BACKUP: baldeFalso([], { quebrar: new Error('R2 indisponível') }) },
    { quando: AGORA },
  );
  assert.equal(r.ok, false);
  assert.match(r.motivo, /R2 indisponível/);
});

test('backup: a listagem pagina — 12 cópias não cabem numa página de 3', async () => {
  // `list` do R2 devolve no máximo 1000 por página e sinaliza `truncated`.
  // Parar na primeira página faria a cópia mais nova sumir da conta e o alerta
  // disparar sozinho toda semana, que é como se aprende a ignorá-lo.
  const datas = ['2026-06-14', '2026-06-21', '2026-08-31'];
  const chaves = datas.flatMap(copia);
  const r = await conferirBackup({ BACKUP: baldeFalso(chaves, { porPagina: 3 }) }, { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-08-31');
});

test('backup ruim com Supabase de pé: alerta próprio, e a execução fica vermelha', async () => {
  const chamadas = [];
  const buscar = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    return url.includes('resend') ? resposta(200, '{"id":"abc"}') : resposta(200, '[]');
  };

  const r = await executar(AMBIENTE_COMPLETO, {
    buscar: comRotina(buscar),
    ...semEspera,
    balde: baldeFalso(copia('2026-01-01')),
    quando: AGORA,
  });

  assert.equal(r.falhas.length, 0, 'as sondas passaram');
  assert.equal(r.backup.ok, false);
  assert.equal(r.algoRuim, true, 'backup velho tem de deixar a execução vermelha');
  assert.equal(r.alertaEnviado, true);

  const email = chamadas.filter((c) => c.url.includes('resend'));
  assert.equal(email.length, 1, 'um e-mail por execução');
  const corpo = JSON.parse(email[0].opcoes.body);
  assert.match(corpo.subject, /backup de produção não está saindo/);
  assert.match(corpo.text, /Enable workflow/, 'o e-mail tem de dizer a causa mais provável');
});

test('alerta com os dois problemas cabe num envelope só', () => {
  const falha = {
    rotulo: 'produção',
    alvo: 'https://exemplo.supabase.co' + CAMINHO_SONDA,
    tentativas: [{ ok: false, status: 540, corpo: 'paused', ms: 9 }],
  };
  const { assunto, texto } = montarAlerta([falha], AGORA, {
    ok: false,
    motivo: 'a cópia mais nova é de 2026-01-01, 244 dias atrás (limite: 9)',
  });

  assert.match(assunto, /produção/);
  assert.match(assunto, /backup está atrasado/);
  assert.match(texto, /HTTP 540/);
  assert.match(texto, /244 dias atrás/);
});

test('o limite do backup cobre a semana perdida, não a atrasada', () => {
  // 7 dias é a operação normal (semanal). O limite tem de dar folga para uma
  // execução atrasada sem alarme falso E denunciar a PRIMEIRA semana perdida,
  // em vez de esperar a segunda.
  assert.ok(BACKUP.idadeMaximaDias > 7, 'abaixo disso, alarme falso toda semana');
  assert.ok(BACKUP.idadeMaximaDias < 14, 'acima disso, uma semana perdida passa batida');
});

// ---------------------------------------------------------------------------
// Vigilância da rotina diária — card 9.2,66
//
// O modo de falha: o job `gi_rotina_diaria` some (ou a extensão desliga, ou
// uma migração substitui `rt_diaria` errado) e a central de pendências e a
// projeção param no último dia bom, SEM ERRO NENHUM. A sonda do banco continua
// verde, porque o banco continua acordado. O que se protege aqui é a asserção
// POSITIVA: passa uma data válida e recente, e nada mais.
// ---------------------------------------------------------------------------

test('rotina: a execução de hoje passa, com a idade em horas', () => {
  const r = avaliarRotina(ROTINA_DE_HOJE, { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.idadeHoras, 2);
});

test('rotina: 36 h passa, 37 reprova — o limite é o limite', () => {
  const ha = (horas) => JSON.stringify(new Date(AGORA.getTime() - horas * 3600000).toISOString());
  assert.equal(avaliarRotina(ha(36), { quando: AGORA }).ok, true);
  const r = avaliarRotina(ha(37), { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /37 h atrás \(limite: 36 h\)/);
});

test('rotina: o limite cobre o dia perdido, não o atrasado', () => {
  // Em dia normal o carimbo tem ~3 h na hora do vigia; com UM dia perdido,
  // ~27 h; com DOIS, ~51 h. O limite tem de deixar passar o atraso de horas e
  // pegar o primeiro vigia depois de um dia inteiro sem rotina.
  assert.ok(ROTINA.idadeMaximaHoras > 27, 'abaixo disso, um cron atrasado vira alarme');
  assert.ok(ROTINA.idadeMaximaHoras < 51, 'acima disso, dois dias perdidos passam batidos');
});

test('rotina: null REPROVA — alguma unidade ativa nunca rodou até o fim', () => {
  const r = avaliarRotina('null', { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /nunca rodou/);
});

test('rotina: o que não é data reprova — lista, número, texto torto', () => {
  for (const corpo of ['[]', '42', '"ontem"', '{"executada_em":"2026-09-02"}', '<html>']) {
    const r = avaliarRotina(corpo, { quando: AGORA });
    assert.equal(r.ok, false, `passou com ${corpo}`);
  }
});

test('rotina: data no futuro reprova — relógio torto não é rotina em dia', () => {
  const r = avaliarRotina(JSON.stringify('2026-09-03T09:00:00Z'), { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /futuro/);
});

test('rotina: pergunta por POST ao rpc, com a chave publicável do ambiente', async () => {
  const buscar = buscarFalso([resposta(200, ROTINA_DE_HOJE)]);
  const r = await conferirRotina(AMBIENTES[1], AMBIENTE_COMPLETO, { buscar, ...semEspera, quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(buscar.chamadas.length, 1);
  assert.equal(buscar.chamadas[0].url, AMBIENTES[1].url + ROTINA.caminho);
  assert.equal(buscar.chamadas[0].opcoes.method, 'POST');
  assert.equal(buscar.chamadas[0].opcoes.headers.apikey, 'chave-prod');
});

test('rotina: 404 (a função não existe) repete e reprova dizendo o HTTP — e não lança', async () => {
  const buscar = buscarFalso([resposta(404, '{"code":"PGRST202"}')]);
  const r = await conferirRotina(AMBIENTES[0], AMBIENTE_COMPLETO, { buscar, ...semEspera, quando: AGORA });
  assert.equal(r.ok, false);
  assert.equal(buscar.chamadas.length, 3);
  assert.match(r.motivo, /HTTP 404/);
});

test('rotina: data velha NÃO repete — repetir não rejuvenesce a resposta', async () => {
  const buscar = buscarFalso([resposta(200, JSON.stringify('2026-08-30T06:10:00Z'))]);
  const r = await conferirRotina(AMBIENTES[0], AMBIENTE_COMPLETO, { buscar, ...semEspera, quando: AGORA });
  assert.equal(r.ok, false);
  assert.equal(buscar.chamadas.length, 1);
});

test('rotina parada com Supabase de pé: e-mail próprio, com o SQL de conferir, e a execução fica vermelha', async () => {
  const chamadas = [];
  const base = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    return url.includes('resend') ? resposta(200, '{"id":"abc"}') : resposta(200, '[]');
  };
  // Produção parou há três dias; homologação rodou hoje.
  const buscar = async (url, opcoes) => {
    if (url.includes('/rpc/')) {
      return url.startsWith(AMBIENTES[1].url)
        ? resposta(200, JSON.stringify('2026-08-30T06:10:00Z'))
        : resposta(200, ROTINA_DE_HOJE);
    }
    return base(url, opcoes);
  };

  const r = await executar(AMBIENTE_COMPLETO, { buscar, ...semEspera, ...backupBom });

  assert.equal(r.falhas.length, 0, 'as sondas passaram');
  assert.equal(r.backup.ok, true);
  assert.deepEqual(r.rotinas.map((x) => `${x.ambiente}=${x.ok}`), ['homologacao=true', 'producao=false']);
  assert.equal(r.algoRuim, true, 'rotina parada tem de deixar a execução vermelha');
  assert.equal(r.alertaEnviado, true);

  const email = chamadas.filter((c) => c.url.includes('resend'));
  assert.equal(email.length, 1, 'um e-mail por execução');
  const corpo = JSON.parse(email[0].opcoes.body);
  assert.match(corpo.subject, /rotina diária de produção não está rodando/);
  assert.match(corpo.text, /cron\.job/, 'o e-mail tem de dizer onde olhar');
  assert.match(corpo.text, /ROTINA_FALHOU/);
  assert.doesNotMatch(corpo.subject, /homologação/);
});

test('alerta com Supabase fora E rotina parada cabe num envelope só', () => {
  const falha = {
    rotulo: 'homologação',
    alvo: 'https://exemplo.supabase.co' + CAMINHO_SONDA,
    tentativas: [{ ok: false, status: 540, corpo: 'paused', ms: 9 }],
  };
  const rotina = { ok: false, rotulo: 'produção', alvo: 'https://x' + ROTINA.caminho, motivo: 'nenhuma execução completa' };
  const { assunto, texto } = montarAlerta([falha], AGORA, { ok: true }, [rotina]);
  assert.match(assunto, /homologação não respondeu — e a rotina diária parou em produção/);
  assert.match(texto, /rotina diária de produção/);
});

test('resumo do log diz a idade da rotina de cada ambiente', () => {
  const r = resumir(
    [{ rotulo: 'produção', ok: true, tentativas: [{ ok: true, status: 200, linhas: 0, ms: 5 }] }],
    null,
    [{ rotulo: 'produção', ok: true, idadeHoras: 2 }],
  );
  assert.match(r, /rotina de produção: ok \(2 h\)/);
});

// ---------------------------------------------------------------------------
// Batimento externo — card 9.6,5 ("quem vigia o vigia")
//
// O modo de falha que estes testes protegem é o SILENCIOSO: vigia morto e vigia
// satisfeito produzem a mesma caixa de entrada vazia. O batimento é o sinal
// positivo de vida, e o serviço externo avisa quando ele some.
// ---------------------------------------------------------------------------

const URL_BATIMENTO = 'https://hc-ping.com/00000000-0000-4000-8000-000000000000';
const COM_BATIMENTO = { ...AMBIENTE_COMPLETO, [BATIMENTO.variavel]: URL_BATIMENTO };

/** Quantos GETs foram para a URL do batimento. */
const pings = (chamadas) => chamadas.filter((c) => c.url === URL_BATIMENTO);

/** fetch de mentira que responde ao batimento com `status` e ao resto com `outro`. */
function comBatimento(outro, status = 200) {
  const chamadas = [];
  const buscar = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    if (url === URL_BATIMENTO) {
      if (status instanceof Error) throw status;
      return resposta(status, 'OK');
    }
    return outro(url, opcoes);
  };
  buscar.chamadas = chamadas;
  return buscar;
}

test('batimento: sem a URL, não chama nada e diz por quê — e não lança', async () => {
  const buscar = buscarFalso([resposta(200, 'OK')]);
  const b = await baterPonto(AMBIENTE_COMPLETO, { buscar, ...semEspera });
  assert.equal(b.enviado, false);
  assert.match(b.motivo, /VIGIA_BATIMENTO_URL/);
  assert.equal(buscar.chamadas.length, 0);
});

test('batimento: com a URL, um GET nela', async () => {
  const buscar = buscarFalso([resposta(200, 'OK')]);
  const b = await baterPonto(COM_BATIMENTO, { buscar, ...semEspera });
  assert.equal(b.enviado, true);
  assert.equal(buscar.chamadas.length, 1);
  assert.equal(buscar.chamadas[0].url, URL_BATIMENTO);
  assert.equal(buscar.chamadas[0].opcoes.method, 'GET');
});

test('batimento: URL que não é https é recusada sem sair da máquina', async () => {
  const buscar = buscarFalso([resposta(200, 'OK')]);
  const b = await baterPonto(
    { [BATIMENTO.variavel]: 'http://hc-ping.com/x' },
    { buscar, ...semEspera },
  );
  assert.equal(b.enviado, false);
  assert.match(b.motivo, /https/);
  assert.equal(buscar.chamadas.length, 0);
});

test('batimento: serviço fora repete, não lança, e o motivo NÃO carrega a URL', async () => {
  const buscar = buscarFalso([new Error(`fetch failed for ${URL_BATIMENTO}`)]);
  const b = await baterPonto(COM_BATIMENTO, { buscar, ...semEspera });
  assert.equal(b.enviado, false);
  assert.equal(buscar.chamadas.length, 3, 'três tentativas, como a sonda');
  assert.equal(b.motivo.includes(URL_BATIMENTO), false, 'a URL é segredo: quem a tem bate o ponto no lugar do vigia');
  assert.match(b.motivo, /<VIGIA_BATIMENTO_URL>/);

  const http = await baterPonto(COM_BATIMENTO, { buscar: buscarFalso([resposta(500, 'x')]), ...semEspera });
  assert.match(http.motivo, /HTTP 500/);
});

test('execução verde bate o ponto uma vez, DEPOIS de sondar tudo', async () => {
  const buscar = comBatimento(async () => resposta(200, '[]'));
  const r = await executar(COM_BATIMENTO, { buscar: comRotina(buscar), ...semEspera, ...backupBom });

  assert.equal(r.algoRuim, false);
  assert.equal(r.batimento.enviado, true);
  assert.equal(pings(buscar.chamadas).length, 1);
  assert.equal(buscar.chamadas.at(-1).url, URL_BATIMENTO, 'o batimento é a última coisa da execução');
});

test('execução verde SEM a URL continua verde — o secret é opcional', async () => {
  const buscar = buscarFalso([resposta(200, '[]')]);
  const r = await executar(AMBIENTE_COMPLETO, { buscar: comRotina(buscar), ...semEspera, ...backupBom });
  assert.equal(r.algoRuim, false);
  assert.equal(r.batimento.enviado, false);
  assert.match(descreverBatimento(r.batimento), /NÃO enviado.*VIGIA_BATIMENTO_URL/);
});

test('batimento recusado não deixa a execução vermelha nem manda e-mail', async () => {
  const buscar = comBatimento(async () => resposta(200, '[]'), 500);
  const r = await executar(COM_BATIMENTO, { buscar: comRotina(buscar), ...semEspera, ...backupBom });
  assert.equal(r.algoRuim, false);
  assert.equal(r.batimento.enviado, false);
  assert.equal(buscar.chamadas.some((c) => c.url.includes('resend')), false);
});

test('algo ruim com o alerta ENTREGUE ainda bate o ponto — o vigia está vivo e falou', async () => {
  const buscar = comBatimento(async (url) => {
    if (url.includes('resend')) return resposta(200, '{"id":"abc"}');
    if (url.includes(AMBIENTES[1].url)) return resposta(503, 'unavailable');
    return resposta(200, '[]');
  });
  const r = await executar(COM_BATIMENTO, { buscar: comRotina(buscar), ...semEspera, ...backupBom });
  assert.equal(r.algoRuim, true);
  assert.equal(r.alertaEnviado, true);
  assert.equal(r.batimento.enviado, true);
});

test('alerta que NÃO sai também não bate o ponto — é o serviço externo que avisa', async () => {
  const buscar = comBatimento(async (url) =>
    url.includes('resend') ? resposta(422, '{"message":"domain not verified"}') : resposta(500, 'boom'),
  );
  await assert.rejects(() => executar(COM_BATIMENTO, { buscar, ...semEspera, ...backupBom }), /ALERTA NÃO SAIU/);
  assert.equal(pings(buscar.chamadas).length, 0);
});

test('a conferência à mão (fetch, sem alertar) nunca bate o ponto', async () => {
  const buscar = comBatimento(async () => resposta(200, '[]'));
  const r = await executar(COM_BATIMENTO, {
    alertar: false,
    buscar: comRotina(buscar),
    ...semEspera,
    ...backupBom,
  });
  assert.equal(r.batimento, null);
  assert.equal(pings(buscar.chamadas).length, 0);
  assert.equal(descreverBatimento(r.batimento), 'batimento: não se aplica');
});
