#!/usr/bin/env node
// CLI da extração (card 9.2).
//
//   node extracao/extrair.mjs "Gestão Interativo.xlsx" --snapshot 2026-08-29 --saida saida/
//
// Escreve dois arquivos, e os dois são entregáveis:
//
// - `importacao-<snapshot>.json`     — o arquivo do card 9.1 (`docs/importacao.md` §3);
// - `inconsistencias-<snapshot>.csv` — o relatório que o card 9.3 revisa.
//
// ⚠️ `--snapshot` é OBRIGATÓRIO e não tem default de "hoje". A data do snapshot muda
// o veredito de metade do relatório (previsão vencida, ano do "(dd/mm)"), e um
// default faria a MESMA planilha produzir arquivos diferentes conforme o dia da
// extração — que é a razão do V12 do importador comparar com o snapshot e não com
// hoje. O card 9.4 ainda manda registrar a data de cada rodada: divergir de totais
// tirados de dias diferentes já é divergir por nada.
//
// `--mapear` não extrai nada: imprime as primeiras linhas das abas que ainda não
// têm mapa de colunas, com a letra de cada coluna. É o caminho para fechar as
// lacunas do `layout.mjs` com a planilha aberta ao lado, sem adivinhar posição.

import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

import * as L from './layout.mjs';
import { data } from './valores.mjs';
import { abrirXlsx } from './xlsx.mjs';
import { ERRO, comoCsv, contar } from './relatorio.mjs';
import { extrair, totais } from './transformacao.mjs';

const USO = `uso: node extracao/extrair.mjs <planilha.xlsx> --snapshot AAAA-MM-DD [opções]

  --snapshot AAAA-MM-DD   data do snapshot da planilha (obrigatório)
  --saida <dir>           diretório de saída (padrão: o atual)
  --sala-laboratorio <n>  nome da sala do laboratório (padrão: ${L.SALA_LABORATORIO_PADRAO})
  --mapear                só imprime as abas sem mapa de colunas, e não extrai
  --linhas <n>            quantas linhas por aba no --mapear (padrão: 6)`;

export function argumentos(argv) {
  const opcoes = {
    planilha: null, snapshot: null, saida: '.',
    salaLaboratorio: L.SALA_LABORATORIO_PADRAO, mapear: false, linhas: 6,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--mapear') opcoes.mapear = true;
    else if (arg === '--snapshot') { i += 1; opcoes.snapshot = argv[i]; }
    else if (arg === '--saida') { i += 1; opcoes.saida = argv[i]; }
    else if (arg === '--sala-laboratorio') { i += 1; opcoes.salaLaboratorio = argv[i]; }
    else if (arg === '--linhas') { i += 1; opcoes.linhas = Number(argv[i]); }
    else if (arg.startsWith('--')) throw new Error(`opção desconhecida: ${arg}\n\n${USO}`);
    else if (opcoes.planilha === null) opcoes.planilha = arg;
    else throw new Error(`argumento sobrando: ${arg}\n\n${USO}`);
  }
  if (opcoes.planilha === null) throw new Error(`falta o caminho da planilha.\n\n${USO}`);
  if (!opcoes.mapear) {
    if (!opcoes.snapshot) throw new Error(`falta --snapshot.\n\n${USO}`);
    // ⚠️ `Date.parse` NÃO serve de validador: o V8 aceita "2026-02-30" e rola para
    // 2 de março, então um snapshot impossível entraria e sairia como outro dia —
    // e a data do snapshot decide metade do relatório. `data()` faz a volta e
    // compara, que é o único jeito de pegar isso.
    if (!/^\d{4}-\d{2}-\d{2}$/.test(opcoes.snapshot)
        || data(opcoes.snapshot) !== opcoes.snapshot) {
      throw new Error(`--snapshot ${opcoes.snapshot} não é uma data AAAA-MM-DD válida.`);
    }
  }
  return opcoes;
}

/** 0 → A, 25 → Z, 26 → AA. */
export function letra(indice) {
  let saida = '';
  let n = indice + 1;
  while (n > 0) {
    const resto = (n - 1) % 26;
    saida = String.fromCharCode(65 + resto) + saida;
    n = Math.floor((n - resto) / 26);
  }
  return saida;
}

export function mapear(planilha, quantas) {
  const existentes = planilha.abas();
  const saida = [`Abas da planilha: ${existentes.join(', ')}`];
  for (const { aba, entidades } of L.ABAS_NAO_MAPEADAS) {
    const alvos = existentes.filter((a) => a === aba || aba.includes(a));
    if (!alvos.length) {
      saida.push(`\n── ${aba}: nenhuma aba com esse nome; procurar à mão.`);
      continue;
    }
    for (const alvo of alvos.sort()) {
      saida.push(`\n── ${alvo}  →  ${entidades.join(', ')}`);
      planilha.linhas(alvo).slice(0, quantas).forEach((linha, numero) => {
        linha.forEach((valor, coluna) => {
          if (valor !== null && valor !== undefined && valor !== '') {
            saida.push(`   L${String(numero + 1).padEnd(3)} ${letra(coluna)}(${coluna}) = `
              + `${JSON.stringify(valor instanceof Date ? valor.toISOString().slice(0, 10) : valor)}`);
          }
        });
      });
    }
  }
  return saida.join('\n');
}

export function principal(argv, escrever = console.log) {
  const opcoes = argumentos(argv);
  const fonte = abrirXlsx(opcoes.planilha);

  if (opcoes.mapear) {
    escrever(mapear(fonte, opcoes.linhas));
    return 0;
  }

  const { arquivo, ocorrencias } = extrair(fonte, opcoes.snapshot, opcoes.salaLaboratorio);

  mkdirSync(opcoes.saida, { recursive: true });
  const alvoJson = join(opcoes.saida, `importacao-${opcoes.snapshot}.json`);
  const alvoCsv = join(opcoes.saida, `inconsistencias-${opcoes.snapshot}.csv`);

  // A ordem das chaves é a ordem de dependência do contrato e NÃO se ordena
  // alfabeticamente: o arquivo é lido por gente antes de ser lido pelo banco.
  writeFileSync(alvoJson, `${JSON.stringify(arquivo, null, 2)}\n`, 'utf8');
  // BOM no CSV porque o destino é o Excel em português; sem ele, acento vira
  // caractere estranho na primeira coluna que alguém abre.
  writeFileSync(alvoCsv, `﻿${comoCsv(ocorrencias)}`, 'utf8');

  const { erros, avisos } = contar(ocorrencias);
  escrever(`${alvoJson}: ${Object.entries(totais(arquivo))
    .map(([k, n]) => `${k} ${n}`).join(', ')}`);
  escrever(`${alvoCsv}: ${erros} ERRO, ${avisos} AVISO`);
  for (const o of ocorrencias) {
    if (o.severidade === ERRO && o.codigo === 'ABA_NAO_MAPEADA') {
      escrever(`  ⚠️ ${o.chave} → ${o.entidade} ficaram FORA do arquivo.`);
    }
  }
  // Sai 1 com ERRO: o dry-run do card 9.4 não deve começar por um arquivo que já se
  // sabe incompleto, e script que sai 0 com erro no relatório é script cujo
  // relatório ninguém abre.
  return erros ? 1 : 0;
}

if (import.meta.filename === process.argv[1]) {
  try {
    process.exitCode = principal(process.argv.slice(2));
  } catch (erro) {
    console.error(erro.message);
    process.exitCode = 2;
  }
}
