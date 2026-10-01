// Suíte do aplicador de templates e campos do Auth — card 9.2,81.
// Roda com `node --test`, sem token e sem rede: o que se exercita aqui é a
// decisão (o que conta como divergência, o que vai no PATCH, que nome a spec
// aceita) e a amarração com o config.toml. Rodar contra os projetos é de
// Irineu, com o personal access token (docs/emails-auth.md §4).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  AJUSTES,
  LETRAS_E_DIGITOS,
  MODELOS,
  camposUsados,
  carregar,
  conferir,
  conferirNomes,
  montarPatch,
  principal,
} from '../aplicar-templates.mjs';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const configToml = readFileSync(join(RAIZ, 'supabase', 'config.toml'), 'utf8').replace(/\r\n/g, '\n');

const modelos = carregar();

/** O painel ideal: exatamente o que o PATCH grava. */
const painelEmDia = () => ({ outro_campo_qualquer: 'intocado', ...montarPatch(modelos) });

/** Spec mínima no formato da Management API, com os campos dados. */
function specCom({ patch = camposUsados(), get = camposUsados(), enumCaracteres } = {}) {
  const props = (campos) =>
    Object.fromEntries(
      campos.map((c) => [
        c,
        c === 'password_required_characters' ? { type: 'string', enum: enumCaracteres ?? [LETRAS_E_DIGITOS, ''] } : { type: 'string' },
      ]),
    );
  return {
    paths: {
      '/v1/projects/{ref}/config/auth': {
        get: { responses: { 200: { content: { 'application/json': { schema: { $ref: '#/components/schemas/Saida' } } } } } },
        patch: { requestBody: { content: { 'application/json': { schema: { $ref: '#/components/schemas/Corpo' } } } } },
      },
    },
    components: { schemas: { Corpo: { properties: props(patch) }, Saida: { properties: props(get) } } },
  };
}

