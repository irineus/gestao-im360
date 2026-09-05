// A obrigação de teste do tipo "Migração de dados (Fase 9)", vista do lado do produtor.
//
// `docs/estrategia-testes.md` §13 exige, para a Fase 9, *"importar duas vezes o
// mesmo snapshot produz os mesmos totais, sem duplicar"*. O importador provou a
// metade dele (card 9.1, `supabase/tests/100_importacao.sql`). A outra metade é
// daqui: se o extrator não for determinístico, o importador reexecutável não serve
// para nada — a segunda leitura da mesma planilha chegaria com chaves diferentes e
// criaria tudo de novo, e `movimento_estoque` é imutável.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { comoCsv } from '../relatorio.mjs';
import { extrair } from '../transformacao.mjs';
import { SNAPSHOT, planilha } from './fixture.mjs';

function extrairTexto(fonte) {
  const { arquivo, ocorrencias } = extrair(fonte, SNAPSHOT);
  return { json: JSON.stringify(arquivo, null, 2), csv: comoCsv(ocorrencias) };
}

const chaves = (fonte) => extrair(fonte, SNAPSHOT).arquivo.movimento_estoque.map((m) => m.chave);

describe('determinismo', () => {
  it('a mesma planilha produz os mesmos bytes', () => {
    assert.deepEqual(extrairTexto(planilha()), extrairTexto(planilha()));
  });

  it('nada no arquivo depende do relógio', () => {
    // Se o extrator olhasse o relógio, o diff entre dois snapshots seria ruído e a
    // conferência do card 9.4 não conseguiria dizer o que mudou.
    const { json } = extrairTexto(planilha());
    assert.equal(json.split(SNAPSHOT).length - 1, 1);
  });
});

describe('estabilidade da chave do movimento', () => {
  it('movimento novo no fim não mexe nas chaves dos antigos', () => {
    const antes = chaves(planilha());
    const depois = chaves(planilha([['2026-06-04', 1, 1, 3605]]));
    assert.deepEqual(depois.slice(0, antes.length), antes);
    assert.equal(depois.length, antes.length + 1);
  });

  it('a chave não depende da posição da linha', () => {
    // Linha inserida no meio é o que mais acontece numa planilha viva. Se a chave
    // carregasse o número da linha, um `insert` deslocaria TODAS as de baixo e a
    // reimportação duplicaria o histórico inteiro.
    const antes = new Set(chaves(planilha()));
    const depois = new Set(chaves(planilha([['2026-01-05', 1, 2, 4433]])));
    for (const chave of antes) assert.equal(depois.has(chave), true, chave);
  });

  it('a chave carrega o que identifica o movimento', () => {
    assert.deepEqual(chaves(planilha()).filter((c) => c.startsWith('ENTRADA-')),
      ['ENTRADA-2026-02-01-INTERATIVO-1-SEM_ALUNO-10-1']);
  });
});

describe('relatório', () => {
  it('ERRO vem primeiro e a ordem é estável', () => {
    const { csv } = extrairTexto(planilha());
    assert.equal(csv, extrairTexto(planilha()).csv);
    const linhas = csv.trim().split('\n');
    assert.equal(linhas[0], 'severidade;codigo;entidade;chave;detalhe');
    // ERRO antes de AVISO — que é o CONTRÁRIO da ordem alfabética, e é de propósito:
    // quem abre o relatório precisa ver primeiro o que impede a importação.
    const severidades = linhas.slice(1).map((l) => l.split(';')[0]);
    const ultimoErro = severidades.lastIndexOf('ERRO');
    assert.equal(severidades.slice(0, ultimoErro + 1).every((s) => s === 'ERRO'), true);
    assert.ok(ultimoErro >= 0, 'a fixture tem ERRO: as quatro abas não mapeadas');
  });

  it('detalhe com ponto e vírgula não parte a linha em duas colunas', () => {
    const { csv } = extrairTexto(planilha());
    for (const linha of csv.trim().split('\n')) {
      const foraDeAspas = linha.replace(/"(?:[^"]|"")*"/g, '');
      assert.equal(foraDeAspas.split(';').length, 5, linha);
    }
  });
});
