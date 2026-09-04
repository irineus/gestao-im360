#!/usr/bin/env node
// Abre UMA sessão do Claude Code e narra o que ela faz, ao vivo. Card 5.5,5.
//
// POR QUE O NODE ABRE O `claude`, E NÃO UMA PIPELINE DO POWERSHELL
// ----------------------------------------------------------------
// A primeira tentativa de narração punha o filtro DEPOIS do `claude`, numa
// pipeline do PowerShell. Funcionou nos testes de fumaça e falhou na primeira
// corrida de verdade — e a diferença entre os dois casos era só a DURAÇÃO.
//
// Quando o PowerShell canaliza um comando nativo para outro comando nativo, ele
// escreve na entrada do segundo em BLOCOS e só descarrega quando o primeiro
// termina. Numa sessão de 3 segundos tudo sai junto e a narração parece
// funcionar; numa de 40 minutos não sai NADA até o fim — que é exatamente o
// silêncio que a narração existia para acabar.
//
// Aqui o pipe é do sistema operacional e o PowerShell só CONSOME a saída, que é
// o lado que ele sempre transmitiu linha a linha.
//
// USO
//   node executar-sessao.mjs <exe> <arq-prompt> <arq-narracao> <arq-bruto> \
//                            <arq-limite> [--model <m>] [ferramenta…]
//
// SAÍDA
//   stdout          narração com cor e relógio (para quem acompanha)
//   <arq-narracao>  a MESMA narração sem cor — é dela que o driver lê o veredito,
//                   e código ANSI antes do `>>>` quebraria o casamento
//   <arq-bruto>     o JSONL cru
//   <arq-limite>    o último `rate_limit_info` visto, que é como o driver estima
//                   se o próximo card cabe na janela de 5 horas
//
// CÓDIGO DE SAÍDA
//   o do `claude`; ou 3 se a sessão terminou sem evento `result` — "não chegou
//   ao fim" é diferente de "terminou sem veredito", e quem distingue é aqui.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { appendFileSync, writeFileSync, readFileSync } from 'node:fs';

const args = process.argv.slice(2);
const [exe, arqPrompt, arqNarracao, arqBruto, arqLimite] = args;

let modelo = null;
const iModelo = args.indexOf('--model');
if (iModelo !== -1) modelo = args[iModelo + 1];

const ferramentas = args
  .slice(5)
  .filter((a, i, arr) => a !== '--model' && arr[i - 1] !== '--model');

if (!exe || !arqPrompt || !arqNarracao) {
  console.error('uso: executar-sessao.mjs <exe> <prompt> <narracao> <bruto> <limite> [--model m] [ferramenta…]');
  process.exit(2);
}

// ---------------------------------------------------------------------------
// Aparência
//
// Cor só no stdout. O arquivo de narração fica limpo de propósito: o driver
// procura `^>>> CARD_OK` nele, e um escape ANSI na frente quebraria o regex —
// o tipo de defeito que só aparece no card em que importa.
// ---------------------------------------------------------------------------
// ⚠️ A cor NÃO sai em ANSI. O driver canaliza este stdout, e `Write-Host` do
// PowerShell 5.1 não interpreta escape de terminal — os códigos apareceriam
// crus no meio da narração (medido em 04/09/2026). O protocolo é uma etiqueta
// de cor antes de uma tabulação; o driver a converte em `-ForegroundColor`, que
// funciona no console do Windows sem depender de VT.
//
// Uma cor por linha, e não por trecho: `Write-Host` colore a chamada inteira, e
// emendar chamadas com `-NoNewline` para pintar rótulo e alvo em tons
// diferentes custaria mais do que entrega.
const COR = {
  relogio: 'DarkGray',
  inicio: 'Cyan',
  fala: 'Gray',
  ferramenta: 'Green',
  escrita: 'Yellow',
  erro: 'Red',
  aviso: 'Yellow',
  resumo: 'White',
  cru: 'DarkGray',
};

const COLUNAS = Math.max(60, Math.min(process.stdout.columns || 120, 160));
const inicio = Date.now();

