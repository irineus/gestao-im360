#!/usr/bin/env node
// Aplica no painel de um projeto Supabase remoto, pela Management API, os
// templates de e-mail deste diretório E os campos do Auth que o config.toml
// declara mas que só valem no stack local — cards 4.7,6 e 9.2,81
// (docs/emails-auth.md §4, docs/acesso-autenticacao.md §2).
//
// Uso (PowerShell):
//   $env:SUPABASE_ACCESS_TOKEN = '<personal access token>'
//   node supabase/templates/aplicar-templates.mjs <ref>              # aplica e confere
//   node supabase/templates/aplicar-templates.mjs --conferir <ref>   # só audita
//   node supabase/templates/aplicar-templates.mjs --conferir-nomes   # sem token: confere
//                                                                    # os nomes na spec
//
//   dev  = ncdfolxdupbbfvtydngx      prod = aqfuawrygxsiopyppjza
//
// ⚠️ POR QUE ESTE SCRIPT EXISTE, E NÃO `supabase config push`.
//    O `config push` empurra o config.toml INTEIRO e o que não está no arquivo
//    volta ao default — e `[auth.email.smtp]` está DELIBERADAMENTE fora dele
//    (decisão de 02/09/2026: o SMTP do Resend vive só no painel). Um `config
//    push` apagaria o SMTP dos dois projetos, e o sintoma seria convite e
//    recuperação parando de chegar, em silêncio, dias depois. Este script faz
//    um PATCH dos campos listados abaixo e não toca em mais nada.
//
// ⚠️ POR QUE OS CAMPOS DO PROVEDOR ENTRARAM AQUI (card 9.2,81, 01/10/2026).
//    O config.toml dizia 24 h de link, senha mínima 8 com letras e dígitos e
//    "Secure password change" ligado — e os dois projetos hospedados estavam
//    com 1 h, 6, nenhum requisito e DESLIGADO, desde sempre. O convite do
//    Laurence venceu em 19 h, e a sessão que sobrou trocou a senha do Lindomar
//    (card 9.2,80). A defesa existia no papel e nunca foi aplicada. O mesmo
//    problema que o item 9.16 tinha com os templates: o arquivo vale só na
//    máquina, e nada comparava o painel com ele.
//
// ⚠️ A conferência é POSITIVA, como o vigia do card 3.10 e o backup do 3.11:
//    não basta o PATCH devolver 200. O script lê a configuração de volta e
//    exige que cada campo seja o do repositório. Nome de campo errado na API
//    devolveria 200 sem mudar nada, e "não deu erro" teria passado por sucesso.
//    Por isso, antes do PATCH, os nomes também são conferidos contra a spec
//    OpenAPI pública da Management API — que não pede token.

import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

export const API = 'https://api.supabase.com/v1/projects';
export const SPEC = 'https://api.supabase.com/api/v1-json';
const ENDPOINT = '/v1/projects/{ref}/config/auth';

// Os nomes vêm do endpoint PATCH /v1/projects/{ref}/config/auth, conferidos em
// 01/10/2026 (card 9.2,81) em DUAS fontes: o schema `UpdateAuthConfigBody` da
// spec OpenAPI e o código do CLI que os grava a partir do config.toml
// (`apps/cli-go/pkg/config/auth.go`, inclusive na tag v2.116.0 que o CI fixa).
export const MODELOS = [
  {
    rotulo: 'Convite (Invite user)',
    campoAssunto: 'mailer_subjects_invite',
    campoCorpo: 'mailer_templates_invite_content',
    assunto: 'Seu acesso ao Gestão IM360',
    arquivo: 'convite.html',
  },
  {
    rotulo: 'Recuperação de senha (Reset password)',
    campoAssunto: 'mailer_subjects_recovery',
    campoCorpo: 'mailer_templates_recovery_content',
    assunto: 'Redefinir sua senha do Gestão IM360',
    arquivo: 'recuperacao-senha.html',
  },
  {
    // Card 9.2,81. Não é template de link: é o aviso mandado DEPOIS da troca.
    // Ligado no prod à mão em 01/10/2026, com um texto colado no painel que
    // pode diferir deste em bytes — o primeiro `--conferir` vai apontar isso,
    // e é esperado. Aplicado pelo script, os dois passam a ser iguais.
    rotulo: 'Senha alterada (Password changed)',
    campoAssunto: 'mailer_subjects_password_changed_notification',
    campoCorpo: 'mailer_templates_password_changed_notification_content',
    assunto: 'Sua senha do Gestão IM360 foi alterada',
    arquivo: 'senha-alterada.html',
  },
];

