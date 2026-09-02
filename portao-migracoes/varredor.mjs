#!/usr/bin/env node
// =============================================================================
// Portão de migrações — card 4.0,5
//
// Reprova a migração que GRAVA DADO em tabela fora da lista permitida.
//
// Por que existe: todo `.sql` posto em `supabase/migrations/` chega a PRODUÇÃO
// sozinho no merge em `main`. A decisão de 02/09/2026 (Decisões vigentes, §1,
// "Dado de negócio só em dev até a virada") diz que dado de planilha entra pelo
// importador do card 9.1, contra o ambiente em que a pessoa está logada, e nunca
// por migração. Regra escrita depende de alguém lembrar; as duas falhas do
// projeto até aqui foram de esquecimento, não de julgamento — daí um portão.
//
// LISTA PERMITIDA, NÃO LISTA PROIBIDA. Tabela nova nasce protegida sem ninguém
// se lembrar de nada. Lista proibida deixaria de fora toda tabela futura — e
// falharia em silêncio, que é o desfecho que este projeto cataloga.
//
// O QUE O VARREDOR PRECISA DISTINGUIR (o ponto delicado do card): `insert into
// pendencia` VAI aparecer em migração legítima, dentro do CORPO de uma função
// (`gerar_pendencias`, card 5.5; `registrar_entrega`, card 6.3). Corpo de função
// é código que roda depois, quando alguém chamar; não é dado gravado pela
// migração. Então:
//
//   * corpo de `create [or replace] function/procedure` NÃO é executado —
//     a não ser que a própria migração CHAME a função, e aí o corpo conta,
//     transitivamente. É por isso que o seed do card 3.6 passa: ele chama
//     `fn_seed_acesso`, e tudo o que essa função escreve é dado de configuração.
//     E é por isso que `create function fn_seed_catalogo() … ; select
//     fn_seed_catalogo();` não é um disfarce que funcione.
//   * bloco `do $$ … $$` É executado na hora da migração — é justamente por onde
//     uma carga entraria disfarçada, então nunca se remove.
//
// Uso:
//   node portao-migracoes/varredor.mjs [diretório ou arquivo …]   (padrão: supabase/migrations)
//
// Sai com 0 se tudo o que a migração grava está na lista; 1 caso contrário, ou
// se encontrar SQL que não consegue ler (fail-closed: o que não se entende
// reprova).
// =============================================================================

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Dado de CONFIGURAÇÃO — precisa estar em produção, senão `tem_permissao()` é
 * falso para todo mundo (card 3.6). `metodo` é a única exceção deliberada do
 * catálogo: enumeração fixa do produto, já referenciada pelos parâmetros
 * `ritmo_padrao_dias_*` do seed (card 4.1).
 *
 * `usuario_perfil` não está na lista escrita na nota do card 4.0,5 e está aqui:
 * `fn_seed_direcao_inicial`, chamada pelo seed do 3.6, liga o primeiro usuário
 * ao perfil DIRECAO. É a mesma configuração de acesso que a nota já permite em
 * `perfil` e `perfil_permissao` — sem ela o seed que o card manda exigir verde
 * ficaria vermelho. Divergência registrada em docs/ci-cd.md §14.
 *
 * AMPLIAR ESTA LISTA É MEXER NO PORTÃO, de propósito: é exatamente a conversa
 * que se quer ter antes de mandar dado novo para produção.
 */
export const TABELAS_PERMITIDAS = new Set([
  'unidade',
  'perfil',
  'permissao',
  'perfil_permissao',
  'usuario',
  'usuario_perfil',
  'parametro',
  'metodo',
]);

export class ErroDeLeitura extends Error {}

const quebras = (s) => (s.match(/\n/g) || []).length;

// ---------------------------------------------------------------------------
// 1. Separação léxica
//
// Devolve o texto com comentários removidos, literais e blocos entre cifrões
// trocados por marcas (§sN§ e §dN§) e tudo o mais em minúsculas. As quebras de
// linha do que sai são reemitidas no lugar, para que o número da linha
// denunciada continue sendo o número da linha do arquivo.
// ---------------------------------------------------------------------------

