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
  CAMINHO_SONDA,
  avaliarBackup,
  conferirBackup,
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

/** Data fixa: o vigia roda 09:00 UTC = 06:00 em São Paulo. */
const AGORA = new Date('2026-09-02T09:00:00Z');

/**
 * Uma cópia do Fulcrum carimbada naquele instante (`YYYY-MM-DDTHHMMZ`), com o
 * tamanho medido em 24/09/2026 (0,1 MB) a menos que se diga outro.
 */
const copia = (carimbo, size = 100 * 1024) => [
  { key: `gestaoim360/gestaoim360-${carimbo}.tar.gz.gpg`, size },
];

/** Bucket R2 de mentira, com a paginação que o `list` de verdade tem. */
function baldeFalso(objetos, { porPagina = 1000, quebrar = null } = {}) {
  return {
    async list({ cursor } = {}) {
      if (quebrar) throw quebrar;
      const inicio = cursor ? Number(cursor) : 0;
      const fatia = objetos.slice(inicio, inicio + porPagina);
      const fim = inicio + fatia.length;
      return {
        objects: fatia,
        truncated: fim < objetos.length,
        cursor: String(fim),
      };
    },
  };
}

/** Backup saudável: a cópia desta madrugada (05:17 UTC), com corpo. */
const backupBom = { balde: baldeFalso(copia('2026-09-02T0517Z')), quando: AGORA };

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
  const r = await executar(AMBIENTE_COMPLETO, { buscar, ...semEspera, ...backupBom });

  assert.equal(r.falhas.length, 0);
  assert.equal(r.backup.ok, true);
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

  const r = await executar(AMBIENTE_COMPLETO, { buscar: espiao, ...semEspera, ...backupBom });

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
// Vigilância do backup de produção — card 3.12; desde 24/09/2026 o backup
// vigiado é o diário do Fulcrum (`r2://fulcrum-backups/gestaoim360/`).
//
// O que estes testes protegem é o modo de falha que o card 3.11 registrou sobre
// o PRÓPRIO backup: o GitHub desativa workflow agendado em repositório com 60
// dias sem commit, e o backup para de sair sem uma linha de aviso. O risco vira
// real justamente quando o desenvolvimento parar — quando ninguém mais abre o
// painel de Actions.
// ---------------------------------------------------------------------------