// `letters_digits` do config.toml, na forma que a API guarda. É o primeiro
// valor do enum de `password_required_characters` e o que o CLI escreve para
// `LettersDigits` — os dois-pontos separam os grupos exigidos: "uma letra
// (qualquer caixa)" e "um dígito".
export const LETRAS_E_DIGITOS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ:0123456789';

// Os campos do Auth que o config.toml declara e que o hospedado não herda.
// Cada um com a chave do config.toml ao lado — é por ela que se acha o porquê.
export const AJUSTES = [
  {
    rotulo: 'Email OTP expiration',
    toml: '[auth.email] otp_expiry',
    campo: 'mailer_otp_exp',
    valor: 86400,
    // ⚠️ O painel avisa "recommended less than an hour". Mantido em 24 h de
    //    propósito — decisão de risco aceito de 01/10/2026, card 9.2,81
    //    (docs/acesso-autenticacao.md §2): com 1 h o convite do Laurence venceu.
  },
  {
    rotulo: 'Minimum password length',
    toml: '[auth] minimum_password_length',
    campo: 'password_min_length',
    valor: 8,
  },
  {
    rotulo: 'Password requirements',
    toml: '[auth] password_requirements = "letters_digits"',
    campo: 'password_required_characters',
    valor: LETRAS_E_DIGITOS,
  },
  {
    rotulo: 'Secure password change',
    toml: '[auth.email] secure_password_change',
    campo: 'security_update_password_require_reauthentication',
    valor: true,
  },
  {
    rotulo: 'Notificação "Password changed" ligada',
    toml: '[auth.email.notification.password_changed] enabled',
    campo: 'mailer_notifications_password_changed_enabled',
    valor: true,
  },
];

function sair(mensagem) {
  console.error(`\n✗ ${mensagem}\n`);
  process.exitCode = 1;
}

