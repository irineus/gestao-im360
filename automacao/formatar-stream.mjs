#!/usr/bin/env node
// Tradutor do `--output-format stream-json` do Claude Code para uma narração
// legível, ao vivo. Card 5.5,5.
//
// POR QUE ESTE ARQUIVO EXISTE
// --------------------------
// `claude -p` com saída em texto **bufferiza a resposta inteira** e só imprime
// quando a sessão termina. Num card `GG` isso é meia hora de silêncio depois de
// uma única linha dizendo onde fica o log — foi exatamente o que Irineu viu na
// primeira corrida: nada até o erro aparecer. Numa cadeia que roda sem ninguém
// olhando, não poder olhar *quando se quer* é o defeito que mais pesa.
//
// `stream-json` resolve, mas troca o silêncio por uma parede de JSON. Este
// filtro fica no meio: lê os eventos conforme chegam e escreve duas coisas —
//   • stdout: a narração curta, que o driver mostra e grava no log do card;
//   • arquivo bruto (argv[2]), opcional: o JSONL inteiro, para quando o resumo
//     não bastar e for preciso reconstituir o que houve.
//
// A ÚLTIMA linha do `result` é reimpressa inteira, sem corte: é dela que o
// driver lê o veredito `>>> CARD_OK` / `CARD_PARADO` / `CADEIA_FIM`.

import { createInterface } from 'node:readline';
import { appendFileSync } from 'node:fs';

const arquivoBruto = process.argv[2] || null;

/** Uma linha por evento, curta o bastante para caber no terminal. */
const LARGURA = 140;

function encurtar(texto, limite = LARGURA) {
  const limpo = String(texto ?? '').replace(/\s+/g, ' ').trim();
  return limpo.length > limite ? limpo.slice(0, limite - 1) + '…' : limpo;
}

/**
 * O argumento que identifica a chamada, por ferramenta.
 *
 * Mostrar o `input` inteiro afogaria a narração — um Edit carrega o arquivo
 * novo inteiro. O que interessa a quem acompanha é *o que* está sendo mexido.
 */
function resumirFerramenta(nome, input = {}) {
  switch (nome) {
    case 'Bash':      return encurtar(input.command, 110);
    case 'Read':
    case 'Write':     return encurtar(input.file_path, 110);
    case 'Edit':      return encurtar(input.file_path, 110);
    case 'Glob':
    case 'Grep':      return encurtar(input.pattern, 110);
    case 'TodoWrite': return `${(input.todos || []).length} itens`;
    default: {
      // MCP e ferramentas novas: mostra o primeiro campo com cara de alvo.
      const alvo = input.id ?? input.url ?? input.query ?? input.page_id ?? input.description;
      return alvo ? encurtar(alvo, 110) : '';
    }
  }
}

function emitir(linha) {
  process.stdout.write(linha + '\n');
}

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });

// Numa pipeline do PowerShell, `$LASTEXITCODE` é o código do ÚLTIMO comando —
// ou seja, deste filtro, e não do `claude`. Em vez de deixar essa informação
// morrer, este processo assume a responsabilidade: sem evento `result`, a
// sessão não chegou ao fim, e isso é diferente de ter terminado sem veredito.
let viuResultado = false;

for await (const linha of rl) {
  if (!linha.trim()) continue;
  if (arquivoBruto) {
    try { appendFileSync(arquivoBruto, linha + '\n'); } catch { /* log bruto é conveniência */ }
  }

  let evento;
  try {
    // O `replace` tira BOM: quem escreve neste stdin pode carimbá-lo na
    // primeira linha, e aí só ela falharia no parse e sairia crua na narração.
    evento = JSON.parse(linha.replace(/^﻿/, ''));
  } catch {
    // Não é JSON: é aviso do CLI em stderr, e passa adiante como está — foi um
    // aviso desses ("Ignoring 22 permissions.allow entries") que denunciou o
    // diretório não confiado.
    emitir(linha);
    continue;
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
      // Só denuncia ferramenta que VOLTOU ERRO. O resultado que deu certo já
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
      const custo = evento.total_cost_usd != null ? `US$ ${evento.total_cost_usd.toFixed(4)}` : 'custo n/d';
      emitir(`  ── sessão encerrada: ${evento.num_turns ?? '?'} turnos · ${seg}s · ${custo}`);
      // Inteiro e sem tocar: é daqui que o driver lê a linha de veredito.
      if (evento.result) emitir(String(evento.result));
      break;
    }

    default:
      break; // rate_limit_event e o que vier depois: ruído para quem acompanha.
  }
}

if (!viuResultado) {
  emitir('  ✗ a sessão terminou sem evento `result` — não chegou ao fim.');
  process.exit(3);
}