test('backup: cópia desta madrugada, com corpo, passa', () => {
  const r = avaliarBackup(copia('2026-09-02T0517Z'), { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-09-02T05:17Z');
  assert.equal(r.idadeHoras, 3);
});

test('backup: bucket vazio REPROVA', () => {
  // Não é caso de laboratório: é o estado do bucket enquanto o backup nunca
  // tiver rodado com sucesso, e o desfecho silencioso seria acreditar que sim.
  const r = avaliarBackup([], { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /nenhuma cópia/);
});

test('backup: cópia velha REPROVA, nomeando a data e o limite', () => {
  const r = avaliarBackup(copia('2026-08-01T0517Z'), { quando: AGORA });
  assert.equal(r.ok, false);
  assert.equal(r.idadeHoras, 771);
  assert.match(r.motivo, /2026-08-01T05:17Z/);
  assert.match(r.motivo, /limite: 48 h/);
});

test('backup: 48 h passa, 49 reprova — o limite é o limite', () => {
  assert.equal(avaliarBackup(copia('2026-08-31T0900Z'), { quando: AGORA }).ok, true, '48 h');
  assert.equal(avaliarBackup(copia('2026-08-31T0800Z'), { quando: AGORA }).ok, false, '49 h');
});

test('backup: cópia TRUNCADA reprova, ainda que seja de hoje', () => {
  // A asserção é positiva pela mesma razão que a sonda não aceita qualquer 200:
  // a chave existir passaria com um objeto vazio. O vigia não abre a cópia (não
  // tem a senha), então o que ele afirma é que ela tem corpo.
  const r = avaliarBackup(copia('2026-09-02T0517Z', 312), { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /incompleta/);
  assert.match(r.motivo, /312 bytes/);
});

test('backup: objeto sem tamanho reprova, em vez de passar por não saber', () => {
  const r = avaliarBackup([{ key: 'gestaoim360/gestaoim360-2026-09-02T0517Z.tar.gz.gpg' }], { quando: AGORA });
  assert.equal(r.ok, false);
  assert.match(r.motivo, /incompleta/);
});

test('backup: a cópia MAIS NOVA é que manda, mesmo com velhas no bucket', () => {
  // Inclusive fora de ordem na listagem: a decisão é pelo carimbo, não pela posição.
  const objetos = [...copia('2026-08-01T0517Z'), ...copia('2026-09-02T0517Z'), ...copia('2026-09-01T0517Z')];
  const r = avaliarBackup(objetos, { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-09-02T05:17Z');
});

test('backup: chave fora do padrão é ignorada, não confundida com cópia', () => {
  // Arquivo SEM cifra (`.tar.gz`) não é cópia do Fulcrum — e sozinho no bucket,
  // tem de reprovar, não passar.
  const estranhos = [
    { key: 'gestaoim360/', size: 0 },
    { key: 'gestaoim360/manifest.txt', size: 50_000 },
    { key: 'gestaoim360/gestaoim360-2026-09-02T0600Z.tar.gz', size: 50_000 },
    { key: 'gestaoim360/entrelares-2026-09-02T0600Z.tar.gz.gpg', size: 50_000 },
  ];
  const r = avaliarBackup([...estranhos, ...copia('2026-09-02T0517Z')], { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-09-02T05:17Z');
  assert.equal(avaliarBackup(estranhos, { quando: AGORA }).ok, false);
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

test('backup: a listagem pagina — a cópia mais nova pode estar na última página', async () => {
  // `list` do R2 devolve no máximo 1000 por página e sinaliza `truncated`.
  // Parar na primeira página faria a cópia mais nova sumir da conta e o alerta
  // disparar sozinho todo dia, que é como se aprende a ignorá-lo.
  const carimbos = ['2026-08-28T0517Z', '2026-08-29T0517Z', '2026-08-30T0517Z', '2026-09-02T0517Z'];
  const objetos = carimbos.flatMap((c) => copia(c));
  const r = await conferirBackup({ BACKUP: baldeFalso(objetos, { porPagina: 3 }) }, { quando: AGORA });
  assert.equal(r.ok, true);
  assert.equal(r.data, '2026-09-02T05:17Z');
});

test('backup ruim com Supabase de pé: alerta próprio, e a execução fica vermelha', async () => {
  const chamadas = [];
  const buscar = async (url, opcoes) => {
    chamadas.push({ url, opcoes });
    return url.includes('resend') ? resposta(200, '{"id":"abc"}') : resposta(200, '[]');
  };

  const r = await executar(AMBIENTE_COMPLETO, {
    buscar,
    ...semEspera,
    balde: baldeFalso(copia('2026-01-01T0517Z')),
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
  assert.match(corpo.text, /irineus\/fulcrum\/actions\/workflows\/pg_dump_r2\.yml/, 'e onde clicar');
  assert.doesNotMatch(corpo.text, /backup-semanal/, 'o workflow aposentado não é mais causa de nada');
});

test('alerta com os dois problemas cabe num envelope só', () => {
  const falha = {
    rotulo: 'produção',
    alvo: 'https://exemplo.supabase.co' + CAMINHO_SONDA,
    tentativas: [{ ok: false, status: 540, corpo: 'paused', ms: 9 }],
  };
  const { assunto, texto } = montarAlerta([falha], AGORA, {
    ok: false,
    motivo: 'a cópia mais nova é de 2026-01-01T05:17Z, 5859 h atrás (limite: 48 h)',
  });

  assert.match(assunto, /produção/);
  assert.match(assunto, /backup está atrasado/);
  assert.match(texto, /HTTP 540/);
  assert.match(texto, /5859 h atrás/);
});

test('o limite do backup cobre o segundo dia perdido, não o atraso', () => {
  // Dump às 05:17 UTC, vigia às 09:00 UTC: operação normal ≈ 4 h. Um dia
  // perdido e um dump atrasado para depois das 09:00 dão os dois ≈ 28 h e daqui
  // não se distinguem; dois dias perdidos dão ≈ 52 h.
  assert.ok(BACKUP.idadeMaximaHoras > 28, 'abaixo disso, alarme falso quando o agendador atrasa');
  assert.ok(BACKUP.idadeMaximaHoras < 52, 'acima disso, dois dias seguidos sem backup passam batidos');
});
