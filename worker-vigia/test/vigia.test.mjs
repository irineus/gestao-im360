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
  CAMINHO_SONDA,
  conferirConfiguracao,
  executar,
  montarAlerta,
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
  const r = await executar(AMBIENTE_COMPLETO, { buscar, ...semEspera });

  assert.equal(r.falhas.length, 0);
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

  const r = await executar(AMBIENTE_COMPLETO, { buscar: espiao, ...semEspera });

  assert.equal(r.falhas.length, 1);
  assert.equal(r.falhas[0].ambiente, 'producao');
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
    () => executar(AMBIENTE_COMPLETO, { buscar, ...semEspera }),
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