function separar(sql) {
  let texto = '';
  const strings = [];
  const dolares = [];
  let i = 0;
  let linha = 1;
  const n = sql.length;

  while (i < n) {
    const c = sql[i];

    if (c === '-' && sql[i + 1] === '-') {
      while (i < n && sql[i] !== '\n') i++;
      continue;
    }

    if (c === '/' && sql[i + 1] === '*') {
      // aninhável no Postgres, ao contrário do SQL padrão
      const linhaIni = linha;
      let prof = 0;
      while (i < n) {
        if (sql[i] === '/' && sql[i + 1] === '*') { prof++; i += 2; continue; }
        if (sql[i] === '*' && sql[i + 1] === '/') { prof--; i += 2; if (prof === 0) break; continue; }
        if (sql[i] === '\n') { texto += '\n'; linha++; }
        i++;
      }
      if (prof !== 0) throw new ErroDeLeitura(`comentário /* … */ não fechado (linha ${linhaIni})`);
      continue;
    }

    if (c === "'") {
      const linhaIni = linha;
      let valor = '';
      let fechou = false;
      i++;
      while (i < n) {
        if (sql[i] === "'" && sql[i + 1] === "'") { valor += "'"; i += 2; continue; }
        if (sql[i] === "'") { i++; fechou = true; break; }
        if (sql[i] === '\n') linha++;
        valor += sql[i++];
      }
      if (!fechou) throw new ErroDeLeitura(`literal de texto não fechado (linha ${linhaIni})`);
      strings.push({ valor, linha: linhaIni });
      texto += `§s${strings.length - 1}§` + '\n'.repeat(quebras(valor));
      continue;
    }

    if (c === '"') {
      // identificador entre aspas: o conteúdo continua no texto, sem as aspas
      const linhaIni = linha;
      let valor = '';
      let fechou = false;
      i++;
      while (i < n) {
        if (sql[i] === '"' && sql[i + 1] === '"') { valor += '"'; i += 2; continue; }
        if (sql[i] === '"') { i++; fechou = true; break; }
        if (sql[i] === '\n') linha++;
        valor += sql[i++];
      }
      if (!fechou) throw new ErroDeLeitura(`identificador entre aspas não fechado (linha ${linhaIni})`);
      texto += valor.toLowerCase();
      continue;
    }

    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 66));
      if (m) {
        const marca = m[0];
        const linhaIni = linha;
        const fim = sql.indexOf(marca, i + marca.length);
        if (fim === -1) throw new ErroDeLeitura(`bloco ${marca} não fechado (linha ${linhaIni})`);
        const conteudo = sql.slice(i + marca.length, fim);
        dolares.push({ conteudo, linha: linhaIni, prefixoAte: texto.length });
        texto += `§d${dolares.length - 1}§` + '\n'.repeat(quebras(conteudo));
        linha += quebras(conteudo);
        i = fim + marca.length;
        continue;
      }
    }

    if (c === '\n') linha++;
    texto += c.toLowerCase();
    i++;
  }

  return { texto, strings, dolares };
}

// ---------------------------------------------------------------------------
// 2. Decomposição: o que executa na migração, o que só define função
// ---------------------------------------------------------------------------

const ALVO = String.raw`(?:[a-z_][a-z0-9_$]*\s*\.\s*)?[a-z_][a-z0-9_$]*`;
const RE_DEF_FUNCAO = /\bcreate\s+(?:or\s+replace\s+)?(?:function|procedure)\b/;
const RE_NOME_FUNCAO = new RegExp(
  String.raw`\bcreate\s+(?:or\s+replace\s+)?(?:function|procedure)\s+(${ALVO})`, 'g');

function ultimoTrecho(texto, ate) {
  return texto.slice(texto.lastIndexOf(';', ate - 1) + 1, ate);
}

function nomeSimples(alvo) {
  const partes = alvo.split('.').map((p) => p.trim());
  return { esquema: partes.length > 1 ? partes[0] : null, nome: partes[partes.length - 1] };
}

/**
 * Decompõe um trecho de SQL em:
 *   - `regioes`: o que a migração EXECUTA (nível superior + blocos `do $$`);
 *   - `funcoes`: os corpos definidos, que só contam se alguém os chamar.
 */
