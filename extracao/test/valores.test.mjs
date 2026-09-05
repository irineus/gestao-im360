import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import * as v from '../valores.mjs';

describe('codigo', () => {
  it('as quatro grafias do mesmo código viram o mesmo texto', () => {
    // A chave natural de `material` é metodo + codigo. Duas grafias do mesmo código
    // viram dois materiais, e o V7 do importador acusaria REFERENCIA_AUSENTE numa
    // linha que existe.
    for (const bruto of [1, 1.0, '01', ' 1 ']) {
      assert.equal(v.codigo(bruto), '1', String(bruto));
    }
  });

  it('código não numérico sobrevive inteiro', () => {
    assert.equal(v.codigo(' A-12 '), 'A-12');
  });

  it('célula vazia é null e nunca string vazia', () => {
    // `aluno_codigo_sgf_ck` recusa '' de propósito: dois alunos com '' colidiriam
    // no índice parcial e o erro falaria de chave duplicada.
    assert.equal(v.codigo(null), null);
    assert.equal(v.codigo('   '), null);
    assert.equal(v.texto(''), null);
  });
});

describe('hora', () => {
  it('as grafias do cabeçalho viram HH:MM', () => {
    const casos = {
      '8H': '08:00', '8h': '08:00', '13H30': '13:30', '13:30': '13:30', '20H': '20:00', ' 8 ': '08:00',
    };
    for (const [bruto, esperado] of Object.entries(casos)) {
      assert.equal(v.hora(bruto), esperado, bruto);
    }
  });

  it('cabeçalho sem horário não vira hora qualquer', () => {
    for (const bruto of ['CLAUDIR', '25H', null, '8H99', '']) {
      assert.equal(v.hora(bruto), null, JSON.stringify(bruto));
    }
  });
});

describe('data', () => {
  it('aceita o Date do leitor e as duas grafias digitadas', () => {
    assert.equal(v.data(new Date(Date.UTC(2026, 2, 1))), '2026-03-01');
    assert.equal(v.data('01/03/2026'), '2026-03-01');
    assert.equal(v.data('2026-03-01'), '2026-03-01');
  });

  it('texto que não é data devolve null, e data impossível também', () => {
    assert.equal(v.data('a combinar'), null);
    assert.equal(v.data('31/02/2026'), null);
  });
});

describe('dataNoNome', () => {
  it('o (dd/mm) sai do nome e vira data do ano do snapshot', () => {
    assert.deepEqual(v.dataNoNome('Afonso Henrique (12/09)', '2026-08-29'),
      ['Afonso Henrique', '2026-09-12']);
  });

  it('data muito à frente do snapshot é do ano anterior', () => {
    // Bloco lançado em dezembro, planilha conferida em janeiro: 20/12 do ano do
    // snapshot cairia onze meses à frente — um início previsto que ninguém escreveu.
    assert.deepEqual(v.dataNoNome('Fulana (20/12)', '2026-01-15'),
      ['Fulana', '2025-12-20']);
  });

  it('nome sem data volta inteiro', () => {
    assert.deepEqual(v.dataNoNome('Fulana de Tal', '2026-08-29'), ['Fulana de Tal', null]);
  });
});

describe('norm e sim', () => {
  it('acento, caixa e espaço duplo não separam o mesmo nome', () => {
    assert.equal(v.norm('Massagem  Terapêutica'), v.norm('massagem terapeutica'));
  });

  it('só SIM é verdadeiro', () => {
    assert.equal(v.sim('SIM'), true);
    assert.equal(v.sim('sim'), true);
    assert.equal(v.sim('NÃO'), false);
    assert.equal(v.sim(null), false);
  });
});
