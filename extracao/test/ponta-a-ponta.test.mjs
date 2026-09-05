// A costura: um `.xlsx` de verdade, lido pelo leitor de verdade, passando pelo CLI
// de verdade e chegando nos dois arquivos que o card 9.4 vai usar.
//
// Os outros testes medem as camadas separadas — de propósito, porque é isso que faz
// a suíte rodar sem a planilha. Este mede a EMENDA, que é onde mora o defeito que
// nenhum teste de unidade vê: um deslocamento de coluna entre o que o leitor
// devolve e o que o `layout.mjs` espera passaria por todos eles.

import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, it } from 'node:test';

import { principal } from '../extrair.mjs';
import { extrair } from '../transformacao.mjs';
import { abrirBuffer } from '../xlsx.mjs';
import { comoXlsx } from './construir-xlsx.mjs';
import { SNAPSHOT, planilha } from './fixture.mjs';

function comoObjeto(fonte) {
  return Object.fromEntries(fonte.abas().map((aba) => [aba, fonte.linhas(aba)]));
}

const memoria = planilha();
const buffer = comoXlsx(comoObjeto(memoria));

describe('ponta a ponta', () => {
  it('o .xlsx lido do disco dá o MESMO arquivo que a planilha em memória', () => {
    // Se um dia isto divergir, o defeito está na emenda leitor × layout, e não na
    // transformação — que os outros testes já cobrem.
    const doArquivo = extrair(abrirBuffer(buffer), SNAPSHOT);
    const daMemoria = extrair(memoria, SNAPSHOT);
    assert.deepEqual(doArquivo.arquivo, daMemoria.arquivo);
    assert.deepEqual(doArquivo.ocorrencias, daMemoria.ocorrencias);
  });

  it('o CLI escreve os dois arquivos e sai 1 por causa das abas não mapeadas', () => {
    const dir = mkdtempSync(join(tmpdir(), 'extracao-'));
    const origem = join(dir, 'planilha.xlsx');
    writeFileSync(origem, buffer);

    const ditas = [];
    const codigo = principal(
      [origem, '--snapshot', SNAPSHOT, '--saida', dir], (linha) => ditas.push(linha),
    );

    // Sai 1 de propósito: o dry-run do card 9.4 não deve começar por um arquivo que
    // já se sabe incompleto, e script que sai 0 com ERRO no relatório é script cujo
    // relatório ninguém abre.
    assert.equal(codigo, 1);
    assert.equal(ditas.some((l) => l.includes('ficaram FORA do arquivo')), true);

    const json = JSON.parse(readFileSync(join(dir, `importacao-${SNAPSHOT}.json`), 'utf8'));
    assert.equal(json.snapshot_em, SNAPSHOT);
    assert.equal(json.aluno.length, extrair(memoria, SNAPSHOT).arquivo.aluno.length);

    const csv = readFileSync(join(dir, `inconsistencias-${SNAPSHOT}.csv`), 'utf8');
    // BOM: o destino é o Excel em português, e sem ele o acento da primeira coluna
    // sai quebrado na tela de quem revisa (card 9.3).
    assert.equal(csv.charCodeAt(0), 0xfeff);
    assert.match(csv, /severidade;codigo;entidade;chave;detalhe/);
    assert.match(csv, /ABA_NAO_MAPEADA/);
  });

  it('--snapshot ausente ou inválido para o extrator antes de ele ler nada', () => {
    // Um default de "hoje" faria a MESMA planilha produzir arquivos diferentes
    // conforme o dia da extração — a lição do V12 do importador.
    assert.throws(() => principal(['x.xlsx']), /falta --snapshot/);
    assert.throws(() => principal(['x.xlsx', '--snapshot', '29/08/2026']), /AAAA-MM-DD/);
    assert.throws(() => principal(['x.xlsx', '--snapshot', '2026-02-30']), /AAAA-MM-DD/);
  });

  it('--mapear imprime as abas sem mapa, com a letra de cada coluna', () => {
    const dir = mkdtempSync(join(tmpdir(), 'extracao-'));
    const origem = join(dir, 'planilha.xlsx');
    // Uma planilha com a aba PCS presente, que é o caso em que o --mapear serve.
    writeFileSync(origem, comoXlsx({
      PCS: [['PC', 'Situação'], ['PC-01', 'OPERACIONAL']],
    }));
    const ditas = [];
    assert.equal(principal([origem, '--mapear'], (l) => ditas.push(l)), 0);
    const saida = ditas.join('\n');
    assert.match(saida, /PCS {2}→ {2}sala, pc, pc_manutencao/);
    assert.match(saida, /L1 {3}A\(0\) = "PC"/);
    assert.match(saida, /L2 {3}B\(1\) = "OPERACIONAL"/);
    // As que não existem na planilha dizem isso, em vez de sumirem.
    assert.match(saida, /Base Modular: nenhuma aba com esse nome/);
  });
});