function decompor(sql, linhaBase, strings) {
  const { texto, strings: locais, dolares } = separar(sql);
  strings.push(...locais);
  const deslocamentoStrings = strings.length - locais.length;
  const regioes = [{ texto, linhaBase, nivel: 'topo', strings, deslocamentoStrings }];
  const funcoes = [];

  for (const d of dolares) {
    const prefixo = ultimoTrecho(texto, d.prefixoAte);
    const linhaDoBloco = linhaBase + d.linha - 1;

    if (RE_DEF_FUNCAO.test(prefixo)) {
      RE_NOME_FUNCAO.lastIndex = 0;
      let nome = null;
      for (const m of texto.slice(0, d.prefixoAte).matchAll(RE_NOME_FUNCAO)) nome = m[1];
      const sub = decompor(d.conteudo, linhaDoBloco, strings);
      funcoes.push({
        nome: nome ? nomeSimples(nome).nome : `(anônima na linha ${linhaDoBloco})`,
        regioes: sub.regioes.map((r) => ({ ...r, nivel: 'plpgsql' })),
      });
      funcoes.push(...sub.funcoes);
      continue;
    }

    if (/^\s*do\b/.test(prefixo)) {
      const sub = decompor(d.conteudo, linhaDoBloco, strings);
      regioes.push(...sub.regioes.map((r) => ({ ...r, nivel: 'plpgsql' })));
      funcoes.push(...sub.funcoes);
      continue;
    }

    // Qualquer outro bloco entre cifrões (`comment on … is $$…$$`, texto de
    // `check`) é conteúdo, não código: não executa e não define nada.
  }

  return { regioes, funcoes };
}

// ---------------------------------------------------------------------------
// 3. O que conta como escrita
// ---------------------------------------------------------------------------

const ESCRITAS = [
  { op: 'insert into', re: new RegExp(String.raw`\binsert\s+into\s+(\S+)`, 'g') },
  { op: 'delete from', re: new RegExp(String.raw`\bdelete\s+from\s+(?:only\s+)?(\S+)`, 'g') },
  { op: 'merge into', re: new RegExp(String.raw`\bmerge\s+into\s+(?:only\s+)?(\S+)`, 'g') },
  { op: 'copy', re: new RegExp(String.raw`\bcopy\s+(\S+)\s*(?:\(|from\b)`, 'g') },
  { op: 'truncate', re: new RegExp(String.raw`\btruncate\s+(?:table\s+)?(?:only\s+)?(\S+)`, 'g') },
  // UPDATE sem SET não é UPDATE: exigir o `set` é o que separa a escrita de
  // `on update cascade`, de `for update` e de `on conflict do update`.
  {
    op: 'update',
    re: new RegExp(
      String.raw`\bupdate\s+(?:only\s+)?(${ALVO})(?:\s+(?:as\s+)?[a-z_][a-z0-9_$]*)?\s+set\b`, 'g'),
  },
];

