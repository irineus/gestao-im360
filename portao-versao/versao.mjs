// Portão de versão — card 9.2,83 (01/10/2026, regra de Irineu).
//
// A versão do sistema é a do `version:` de `app/pubspec.yaml`, semântica
// (MAJOR.MINOR.REVISION+BUILD), mostrada na tela de entrada e no menu do
// usuário. A regra:
//
//   - REVISION sobe em TODA mudança que gere código novo (lista
//     CAMINHOS_DE_CODIGO abaixo) — e o BUILD sobe junto, porque é ele que as
//     lojas exigem crescente;
//   - MINOR é sugerida pela sessão (feature grande, fechamento de fase);
//   - MAJOR só por pedido explícito de Irineu — o portão não tem como saber
//     disso, então ele só AVISA quando a major muda.
//
// Por que um portão e não só a regra escrita: regra que depende de alguém
// lembrar não serve (lição do card 3.12), e a versão existe exatamente para
// dizer "qual app está aberto" — dois deploys diferentes com o mesmo número
// mentiriam com cara de informação. Duas PRs que sobem a mesma versão batem na
// mesma linha do pubspec e a segunda precisa ser refeita, o que é o certo.
//
// Uso (CI, só em pull_request): node portao-versao/versao.mjs origin/<base>

import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

/// O que conta como "código novo": tudo o que chega a um ambiente. Testes,
/// documentos, workflows e ferramentas de apoio não contam.
export const CAMINHOS_DE_CODIGO = [
  'app/lib/',
  'app/web/',
  'app/assets/',
  'app/pubspec.yaml',
  'supabase/migrations/',
  'supabase/functions/',
  'worker-vigia/src/',
];

/// O `version:` que o `flutter create` gera e que o projeto carregou até o card
/// 9.2,83 sem significar nada. A primeira versão de verdade (0.1.0) é MENOR que
/// ele, e o portão aceita essa única descida.
export const VERSAO_DE_FABRICA = '1.0.0+1';

/// `version: 0.1.0+3` → { nome: '0.1.0', partes: [0,1,0], build: 3 }.
export function lerVersao(pubspec) {
  const linha = pubspec.split(/\r?\n/).find((l) => /^version:/.test(l));
  if (!linha) throw new Error('app/pubspec.yaml sem a linha "version:"');
  const m = linha.match(/^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$/);
  if (!m) {
    throw new Error(
      `version inválida: "${linha.trim()}" — o formato é MAJOR.MINOR.REVISION+BUILD (ex.: 0.1.0+1)`,
    );
  }
  const partes = [Number(m[1]), Number(m[2]), Number(m[3])];
  return { nome: partes.join('.'), partes, build: Number(m[4]), bruto: `${partes.join('.')}+${m[4]}` };
}

/// -1, 0 ou 1, comparando MAJOR, depois MINOR, depois REVISION.
export function compararNome(a, b) {
  for (let i = 0; i < 3; i++) {
    if (a.partes[i] !== b.partes[i]) return a.partes[i] < b.partes[i] ? -1 : 1;
  }
  return 0;
}

export function mexeEmCodigo(arquivos) {
  return arquivos.filter((f) => CAMINHOS_DE_CODIGO.some((c) => f === c || f.startsWith(c)));
}

/// O veredito, puro: { ok, mensagens }.
export function veredito({ arquivos, pubspecBase, pubspecCabeca }) {
  const mensagens = [];
  const cabeca = lerVersao(pubspecCabeca);
  const base = lerVersao(pubspecBase);
  const deFabrica = base.bruto === VERSAO_DE_FABRICA;
  const codigo = mexeEmCodigo(arquivos);

  if (!deFabrica && cabeca.partes[0] !== base.partes[0]) {
    mensagens.push(
      `aviso: a MAJOR mudou (${base.nome} → ${cabeca.nome}) — só por pedido explícito de Irineu`,
    );
  }

  if (!deFabrica && compararNome(cabeca, base) < 0) {
    return { ok: false, mensagens: [...mensagens, `a versão DESCEU: ${base.bruto} → ${cabeca.bruto}`] };
  }
  if (!deFabrica && cabeca.build < base.build) {
    return { ok: false, mensagens: [...mensagens, `o BUILD desceu: ${base.bruto} → ${cabeca.bruto}`] };
  }

  if (codigo.length === 0) {
    return { ok: true, mensagens: [...mensagens, `sem código novo; versão ${cabeca.bruto}`] };
  }

  if (deFabrica && cabeca.bruto === VERSAO_DE_FABRICA) {
    return {
      ok: false,
      mensagens: [...mensagens, `este PR muda código e a versão ainda é a de fábrica (${VERSAO_DE_FABRICA}); a primeira é 0.1.0+1`],
    };
  }
  if (!deFabrica && compararNome(cabeca, base) === 0) {
    return {
      ok: false,
      mensagens: [
        ...mensagens,
        `este PR muda código (${codigo.slice(0, 5).join(', ')}${codigo.length > 5 ? ', …' : ''}) e a versão continua ${base.bruto}.`,
        `Suba a REVISION em app/pubspec.yaml (ex.: ${base.partes[0]}.${base.partes[1]}.${base.partes[2] + 1}+${base.build + 1}).`,
      ],
    };
  }
  if (!deFabrica && cabeca.build <= base.build) {
    return {
      ok: false,
      mensagens: [...mensagens, `a versão subiu e o BUILD não: ${base.bruto} → ${cabeca.bruto} (use +${base.build + 1})`],
    };
  }
  return { ok: true, mensagens: [...mensagens, `versão ${base.bruto} → ${cabeca.bruto}`] };
}

function git(...args) {
  return execFileSync('git', args, { encoding: 'utf8' });
}

function principal(base) {
  if (!base) {
    console.error('uso: node portao-versao/versao.mjs <ref-base>   (ex.: origin/develop)');
    return 2;
  }
  const arquivos = git('diff', '--name-only', `${base}...HEAD`).split('\n').filter(Boolean);
  const resultado = veredito({
    arquivos,
    pubspecBase: git('show', `${base}:app/pubspec.yaml`),
    pubspecCabeca: git('show', 'HEAD:app/pubspec.yaml'),
  });
  for (const m of resultado.mensagens) {
    console.log(resultado.ok ? m : `::error title=Versão::${m}`);
  }
  return resultado.ok ? 0 : 1;
}

// Mesma guarda do portão de migrações (card 9.2,76): compara por URL, que casa
// no Windows e no Linux.
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = principal(process.argv[2]);
}