function relogio() {
  const s = Math.floor((Date.now() - inicio) / 1000);
  return `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
}

/** Quebra em linhas que cabem no terminal, com recuo de continuação. */
function dobrar(texto, largura) {
  const palavras = String(texto).replace(/\s+/g, ' ').trim().split(' ');
  const linhas = [];
  let atual = '';
  for (const p of palavras) {
    if (atual && (atual + ' ' + p).length > largura) { linhas.push(atual); atual = p; }
    else atual = atual ? atual + ' ' + p : p;
  }
  if (atual) linhas.push(atual);
  return linhas;
}

/**
 * Escreve uma entrada da narração.
 *
 * O console recebe `Cor<TAB>texto`, que o driver converte em
 * `-ForegroundColor`; o arquivo recebe só o texto. A separação é o que mantém o
 * arquivo legível para o regex do veredito — etiqueta de cor antes do `>>>`
 * quebraria o casamento.
 */
function emitir(plano, cor = COR.cru) {
  process.stdout.write(`${cor}\t${plano}\n`);
  try { appendFileSync(arqNarracao, plano + '\n', 'utf8'); } catch { /* console já recebeu */ }
}

/**
 * Uma linha de evento: relógio, marcador, rótulo em coluna, e o detalhe dobrado.
 *
 * ⚠️ O rótulo NÃO passa pelo `dobrar`: ele normaliza espaço em branco e comeria
 * o preenchimento da coluna, deixando `▸ Bash node --version` em vez de
 * `▸ Bash            node --version`. A coluna é o que permite varrer a
 * narração de cima a baixo e ver o que é ferramenta e o que é alvo.
 */
function linhaEvento(marcador, cor, rotulo, detalhe) {
  const cabeca = `  ${relogio()} ${marcador}  `;
  const rot = rotulo ? rotulo.padEnd(16) : '';
  const linhas = dobrar(detalhe ?? '', Math.max(24, COLUNAS - cabeca.length - rot.length - 2));

  emitir(cabeca + rot + (linhas[0] ?? ''), cor);
  const recuo = ' '.repeat(cabeca.length + rot.length);
  for (const extra of linhas.slice(1)) emitir(recuo + extra, cor);
}

// ---------------------------------------------------------------------------
// Tradução dos eventos
// ---------------------------------------------------------------------------

/** O argumento que identifica a chamada, por ferramenta. */
function alvoDaFerramenta(nome, input = {}) {
  const curto = (v, n = 200) => String(v ?? '').replace(/\s+/g, ' ').trim().slice(0, n);
  switch (nome) {
    case 'Bash':      return curto(input.command);
    case 'Read':
    case 'Write':
    case 'Edit':      return curto(input.file_path).replace(/^.*[/\\](?=(app|docs|supabase|automacao|\.claude)[/\\])/, '');
    case 'Glob':
    case 'Grep':      return curto(input.pattern);
    case 'TodoWrite': return `${(input.todos || []).length} itens`;
    default: {
      const alvo = input.id ?? input.url ?? input.query ?? input.page_id ?? input.description;
      return alvo ? curto(alvo) : '';
    }
  }
}

/** Ferramentas de MCP viram `Notion·fetch`, que cabe na coluna. */
function nomeCurto(nome) {
  const m = /^mcp__[^_]*_?([A-Za-z]+)__(.+)$/.exec(nome);
  if (!m) return nome;
  return `${m[1]}·${m[2].replace(/^notion-/, '')}`;
}

let viuResultado = false;
let ultimoLimite = null;

function tratarEvento(linha) {
  if (arqBruto) {
    try { appendFileSync(arqBruto, linha + '\n', 'utf8'); } catch { /* bruto é conveniência */ }
  }

  let evento;
  try {
    evento = JSON.parse(linha.replace(/^﻿/, ''));
  } catch {
    emitir(linha, COR.cru); // aviso do CLI, não evento
    return;
  }

  // O estado da janela de 5 horas chega junto de qualquer evento; guardar o
  // último é o que permite ao driver decidir se o PRÓXIMO card cabe.
  if (evento.rate_limit_info) ultimoLimite = evento.rate_limit_info;

  switch (evento.type) {
    case 'system':
      if (evento.subtype === 'init') {
        const m = evento.model ? ` · ${evento.model}` : '';
        linhaEvento('•', COR.inicio, null, `sessão iniciada${m}`);
      }
      break;

    case 'assistant':
      for (const parte of evento.message?.content ?? []) {
        if (parte.type === 'text' && parte.text?.trim()) {
          for (const p of String(parte.text).split(/\n{2,}/).slice(0, 4)) {
            if (p.trim()) linhaEvento('»', COR.fala, null, p);
          }
        } else if (parte.type === 'tool_use') {
          const escrita = /^(Write|Edit|NotebookEdit)$/.test(parte.name) ||
                          /update-page|create-pages/.test(parte.name);
          linhaEvento(escrita ? '✎' : '▸', escrita ? COR.escrita : COR.ferramenta,
                      nomeCurto(parte.name), alvoDaFerramenta(parte.name, parte.input));
        }
      }
      break;

    case 'user':
      // Só denuncia ferramenta que VOLTOU ERRO: o resultado que deu certo já
      // está implícito no passo seguinte, e imprimi-lo dobraria a narração.
      for (const parte of evento.message?.content ?? []) {
        if (parte.type === 'tool_result' && parte.is_error) {
          const txt = Array.isArray(parte.content)
            ? parte.content.map((c) => c.text ?? '').join(' ')
            : parte.content;
          linhaEvento('✗', COR.erro, null, String(txt).slice(0, 300));
        }
      }
      break;

    case 'result': {
      viuResultado = true;
      const seg = Math.round((evento.duration_ms ?? 0) / 1000);
      const dur = `${Math.floor(seg / 60)}m${String(seg % 60).padStart(2, '0')}s`;
      const custo = evento.total_cost_usd != null
        ? `US$ ${evento.total_cost_usd.toFixed(2)}`
        : 'custo n/d';
      const uso = ultimoLimite?.unifiedWindows?.five_hour?.utilization;
      const janela = uso != null ? ` · janela 5h em ${(uso * 100).toFixed(0)}%` : '';
      const resumo = `${evento.num_turns ?? '?'} turnos · ${dur} · ${custo}${janela}`;

      emitir(`  ──── ${resumo}`, COR.resumo);

      // Verbatim: é daqui que o driver lê a linha de veredito, e o arquivo de
      // narração recebe o texto sem a etiqueta de cor.
      if (evento.result) emitir(String(evento.result), COR.resumo);
      break;
    }

    default:
      break; // rate_limit_event e o que vier depois: já foi lido acima.
  }
}

// ---------------------------------------------------------------------------
const prompt = readFileSync(arqPrompt, 'utf8');

const argumentos = [
  '-p', prompt,
  '--permission-mode', 'acceptEdits',
  '--output-format', 'stream-json',
  '--verbose',
];
if (modelo) argumentos.push('--model', modelo);
if (ferramentas.length) argumentos.push('--allowedTools', ...ferramentas);

// `stdin: 'ignore'` de propósito: com stdin aberto e vazio o CLI espera alguns
// segundos por dados que nunca vêm ("no stdin data received in 3s"), e o aviso
// ainda sujaria a narração.
//
// `shell` só quando o executável é atalho `.cmd`/`.bat` do npm — com o `.exe`
// resolvido, `shell: false` evita citar um prompt de milhares de caracteres,
// que é onde esse tipo de invocação quebra.
const filho = spawn(exe, argumentos, {
  stdio: ['ignore', 'pipe', 'pipe'],
  shell: /\.(cmd|bat)$/i.test(exe),
  windowsHide: true,
});

createInterface({ input: filho.stdout, crlfDelay: Infinity }).on('line', tratarEvento);
createInterface({ input: filho.stderr, crlfDelay: Infinity })
  .on('line', (l) => { if (l.trim()) linhaEvento('!', COR.aviso, null, l.slice(0, 240)); });

filho.on('error', (e) => {
  linhaEvento('✗', COR.erro, null, `não consegui executar "${exe}": ${e.message}`);
  process.exit(2);
});

filho.on('close', (codigo) => {
  if (arqLimite && ultimoLimite) {
    try {
      writeFileSync(arqLimite, JSON.stringify({ ...ultimoLimite, lidoEm: new Date().toISOString() }, null, 2), 'utf8');
    } catch { /* a estimativa cai no padrão documentado */ }
  }
  if (!viuResultado) {
    linhaEvento('✗', COR.erro, null, 'a sessão terminou sem evento result — não chegou ao fim.');
    process.exit(3);
  }
  process.exit(codigo ?? 0);
});