const RE_CHAMADA = /(?:^|[^a-z0-9_$.])((?:[a-z_][a-z0-9_$]*\s*\.\s*)?[a-z_][a-z0-9_$]*)\s*\(/g;
const RE_MARCA_STRING = /^§s(\d+)§/;
// Cabeças de comando que, no nível superior, chamam função. `create trigger …
// execute function fn()` NÃO chama nada agora: registra quem chamar depois.
const CABECA_EXECUTA = /^\s*(select|call|perform|with|insert|update|delete|merge)\b/;

function linhaDe(regiao, deslocamento) {
  return regiao.linhaBase + quebras(regiao.texto.slice(0, deslocamento));
}

function fatiar(texto) {
  const fatias = [];
  let inicio = 0;
  for (let i = 0; i < texto.length; i++) {
    if (texto[i] === ';') { fatias.push({ texto: texto.slice(inicio, i), deslocamento: inicio }); inicio = i + 1; }
  }
  fatias.push({ texto: texto.slice(inicio), deslocamento: inicio });
  return fatias;
}

function normalizarAlvo(bruto) {
  const limpo = bruto.replace(/[(;,]+$/, '').trim();
  if (!/^(?:[a-z_][a-z0-9_$]*\s*\.\s*)?[a-z_][a-z0-9_$]*$/.test(limpo)) return null;
  return nomeSimples(limpo);
}

function escritasDe(regiao) {
  const achados = [];
  for (const { op, re } of ESCRITAS) {
    re.lastIndex = 0;
    for (const m of regiao.texto.matchAll(re)) {
      const alvo = normalizarAlvo(m[1]);
      const linha = linhaDe(regiao, m.index);
      if (!alvo) {
        achados.push({ linha, op, tabela: null, motivo: `alvo de \`${op}\` não identificado (\`${m[1]}\`)` });
        continue;
      }
      achados.push({ linha, op, esquema: alvo.esquema, tabela: alvo.nome });
    }
  }
  return achados;
}

/** SQL montado em tempo de execução: o que o portão não consegue ler, reprova. */
function dinamicosDe(regiao) {
  const achados = [];
  const re = /(^|[^a-z0-9_$.])execute\s+/g;
  for (const m of regiao.texto.matchAll(re)) {
    const depois = regiao.texto.slice(m.index + m[0].length);
    if (/^(function|procedure)\b/.test(depois)) continue;   // `create trigger … execute function`
    const anterior = regiao.texto.slice(0, m.index).match(/([a-z_]+)[\s,]*$/);
    if (anterior && ['grant', 'revoke', 'insert', 'update', 'delete', 'select', 'references', 'trigger', 'truncate', 'usage', 'all', 'on'].includes(anterior[1])) continue;
    const linha = linhaDe(regiao, m.index + m[0].length - 'execute '.length);
    const marca = RE_MARCA_STRING.exec(depois);
    // Só um literal INTEIRO e sozinho é legível. `'insert into ' || v_tabela`
    // não é: o comando de verdade só existe quando a migração já está rodando.
    const sozinho = marca && /^\s*(;|using\b|into\b|$)/.test(depois.slice(marca[0].length));
    if (!marca || !sozinho) {
      achados.push({ linha, motivo: 'SQL dinâmico (`execute`) que o portão não consegue ler — escreva o comando literalmente ou tire-o da migração' });
      continue;
    }
    const literal = regiao.strings[Number(marca[1])];
    if (!literal) continue;
    const sub = { texto: literal.valor.toLowerCase(), linhaBase: linha, strings: regiao.strings };
    for (const e of escritasDe(sub)) achados.push({ ...e, linha, dinamico: true });
  }
  return achados;
}

function chamadasDe(regiao) {
  const alvos = [];
  const trechos = regiao.nivel === 'topo'
    ? fatiar(regiao.texto).filter((f) => CABECA_EXECUTA.test(f.texto))
    : [{ texto: regiao.texto, deslocamento: 0 }];
  for (const t of trechos) {
    for (const m of t.texto.matchAll(RE_CHAMADA)) {
      const antes = t.texto.slice(0, m.index + m[0].indexOf(m[1])).match(/([a-z_]+)\s+$/);
      if (antes && ['function', 'procedure', 'default', 'table', 'trigger', 'on', 'references'].includes(antes[1])) continue;
      alvos.push({
        nome: nomeSimples(m[1]).nome,
        linha: linhaDe(regiao, t.deslocamento + m.index),
      });
    }
  }
  return alvos;
}

// ---------------------------------------------------------------------------
// 4. Varredura
// ---------------------------------------------------------------------------

export function varrerConjunto(arquivos) {
  const funcoes = new Map();
  const unidades = [];
  const erros = [];

  for (const { arquivo, sql } of arquivos) {
    try {
      const strings = [];
      const { regioes, funcoes: definidas } = decompor(sql, 1, strings);
      for (const f of definidas) if (!funcoes.has(f.nome)) funcoes.set(f.nome, { ...f, arquivo });
      unidades.push({ arquivo, regioes });
    } catch (e) {
      if (!(e instanceof ErroDeLeitura)) throw e;
      erros.push({ arquivo, motivo: e.message });
    }
  }

  const relatorio = { arquivos: [], erros, aprovado: erros.length === 0 };

  for (const u of unidades) {
    const permitidas = [];
    const barradas = [];
    const visitadas = new Set();

    const percorrer = (regioes, arquivoTrecho, caminho) => {
      for (const regiao of regioes) {
        for (const a of [...escritasDe(regiao), ...dinamicosDe(regiao)]) {
          const local = `${arquivoTrecho}:${a.linha}`;
          if (a.motivo) { barradas.push({ ...a, local, caminho, motivo: a.motivo }); continue; }
          const qualificada = a.esquema && a.esquema !== 'public' ? `${a.esquema}.${a.tabela}` : a.tabela;
          const permitida = (!a.esquema || a.esquema === 'public') && TABELAS_PERMITIDAS.has(a.tabela) && !a.dinamico;
          const registro = { ...a, local, caminho, tabela: qualificada };
          if (permitida) permitidas.push(registro);
          else barradas.push({ ...registro, motivo: a.dinamico
            ? `\`${a.op} ${qualificada}\` dentro de \`execute\` — escrita montada em tempo de execução não passa pelo portão`
            : `\`${a.op} ${qualificada}\` — tabela fora da lista permitida` });
        }
        for (const c of chamadasDe(regiao)) {
          const f = funcoes.get(c.nome);
          if (!f || visitadas.has(c.nome)) continue;
          visitadas.add(c.nome);
          percorrer(f.regioes, f.arquivo, [...caminho, `${c.nome}()`]);
        }
      }
    };

    percorrer(u.regioes, u.arquivo, []);
    relatorio.arquivos.push({ arquivo: u.arquivo, permitidas, barradas });
    if (barradas.length) relatorio.aprovado = false;
  }

  return relatorio;
}

export function varrerSql(arquivo, sql) {
  return varrerConjunto([{ arquivo, sql }]);
}

export function listarMigracoes(caminhos) {
  const arquivos = [];
  for (const caminho of caminhos) {
    if (statSync(caminho).isDirectory()) {
      for (const nome of readdirSync(caminho).sort()) {
        if (nome.toLowerCase().endsWith('.sql')) arquivos.push(join(caminho, nome));
      }
    } else {
      arquivos.push(caminho);
    }
  }
  return arquivos.map((arquivo) => ({ arquivo, sql: readFileSync(arquivo, 'utf8') }));
}

// ---------------------------------------------------------------------------
// 5. Linha de comando
// ---------------------------------------------------------------------------

export function formatar(relatorio) {
  const linhas = [];
  for (const a of relatorio.arquivos) {
    const via = (c) => (c.length ? ` (via ${c.join(' → ')})` : '');
    if (a.barradas.length) {
      linhas.push(`✗ ${a.arquivo}`);
      for (const b of a.barradas) linhas.push(`    ${b.local}${via(b.caminho)}: ${b.motivo}`);
    } else {
      const resumo = a.permitidas.length
        ? `${a.permitidas.length} escrita(s) em tabela permitida: ${[...new Set(a.permitidas.map((p) => p.tabela))].sort().join(', ')}`
        : 'nenhuma escrita de dado';
      linhas.push(`✓ ${a.arquivo} — ${resumo}`);
    }
  }
  for (const e of relatorio.erros) linhas.push(`✗ ${e.arquivo}: não foi possível ler o SQL — ${e.motivo}`);
  return linhas.join('\n');
}

function principal(argv) {
  const caminhos = argv.length ? argv : ['supabase/migrations'];
  const arquivos = listarMigracoes(caminhos);
  if (!arquivos.length) {
    console.log('Portão de migrações: nenhum arquivo .sql encontrado em ' + caminhos.join(', '));
    return 0;
  }
  const relatorio = varrerConjunto(arquivos);
  console.log(formatar(relatorio));
  if (relatorio.aprovado) {
    console.log(`\nPortão de migrações: ${arquivos.length} migração(ões) varrida(s), nenhuma grava fora da lista permitida.`);
    return 0;
  }
  console.log(`
─────────────────────────────────────────────────────────────────────────────
REPROVADO. Migração é o que o CI empurra para PRODUÇÃO sozinho no merge em
\`main\` (Decisões vigentes §1, "Dado de negócio só em dev até a virada").

Tabelas em que uma migração pode gravar: ${[...TABELAS_PERMITIDAS].sort().join(', ')}.

Dado de negócio (materiais, cursos, módulos, combos, alunos, salas, PCs,
professores, blocos, trilha, estoque, pedidos) entra pelo importador do card 9.1,
carregado só no projeto dev/homolog, e alcança produção uma única vez, na virada
do card 9.7. Dado de teste vive em \`supabase/seed.sql\`, que nunca sai do stack
local (card 3.4.5).

Se a tabela nova for mesmo CONFIGURAÇÃO, ampliar a lista é um commit em
portao-migracoes/varredor.mjs — que é a conversa que este portão existe para
provocar.
─────────────────────────────────────────────────────────────────────────────`);
  return 1;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  process.exit(principal(process.argv.slice(2)));
}