/** Valor de `chave = valor` dentro da seção `[secao]` do config.toml. */
function lerToml(secao, chave) {
  const inicio = configToml.indexOf(`\n[${secao}]\n`);
  assert.notEqual(inicio, -1, `seção [${secao}] não existe no config.toml`);
  const resto = configToml.slice(inicio + secao.length + 4);
  const corpo = resto.slice(0, resto.search(/\n\[/) === -1 ? undefined : resto.search(/\n\[/));
  const linha = corpo.split('\n').find((l) => l.startsWith(`${chave} =`));
  assert.ok(linha, `[${secao}] ${chave} não existe no config.toml`);
  return JSON.parse(linha.slice(linha.indexOf('=') + 1).trim());
}

test('painel igual ao repositório: nenhuma divergência', () => {
  assert.deepEqual(conferir(painelEmDia(), modelos), []);
});

test('o estado medido ANTES de 01/10/2026 reprova nos quatro campos do provedor', () => {
  // dev e prod, medidos por Irineu no painel (Notas do card 9.2,81).
  const antes = {
    ...painelEmDia(),
    mailer_otp_exp: 3600,
    password_min_length: 6,
    password_required_characters: '',
    security_update_password_require_reauthentication: false,
  };
  const div = conferir(antes, modelos);
  assert.equal(div.length, 4);
  for (const campo of ['mailer_otp_exp', 'password_min_length', 'password_required_characters', 'security_update_password_require_reauthentication']) {
    assert.ok(div.some((d) => d.includes(campo)), `faltou acusar ${campo}`);
  }
});

test('cada ajuste errado sozinho gera UMA divergência, com o nome do campo', () => {
  for (const a of AJUSTES) {
    const painel = { ...painelEmDia(), [a.campo]: typeof a.valor === 'boolean' ? !a.valor : 1 };
    const div = conferir(painel, modelos);
    assert.equal(div.length, 1, a.campo);
    assert.match(div[0], new RegExp(a.campo));
  }
});

test('campo AUSENTE da resposta reprova — é assim que um nome trocado aparece na leitura de volta', () => {
  for (const campo of camposUsados()) {
    const painel = painelEmDia();
    delete painel[campo];
    assert.ok(conferir(painel, modelos).length >= 1, campo);
  }
});

test('igualdade estrita: "86400" em texto não é 86400', () => {
  const div = conferir({ ...painelEmDia(), mailer_otp_exp: '86400' }, modelos);
  assert.equal(div.length, 1);
});

test('notificação desligada reprova mesmo com assunto e corpo certos', () => {
  const div = conferir({ ...painelEmDia(), mailer_notifications_password_changed_enabled: false }, modelos);
  assert.equal(div.length, 1);
  assert.match(div[0], /password_changed_enabled/);
});

test('corpo colado à mão no painel (bytes diferentes) reprova; CRLF × LF não', () => {
  const senha = MODELOS.find((m) => m.arquivo === 'senha-alterada.html');
  const colado = { ...painelEmDia(), [senha.campoCorpo]: '<p>Your password has been changed</p>' };
  assert.equal(conferir(colado, modelos).length, 1);

  const comCrlf = { ...painelEmDia(), [senha.campoCorpo]: modelos.find((m) => m.arquivo === senha.arquivo).corpo.replace(/\n/g, '\r\n') };
  assert.deepEqual(conferir(comCrlf, modelos), []);
});

test('o PATCH leva exatamente os campos usados, e nenhum outro', () => {
  const chaves = Object.keys(montarPatch(modelos)).sort();
  assert.deepEqual(chaves, [...camposUsados()].sort());
  // Nada de SMTP, Site URL ou Redirect URLs: é o que um `config push` apagaria.
  assert.ok(!chaves.some((c) => /smtp|site_url|uri_allow_list/.test(c)));
});

test('conferirNomes: spec com todos os campos aprova', () => {
  assert.deepEqual(conferirNomes(specCom()), []);
});

test('conferirNomes: campo fora do PATCH ou fora do GET reprova', () => {
  const semNoPatch = specCom({ patch: camposUsados().filter((c) => c !== 'mailer_otp_exp') });
  assert.deepEqual(conferirNomes(semNoPatch), ['mailer_otp_exp: não existe no corpo do PATCH']);

  const semNoGet = specCom({ get: camposUsados().filter((c) => c !== 'security_update_password_require_reauthentication') });
  assert.deepEqual(conferirNomes(semNoGet), ['security_update_password_require_reauthentication: não existe na resposta do GET']);
});

test('conferirNomes: valor fora do enum reprova', () => {
  const spec = specCom({ enumCaracteres: ['abcdefghijklmnopqrstuvwxyz:0123456789', ''] });
  const problemas = conferirNomes(spec);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /password_required_characters/);
});

test('conferirNomes: endpoint sumido reprova com uma linha só', () => {
  assert.equal(conferirNomes({ paths: {}, components: { schemas: {} } }).length, 1);
});

test('senha-alterada.html usa só {{ .Email }} e {{ .SiteURL }} — as variáveis que a notificação oferece', () => {
  const corpo = modelos.find((m) => m.arquivo === 'senha-alterada.html').corpo;
  const usadas = new Set([...corpo.matchAll(/\{\{\s*([^}]+?)\s*\}\}/g)].map((m) => m[1]));
  assert.deepEqual([...usadas].sort(), ['.Email', '.SiteURL']);
});

test('o script e o config.toml dizem a mesma coisa (o defeito do card 9.2,81 era a divergência)', () => {
  const valor = (campo) => AJUSTES.find((a) => a.campo === campo).valor;
  assert.equal(lerToml('auth.email', 'otp_expiry'), valor('mailer_otp_exp'));
  assert.equal(lerToml('auth', 'minimum_password_length'), valor('password_min_length'));
  assert.equal(lerToml('auth', 'password_requirements'), 'letters_digits');
  assert.equal(valor('password_required_characters'), LETRAS_E_DIGITOS);
  assert.equal(lerToml('auth.email', 'secure_password_change'), valor('security_update_password_require_reauthentication'));
  assert.equal(lerToml('auth.email.notification.password_changed', 'enabled'), valor('mailer_notifications_password_changed_enabled'));

  const secoes = {
    'convite.html': 'auth.email.template.invite',
    'recuperacao-senha.html': 'auth.email.template.recovery',
    'senha-alterada.html': 'auth.email.notification.password_changed',
  };
  for (const m of MODELOS) {
    assert.equal(lerToml(secoes[m.arquivo], 'subject'), m.assunto, m.arquivo);
    assert.equal(lerToml(secoes[m.arquivo], 'content_path'), `./supabase/templates/${m.arquivo}`, m.arquivo);
  }
});

