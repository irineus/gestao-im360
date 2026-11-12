import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import * as L from '../layout.mjs';
import { catalogoDoCurso, derivarRodizio, linhasDoRodizio } from '../rodizio.mjs';

// Um curso de seis módulos em rodízio, à maneira do exemplo que o dono do
// produto deu nos áudios de 06/11/2026 — cada aluno começa onde a turma estava.
// Os nomes dos módulos são de teste, não os da planilha.
const CHEF = catalogoDoCurso([
  { ordem: 1, nome: 'Higiene e Manipulação' },
  { ordem: 2, nome: 'Massas e Molhos' },
  { ordem: 3, nome: 'Carnes e Aves' },
  { ordem: 4, nome: 'Peixes e Frutos do Mar' },
  { ordem: 5, nome: 'Confeitaria' },
  { ordem: 6, nome: 'Cozinha Internacional' },
]);
const SNAPSHOT = '2026-11-01';

const mod = (nome, inicio, previsao) => ({ nome, inicio, previsao });

describe('derivarRodizio', () => {
  it('a entrada é o PRIMEIRO módulo da linha, e não o primeiro do curso', () => {
    const r = derivarRodizio([
      mod('Carnes e Aves', 'SIM', '30/09/2026'),
      mod('Peixes e Frutos do Mar', 'SIM', '15/11/2026'),
      mod('Confeitaria', 'NÃO', null),
    ], CHEF, SNAPSHOT);
    assert.equal(r.moduloEntrada, 3);
    assert.equal(r.emCurso, 4);
  });

  it('o último iniciado está EM CURSO; os iniciados antes dele estão feitos', () => {
    // A planilha marca módulo iniciado, não concluído. Ter começado o seguinte é
    // o que diz que o anterior acabou.
    const r = derivarRodizio([
      mod('Confeitaria', 'SIM', '31/07/2026'),
      mod('Cozinha Internacional', 'SIM', '15/09/2026'),
      mod('Higiene e Manipulação', 'SIM', '20/11/2026'),
      mod('Massas e Molhos', 'NÃO', '10/01/2027'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(r.feitos, [
      { modulo_ordem: 5, data_conclusao: '2026-07-31' },
      { modulo_ordem: 6, data_conclusao: '2026-09-15' },
    ]);
    assert.equal(r.emCurso, 1, 'deu a volta: depois do 6 veio o 1');
    assert.deepEqual(r.ocorrencias, []);
  });

  it('quem só começou o primeiro não tem módulo feito nenhum', () => {
    const r = derivarRodizio([
      mod('Massas e Molhos', 'SIM', '20/11/2026'),
      mod('Carnes e Aves', 'NÃO', null),
    ], CHEF, SNAPSHOT);
    assert.equal(r.moduloEntrada, 2);
    assert.deepEqual(r.feitos, []);
  });

  it('quem ainda não começou nada tem entrada e nenhum módulo em curso', () => {
    // É o aluno que entrou para começar no próximo módulo. O importador avisa
    // (V19) se a entrada não for o módulo corrente da turma.
    const r = derivarRodizio([
      mod('Carnes e Aves', 'NÃO', '10/01/2027'),
      mod('Peixes e Frutos do Mar', 'NÃO', null),
    ], CHEF, SNAPSHOT);
    assert.equal(r.moduloEntrada, 3);
    assert.equal(r.emCurso, null);
    assert.deepEqual(r.feitos, []);
  });

  it('módulo NÃO iniciado no meio de dois iniciados é o módulo PERDIDO — não é '
    + 'erro, e não entra nos feitos', () => {
    // Regra do STANDBY: "a fazer" é a ausência do registro, e o aluno refaz o
    // módulo quando a turma voltar a ele.
    const r = derivarRodizio([
      mod('Massas e Molhos', 'SIM', '30/06/2026'),
      mod('Carnes e Aves', 'NÃO', '15/08/2026'),
      mod('Peixes e Frutos do Mar', 'SIM', '30/09/2026'),
      mod('Confeitaria', 'SIM', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(r.feitos.map((f) => f.modulo_ordem), [2, 4]);
    assert.deepEqual(r.ocorrencias, []);
  });

  it('módulo feito SEM previsão não sai como feito, e a linha diz por quê', () => {
    // O importador exige a data. Inventar uma faria a ficha afirmar um dia que
    // ninguém registrou.
    const r = derivarRodizio([
      mod('Massas e Molhos', 'SIM', null),
      mod('Carnes e Aves', 'SIM', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(r.feitos, []);
    assert.deepEqual(r.ocorrencias.map((o) => o.codigo), ['MODULO_FEITO_SEM_DATA']);
  });

  it('módulo "feito" com previsão DEPOIS do snapshot sai, com aviso', () => {
    const r = derivarRodizio([
      mod('Massas e Molhos', 'SIM', '15/12/2026'),
      mod('Carnes e Aves', 'SIM', '20/01/2027'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(r.feitos, [{ modulo_ordem: 2, data_conclusao: '2026-12-15' }]);
    assert.deepEqual(r.ocorrencias.map((o) => o.codigo), ['MODULO_FEITO_COM_DATA_FUTURA']);
  });

  it('nome que a Base Modular não conhece vira MODULO_FORA_DO_CATALOGO — a '
    + 'pergunta 5 da proposta', () => {
    // A Base Modular e a aba da turma podem não listar os mesmos módulos
    // ("Higiene e Boas Práticas", no livro Panificação). O módulo não entra em
    // lugar nenhum: nem como entrada, nem como feito.
    const r = derivarRodizio([
      mod('Higiene e Boas Práticas', 'SIM', '30/06/2026'),
      mod('Massas e Molhos', 'SIM', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.equal(r.moduloEntrada, null);
    assert.deepEqual(r.feitos, []);
    assert.deepEqual(r.ocorrencias.map((o) => o.codigo), ['MODULO_FORA_DO_CATALOGO']);
  });

  it('o nome casa sem acento, sem caixa e sem espaço duplo', () => {
    const r = derivarRodizio([
      mod('  MASSAS  e molhos ', 'sim', new Date(Date.UTC(2026, 5, 30))),
      mod('Carnes e Aves', 'Sim', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.equal(r.moduloEntrada, 2);
    assert.deepEqual(r.feitos, [{ modulo_ordem: 2, data_conclusao: '2026-06-30' }]);
  });

  it('célula de nome vazia é ignorada, e linha vazia não inventa nada', () => {
    const r = derivarRodizio([mod(null, 'SIM', '01/01/2026'), mod('  ', null, null)],
      CHEF, SNAPSHOT);
    assert.deepEqual(r, { moduloEntrada: null, feitos: [], emCurso: null, ocorrencias: [] });
  });

  it('o mesmo módulo iniciado duas vezes fica com a primeira', () => {
    const r = derivarRodizio([
      mod('Massas e Molhos', 'SIM', '30/06/2026'),
      mod('Massas e Molhos', 'SIM', '31/07/2026'),
      mod('Carnes e Aves', 'SIM', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(r.feitos, [{ modulo_ordem: 2, data_conclusao: '2026-06-30' }]);
    assert.deepEqual(r.ocorrencias.map((o) => o.codigo), ['MODULO_REPETIDO']);
  });
});

describe('catalogoDoCurso', () => {
  it('dois módulos com o mesmo nome em posições diferentes ficam FORA do mapa', () => {
    // Escolher um deles daria ao aluno um módulo que talvez não seja o dele.
    const c = catalogoDoCurso([
      { ordem: 1, nome: 'Introdução' },
      { ordem: 2, nome: 'Prática' },
      { ordem: 3, nome: 'introducao' },
    ]);
    assert.equal(c.porNome.has('introducao'), false);
    assert.equal(c.porNome.get('pratica'), 2);
    const r = derivarRodizio([mod('Introdução', 'SIM', '01/10/2026')], c, SNAPSHOT);
    assert.deepEqual(r.ocorrencias.map((o) => o.codigo), ['MODULO_AMBIGUO']);
  });
});

describe('linhasDoRodizio', () => {
  const quem = { aluno: '4433', turma: 'Chef 2026', metodo: 'MODULAR', curso: 'Chef Profissional' };

  it('monta a alocação e os módulos feitos no formato do contrato', () => {
    const derivado = derivarRodizio([
      mod('Confeitaria', 'SIM', '31/07/2026'),
      mod('Cozinha Internacional', 'SIM', '20/11/2026'),
    ], CHEF, SNAPSHOT);
    assert.deepEqual(linhasDoRodizio({ ...quem, dataEntrada: '2026-06-15' }, derivado), {
      turma_modular_aluno: {
        turma: 'Chef 2026', aluno: '4433', data_entrada: '2026-06-15', modulo_entrada: 5,
      },
      aluno_modulo: [{
        aluno: '4433', metodo: 'MODULAR', curso: 'Chef Profissional',
        modulo_ordem: 5, data_conclusao: '2026-07-31',
      }],
    });
  });

  it('entrada não resolvida fica AUSENTE do arquivo — no importador, ausente é '
    + '"não sei" e não apaga o que já está gravado', () => {
    const derivado = derivarRodizio([mod('Módulo que não existe', 'SIM', null)],
      CHEF, SNAPSHOT);
    const { turma_modular_aluno: alocacao } = linhasDoRodizio(quem, derivado);
    assert.equal('modulo_entrada' in alocacao, false);
    assert.equal('data_entrada' in alocacao, false);
  });
});

describe('o inventário de entidades', () => {
  it('aluno_modulo está na ordem do contrato, logo depois da alocação Modular', () => {
    const i = L.ORDEM_ENTIDADES.indexOf('turma_modular_aluno');
    assert.equal(L.ORDEM_ENTIDADES[i + 1], 'aluno_modulo');
    assert.equal(L.ORDEM_ENTIDADES.length, 19);
  });

  it('e é declarada como LACUNA das abas de turma — ausente, não vazia', () => {
    const lacuna = L.ABAS_NAO_MAPEADAS.find((a) => a.entidades.includes('turma_modular_aluno'));
    assert.ok(lacuna.entidades.includes('aluno_modulo'));
  });
});