async function pedir(metodo, ref, token, corpo) {
  const resposta = await fetch(`${API}/${ref}/config/auth`, {
    method: metodo,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const texto = await resposta.text();
  let dados = null;
  try {
    dados = texto ? JSON.parse(texto) : null;
  } catch {
    dados = texto;
  }
  return { status: resposta.status, dados };
}

// ⚠️ Fim de linha normalizado para LF nos DOIS lados da comparação, e no que se
//    envia. Sem isso o `--conferir` acusa divergência falsa: o repositório tem
//    `core.autocrlf` do Windows e o arquivo em disco vem com CRLF, enquanto o
//    painel guarda o que o navegador mandou ao colar, que é LF. Guarda que não
//    distingue verdade de defeito produz alarme falso — mesmo desfecho de não
//    ter guarda (lição do `--role-only` do card 3.11).
export const paraLf = (texto) => texto.replace(/\r\n/g, '\n');

export function carregar() {
  return MODELOS.map((m) => ({
    ...m,
    corpo: paraLf(readFileSync(join(AQUI, m.arquivo), 'utf8')),
  }));
}

const mostrar = (v) => (v === undefined ? 'ausente' : JSON.stringify(v));

/** Confere que o painel tem EXATAMENTE o que está no repositório. */
export function conferir(atual, modelos) {
  const divergencias = [];
  for (const m of modelos) {
    const assunto = atual?.[m.campoAssunto];
    const corpo = atual?.[m.campoCorpo] == null ? null : paraLf(atual[m.campoCorpo]);
    if (assunto !== m.assunto) {
      divergencias.push(`${m.rotulo}: assunto no painel é ${JSON.stringify(assunto)}, esperado ${JSON.stringify(m.assunto)}`);
    }
    // Comparação do corpo por conteúdo, não por tamanho: o painel devolve o
    // que gravou, e um byte a menos é template editado à mão lá dentro.
    if (corpo !== m.corpo) {
      const detalhe = corpo == null
        ? 'vazio (o painel está com o template padrão do Supabase, em inglês)'
        : `${corpo.length} bytes, e o repositório tem ${m.corpo.length}`;
      divergencias.push(`${m.rotulo}: corpo divergente — ${detalhe}`);
    }
  }
  // Igualdade estrita: `"86400"` (texto) ou `null` não são 86400. Campo
  // AUSENTE da resposta também reprova — é como um nome trocado se apresenta
  // na leitura de volta.
  for (const a of AJUSTES) {
    const valor = atual?.[a.campo];
    if (valor !== a.valor) {
      divergencias.push(`${a.rotulo} (${a.campo}): painel ${mostrar(valor)}, esperado ${JSON.stringify(a.valor)} — ${a.toml}`);
    }
  }
  return divergencias;
}

/** O corpo do PATCH: os campos listados, e nenhum outro. */
export function montarPatch(modelos) {
  const corpo = {};
  for (const m of modelos) {
    corpo[m.campoAssunto] = m.assunto;
    corpo[m.campoCorpo] = m.corpo;
  }
  for (const a of AJUSTES) corpo[a.campo] = a.valor;
  return corpo;
}

/** Todos os nomes de campo que o script lê e grava. */
export function camposUsados() {
  return [
    ...MODELOS.flatMap((m) => [m.campoAssunto, m.campoCorpo]),
    ...AJUSTES.map((a) => a.campo),
  ];
}

function resolverSchema(spec, schema) {
  const ref = schema?.$ref;
  return ref ? spec.components.schemas[ref.split('/').pop()] : schema;
}

/**
 * Confere os nomes contra a spec OpenAPI da Management API: cada campo tem de
 * existir no corpo do PATCH E na resposta do GET (sem a segunda metade, o
 * script gravaria e não teria como conferir), e cada valor de enum tem de ser
 * um dos aceitos. Devolve a lista de problemas — vazia é aprovado.
 */
export function conferirNomes(spec) {
  const caminho = spec?.paths?.[ENDPOINT];
  if (!caminho?.patch || !caminho?.get) {
    return [`a spec não tem PATCH e GET em ${ENDPOINT} — o endpoint mudou de nome`];
  }
  const corpoPatch = resolverSchema(spec, caminho.patch.requestBody?.content?.['application/json']?.schema);
  const respostaGet = resolverSchema(spec, caminho.get.responses?.['200']?.content?.['application/json']?.schema);
  const problemas = [];
  for (const campo of camposUsados()) {
    if (!corpoPatch?.properties?.[campo]) problemas.push(`${campo}: não existe no corpo do PATCH`);
    if (!respostaGet?.properties?.[campo]) problemas.push(`${campo}: não existe na resposta do GET`);
  }
  for (const a of AJUSTES) {
    const enumerado = corpoPatch?.properties?.[a.campo]?.enum;
    if (enumerado && !enumerado.includes(a.valor)) {
      problemas.push(`${a.campo}: ${JSON.stringify(a.valor)} não é um dos valores aceitos (${enumerado.length} no enum)`);
    }
  }
  return problemas;
}

async function baixarSpec() {
  const resposta = await fetch(SPEC);
  if (resposta.status !== 200) throw new Error(`GET ${SPEC} devolveu ${resposta.status}`);
  return resposta.json();
}

export async function principal(argumentos) {
  const somenteConferir = argumentos.includes('--conferir');
  const somenteNomes = argumentos.includes('--conferir-nomes');
  const ref = argumentos.find((a) => !a.startsWith('--'));
  const token = process.env.SUPABASE_ACCESS_TOKEN;

  if (somenteNomes) {
    const problemas = conferirNomes(await baixarSpec());
    if (problemas.length) {
      for (const p of problemas) console.error(`  · ${p}`);
      return sair(`${problemas.length} problema(s) de nome ou valor que a Management API não aceita.`);
    }
    console.log(`\n✓ Os ${camposUsados().length} campos existem no PATCH e no GET de ${ENDPOINT}.\n`);
    return;
  }

  if (!ref) {
    return sair('Falta o ref do projeto. Ex.: node supabase/templates/aplicar-templates.mjs ncdfolxdupbbfvtydngx');
  }
  if (!token) {
    return sair(
      'Falta SUPABASE_ACCESS_TOKEN — é o *personal access token* da conta, criado em\n' +
        '  https://supabase.com/dashboard/account/tokens\n' +
        '  Não é a service key nem a chave publicável do projeto.',
    );
  }

  const modelos = carregar();
  console.log(`\nProjeto ${ref}`);
  for (const m of modelos) console.log(`  ${m.arquivo}: ${m.corpo.length} bytes`);

  const antes = await pedir('GET', ref, token);
  if (antes.status !== 200) {
    return sair(`GET da configuração devolveu ${antes.status}: ${JSON.stringify(antes.dados).slice(0, 300)}`);
  }
  const pendentes = conferir(antes.dados, modelos);
  console.log('\nAntes:');
  for (const d of pendentes) console.log(`  · ${d}`);
  if (pendentes.length === 0) console.log('  · já está igual ao repositório');

  if (somenteConferir) {
    if (pendentes.length) return sair(`${pendentes.length} divergência(s) — rode sem --conferir para aplicar.`);
    console.log('\n✓ Painel em dia com o repositório.\n');
    return;
  }

  // Antes de escrever: os nomes existem? Spec inalcançável não impede — a
  // leitura de volta continua sendo a prova —, mas nome que a spec NÃO tem
  // impede, porque esse PATCH é o 200 que não muda nada.
  try {
    const problemas = conferirNomes(await baixarSpec());
    if (problemas.length) {
      for (const p of problemas) console.error(`  · ${p}`);
      return sair('Nome de campo que a spec da Management API não reconhece — nada foi gravado.');
    }
  } catch (erro) {
    console.warn(`\n! Não deu para baixar a spec (${erro.message}); seguindo, a leitura de volta confere.`);
  }

  const patch = await pedir('PATCH', ref, token, montarPatch(modelos));
  if (patch.status !== 200) {
    return sair(`PATCH devolveu ${patch.status}: ${JSON.stringify(patch.dados).slice(0, 400)}`);
  }
  // A prova não é o 200 do PATCH: é a leitura de volta.
  const depois = await pedir('GET', ref, token);
  const divergencias = conferir(depois.dados, modelos);
  if (divergencias.length) {
    console.error('\n✗ O PATCH devolveu 200 e a configuração NÃO ficou igual ao repositório:');
    for (const d of divergencias) console.error(`  · ${d}`);
    console.error('\n  Provável causa: nome de campo mudou na Management API. Conferir o');
    console.error(`  endpoint PATCH ${ENDPOINT} antes de confiar neste script.\n`);
    process.exitCode = 1;
    return;
  }
  console.log('\n✓ Aplicado e conferido por leitura de volta:');
  for (const m of modelos) console.log(`  · ${m.rotulo} — "${m.assunto}"`);
  for (const a of AJUSTES) console.log(`  · ${a.rotulo} = ${JSON.stringify(a.valor)}`);
  console.log('');
}

// Só roda quando chamado pela linha de comando — importado pela suíte, não.
// `pathToFileURL(resolve(...))` e não a comparação crua: no Windows `argv[1]`
// é `C:\…` e `import.meta.url` é `file:///C:/…`, e a comparação crua nunca
// casa (pendência 9.20, o portão de migrações que saía 0 sem varrer nada).
const ehPrincipal = () =>
  process.argv[1] !== undefined && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (ehPrincipal()) await principal(process.argv.slice(2));
