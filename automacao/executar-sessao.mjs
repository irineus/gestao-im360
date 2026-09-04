#!/usr/bin/env node
// Abre UMA sessão do Claude Code e narra o que ela faz, ao vivo. Card 5.5,5.
//
// POR QUE ESTE ARQUIVO SUBSTITUI O `formatar-stream.mjs`
// -----------------------------------------------------
// A primeira tentativa de narração punha o filtro DEPOIS do `claude`, numa
// pipeline do PowerShell: `claude … | node formatar-stream.mjs`. Funcionou nos
// testes de fumaça e falhou na primeira corrida de verdade — e a diferença
// entre os dois casos é só a DURAÇÃO.
//
// Quando o PowerShell canaliza um comando nativo para outro comando nativo, ele
// escreve na entrada do segundo em BLOCOS, e só descarrega quando o primeiro
// termina. Numa sessão de 3 segundos o processo encerra e tudo sai junto: a
// narração parece funcionar. Numa sessão de 40 minutos não sai nada até o fim —
// que é exatamente o silêncio que a narração existia para acabar. O conserto do
// buffer do `claude` tinha apenas criado outro buffer, um passo adiante.
//
// Aqui o node ABRE o `claude` e lê a saída dele por um pipe do sistema
// operacional. O PowerShell deixa de estar no meio: ele só CONSOME a saída
// deste processo, que é o lado que ele sempre soube transmitir linha a linha.
// De quebra somem as duas armadilhas de encoding do PowerShell 5.1 (o
// `$OutputEncoding` ASCII e o BOM do `[System.Text.Encoding]::UTF8`), porque
// nenhuma delas participa de um pipe que o PowerShell não escreve.
//
// USO
//   node executar-sessao.mjs <exe> <arq-prompt> <arq-narracao> <arq-bruto> [ferramenta…]
//
// SAÍDA
//   stdout  narração legível, linha a linha, conforme acontece
//   <arq-narracao>  a mesma narração
//   <arq-bruto>     o JSONL cru, para quando o resumo não bastar
//
// CÓDIGO DE SAÍDA
//   o do `claude`; ou 3 se a sessão terminou sem evento `result` — "não chegou
//   ao fim" é diferente de "terminou sem veredito", e quem distingue é aqui.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { appendFileSync, readFileSync } from 'node:fs';

const [exe, arqPrompt, arqNarracao, arqBruto, ...ferramentas] = process.argv.slice(2);

if (!exe || !arqPrompt || !arqNarracao) {
  console.error('uso: executar-sessao.mjs <exe> <arq-prompt> <arq-narracao> <arq-bruto> [ferramenta…]');
  process.exit(2);
}

const LARGURA = 140;

function encurtar(texto, limite = LARGURA) {
  const limpo = String(texto ?? '').replace(/\s+/g, ' ').trim();
  return limpo.length > limite ? limpo.slice(0, limite - 1) + '…' : limpo;
}

/**
 * O argumento que identifica a chamada, por ferramenta.
 *
 * Mostrar o `input` inteiro afogaria a narração — um Edit carrega o arquivo
 * novo inteiro. Para quem acompanha, o que importa é *o que* está sendo mexido.
 */
function resumirFerramenta(nome, input = {}) {
  switch (nome) {
    case 'Bash':      return encurtar(input.command, 110);
    case 'Read':
    case 'Write':
    case 'Edit':      return encurtar(input.file_path, 110);
    case 'Glob':
    case 'Grep':      return encurtar(input.pattern, 110);
    case 'TodoWrite': return `${(input.todos || []).length} itens`;
    default: {
      const alvo = input.id ?? input.url ?? input.query ?? input.page_id ?? input.description;
      return alvo ? encurtar(alvo, 110) : '';
    }
  }
}

function emitir(linha) {
  process.stdout.write(linha + '\n');
  try { appendFileSync(arqNarracao, linha + '\n', 'utf8'); } catch { /* console já recebeu */ }
}

let viuResultado = false;

function tratarEvento(linha) {
  if (arqBruto) {
    try { appendFileSync(arqBruto, linha + '\n', 'utf8'); } catch { /* bruto é conveniência */ }
  }

  let evento;
  try {
    evento = JSON.parse(linha.replace(/^﻿/, ''));
  } catch {
    emitir(linha); // aviso do CLI, não evento — passa como está.
    return;
  }

  switch (evento.type) {
    case 'system':
      if (evento.subtype === 'init') emitir('  · sessão iniciada');
      break;

    case 'assistant':
      for (const parte of evento.message?.content ?? []) {
        if (parte.type === 'text' && parte.text?.trim()) {
          emitir('  · ' + encurtar(parte.text));
        } else if (parte.type === 'tool_use') {
          const alvo = resumirFerramenta(parte.name, parte.input);
          emitir(`  → ${parte.name}${alvo ? ': ' + alvo : ''}`);
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
          emitir('  ✗ ferramenta falhou: ' + encurtar(txt, 120));
        }
      }
      break;

    case 'result': {
      viuResultado = true;
      const seg = ((evento.duration_ms ?? 0) / 1000).toFixed(1);
      const custo = evento.total_cost_usd != null
        ? `US$ ${evento.total_cost_usd.toFixed(4)}`
        : 'custo n/d';
      emitir(`  ── sessão encerrada: ${evento.num_turns ?? '?'} turnos · ${seg}s · ${custo}`);
      // Inteiro e sem tocar: é daqui que o driver lê a linha de veredito.
      if (evento.result) emitir(String(evento.result));
      break;
    }

    default:
      break; // rate_limit_event e o que vier depois: ruído para quem acompanha.
  }
}

const prompt = readFileSync(arqPrompt, 'utf8');

const argumentos = [
  '-p', prompt,
  '--permission-mode', 'acceptEdits',
  '--output-format', 'stream-json',
  '--verbose',
];
if (ferramentas.length) argumentos.push('--allowedTools', ...ferramentas);

// `stdin: 'ignore'` de propósito: com stdin aberto e vazio o CLI espera alguns
// segundos por dados que nunca vêm ("no stdin data received in 3s"). Multiplicado
// por 30 cards é tempo jogado fora, e o aviso ainda sujaria a narração.
//
// `shell` só quando o executável é um atalho .cmd/.bat do npm — para o .exe
// resolvido, `shell: false` evita ter de citar um prompt de milhares de
// caracteres, que é onde esse tipo de invocação costuma quebrar.
const precisaShell = /\.(cmd|bat)$/i.test(exe);

const filho = spawn(exe, argumentos, {
  stdio: ['ignore', 'pipe', 'pipe'],
  shell: precisaShell,
  windowsHide: true,
});

createInterface({ input: filho.stdout, crlfDelay: Infinity })
  .on('line', tratarEvento);

createInterface({ input: filho.stderr, crlfDelay: Infinity })
  .on('line', (l) => { if (l.trim()) emitir('  ! ' + encurtar(l, 120)); });

filho.on('error', (e) => {
  emitir(`  ✗ não consegui executar "${exe}": ${e.message}`);
  process.exit(2);
});

filho.on('close', (codigo) => {
  if (!viuResultado) {
    emitir('  ✗ a sessão terminou sem evento `result` — não chegou ao fim.');
    process.exit(3);
  }
  process.exit(codigo ?? 0);
});