test('"24 horas" nos e-mails de link ↔ otp_expiry de 86400 (docs/emails-auth.md §7, item 3)', () => {
  // Até 01/10/2026 a recuperação dizia 24 h e o hospedado aplicava 1 h. Se o
  // número mudar, esta asserção obriga a mudar a frase junto.
  assert.equal(AJUSTES.find((a) => a.campo === 'mailer_otp_exp').valor, 86400);
  for (const arquivo of ['convite.html', 'recuperacao-senha.html']) {
    assert.match(modelos.find((m) => m.arquivo === arquivo).corpo, /24 horas/, arquivo);
  }
});

// ---------------------------------------------------------------------------
// O fluxo inteiro, com um `fetch` falso no lugar da Management API. É o único
// jeito de exercitar sem token o caso que justifica o script existir: o PATCH
// que devolve 200 e não muda nada.
// ---------------------------------------------------------------------------

/** Projeto falso: `aplica` diz se o PATCH grava de fato. */
function apiFalsa({ inicial, aplica = true, ignora = [] }) {
  let estado = { ...inicial };
  const chamadas = [];
  const fetchFalso = async (url, opcoes = {}) => {
    const metodo = opcoes.method ?? 'GET';
    chamadas.push(`${metodo} ${url}`);
    if (url.endsWith('/api/v1-json')) return new Response(JSON.stringify(specCom()), { status: 200 });
    if (metodo === 'PATCH') {
      if (aplica) {
        const corpo = JSON.parse(opcoes.body);
        for (const c of ignora) delete corpo[c];
        estado = { ...estado, ...corpo };
      }
      return new Response('{}', { status: 200 });
    }
    return new Response(JSON.stringify(estado), { status: 200 });
  };
  return { fetchFalso, chamadas, estado: () => estado };
}

async function rodar(argumentos, api) {
  const fetchOriginal = globalThis.fetch;
  const { log, error, warn } = console;
  const saida = [];
  globalThis.fetch = api.fetchFalso;
  console.log = console.error = console.warn = (...a) => saida.push(a.join(' '));
  process.env.SUPABASE_ACCESS_TOKEN = 'sbp_falso_da_suite';
  process.exitCode = undefined;
  try {
    await principal(argumentos);
    return { rc: process.exitCode ?? 0, saida: saida.join('\n') };
  } finally {
    globalThis.fetch = fetchOriginal;
    Object.assign(console, { log, error, warn });
    delete process.env.SUPABASE_ACCESS_TOKEN;
    process.exitCode = undefined;
  }
}

const ANTES_DE_01_10 = {
  mailer_otp_exp: 3600,
  password_min_length: 6,
  password_required_characters: '',
  security_update_password_require_reauthentication: false,
  smtp_host: 'smtp.resend.com',
};

test('fluxo: --conferir no estado de antes reprova e NÃO escreve', async () => {
  const api = apiFalsa({ inicial: ANTES_DE_01_10 });
  const { rc, saida } = await rodar(['--conferir', 'ref'], api);
  assert.equal(rc, 1);
  assert.match(saida, /\(mailer_otp_exp\): painel 3600, esperado 86400/);
  assert.ok(!api.chamadas.some((c) => c.startsWith('PATCH')));
});

test('fluxo: aplicar grava, confere por leitura de volta e não toca no SMTP', async () => {
  const api = apiFalsa({ inicial: ANTES_DE_01_10 });
  const { rc, saida } = await rodar(['ref'], api);
  assert.equal(rc, 0, saida);
  assert.match(saida, /Aplicado e conferido/);
  assert.equal(api.estado().smtp_host, 'smtp.resend.com');
  assert.deepEqual(conferir(api.estado(), modelos), []);
  // E o --conferir seguinte aprova.
  assert.equal((await rodar(['--conferir', 'ref'], api)).rc, 0);
});

test('fluxo: PATCH 200 que não grava nada reprova na leitura de volta', async () => {
  const api = apiFalsa({ inicial: ANTES_DE_01_10, aplica: false });
  const { rc, saida } = await rodar(['ref'], api);
  assert.equal(rc, 1);
  assert.match(saida, /devolveu 200 e a configuração NÃO ficou igual/);
});

test('fluxo: PATCH 200 que ignora UM campo reprova nomeando o campo', async () => {
  const api = apiFalsa({ inicial: ANTES_DE_01_10, ignora: ['security_update_password_require_reauthentication'] });
  const { rc, saida } = await rodar(['ref'], api);
  assert.equal(rc, 1);
  assert.match(saida, /Secure password change \(security_update_password_require_reauthentication\): painel false/);
});
