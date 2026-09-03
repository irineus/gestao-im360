#!/usr/bin/env node
// Aplica os templates de e-mail deste diretório no painel de um projeto
// Supabase remoto, pela Management API — card 4.7,6 (docs/emails-auth.md §4).
//
// Uso:
//   SUPABASE_ACCESS_TOKEN=sbp_... node supabase/templates/aplicar-templates.mjs <ref-do-projeto>
//   ...                                                                        --conferir <ref>
//
//   dev  = ncdfolxdupbbfvtydngx      prod = aqfuawrygxsiopyppjza
//
// ⚠️ POR QUE ESTE SCRIPT EXISTE, E NÃO `supabase config push`.
//    O `config push` empurra o config.toml INTEIRO e o que não está no arquivo
//    volta ao default — e `[auth.email.smtp]` está DELIBERADAMENTE fora dele
//    (decisão de 02/09/2026: o SMTP do Resend vive só no painel). Um `config
//    push` apagaria o SMTP dos dois projetos, e o sintoma seria convite e
//    recuperação parando de chegar, em silêncio, dias depois. Este script faz
//    um PATCH de QUATRO CAMPOS e não toca em mais nada.
//
// ⚠️ A conferência é POSITIVA, como o vigia do card 3.10 e o backup do 3.11:
//    não basta o PATCH devolver 200. O script lê a configuração de volta e
//    exige que o assunto e o tamanho do corpo sejam os do repositório. Nome de
//    campo errado na API devolveria 200 sem mudar nada, e "não deu erro" teria
//    passado por sucesso.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));

// Os quatro campos da Management API. Os nomes vêm do endpoint
// PATCH /v1/projects/{ref}/config/auth — se algum estiver errado, a conferência
// abaixo reprova em vez de deixar passar.
const MODELOS = [
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
];

const API = 'https://api.supabase.com/v1/projects';

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
const paraLf = (texto) => texto.replace(/\r\n/g, '\n');

function carregar() {
  return MODELOS.map((m) => ({
    ...m,
    corpo: paraLf(readFileSync(join(AQUI, m.arquivo), 'utf8')),
  }));
}

/** Confere que o painel tem EXATAMENTE o que está no repositório. */
function conferir(atual, modelos) {
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
  return divergencias;
}

const argumentos = process.argv.slice(2);
const somenteConferir = argumentos.includes('--conferir');
const ref = argumentos.find((a) => !a.startsWith('--'));
const token = process.env.SUPABASE_ACCESS_TOKEN;

if (!ref) {
  sair('Falta o ref do projeto. Ex.: node supabase/templates/aplicar-templates.mjs ncdfolxdupbbfvtydngx');
} else if (!token) {
  sair(
    'Falta SUPABASE_ACCESS_TOKEN — é o *personal access token* da conta, criado em\n' +
      '  https://supabase.com/dashboard/account/tokens\n' +
      '  Não é a service key nem a chave publicável do projeto.',
  );
} else {
  const modelos = carregar();
  console.log(`\nProjeto ${ref}`);
  for (const m of modelos) {
    console.log(`  ${m.arquivo}: ${m.corpo.length} bytes`);
  }

  const antes = await pedir('GET', ref, token);
  if (antes.status !== 200) {
    sair(`GET da configuração devolveu ${antes.status}: ${JSON.stringify(antes.dados).slice(0, 300)}`);
  } else {
    console.log('\nAntes:');
    for (const d of conferir(antes.dados, modelos)) console.log(`  · ${d}`);
    if (conferir(antes.dados, modelos).length === 0) console.log('  · já está igual ao repositório');

    if (somenteConferir) {
      const pendentes = conferir(antes.dados, modelos);
      if (pendentes.length) sair(`${pendentes.length} divergência(s) — rode sem --conferir para aplicar.`);
      else console.log('\n✓ Painel em dia com o repositório.\n');
    } else {
      const corpo = {};
      for (const m of modelos) {
        corpo[m.campoAssunto] = m.assunto;
        corpo[m.campoCorpo] = m.corpo;
      }
      const patch = await pedir('PATCH', ref, token, corpo);
      if (patch.status !== 200) {
        sair(`PATCH devolveu ${patch.status}: ${JSON.stringify(patch.dados).slice(0, 400)}`);
      } else {
        // A prova não é o 200 do PATCH: é a leitura de volta.
        const depois = await pedir('GET', ref, token);
        const divergencias = conferir(depois.dados, modelos);
        if (divergencias.length) {
          console.error('\n✗ O PATCH devolveu 200 e a configuração NÃO ficou igual ao repositório:');
          for (const d of divergencias) console.error(`  · ${d}`);
          console.error('\n  Provável causa: nome de campo mudou na Management API. Conferir o');
          console.error('  endpoint PATCH /v1/projects/{ref}/config/auth antes de confiar neste script.\n');
          process.exitCode = 1;
        } else {
          console.log('\n✓ Aplicado e conferido por leitura de volta:');
          for (const m of modelos) console.log(`  · ${m.rotulo} — "${m.assunto}"`);
          console.log('');
        }
      }
    }
  }
}
