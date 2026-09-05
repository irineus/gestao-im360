// A camada que abre arquivo, exercitada de verdade.
//
// Este é o teste que o desenho em Python não conseguia ter: com `openpyxl`, a
// leitura só se exercitaria instalando a dependência no CI e arrumando um `.xlsx`
// de mentira — e a planilha real não está no repositório. Em Node, escrever um
// `.xlsx` mínimo é ~80 linhas de ZIP, então o leitor é medido contra um arquivo
// construído aqui, com deflate e com stored, com data, texto compartilhado, texto
// embutido, booleano e buracos de linha e de coluna.

import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { abrirBuffer } from '../xlsx.mjs';
import { zip } from './construir-xlsx.mjs';

// --- Um .xlsx mínimo --------------------------------------------------------

const COMPARTILHADAS = ['Windows 11', 'Beatriz & Cia <ME>'];

// `s="1"` é o estilo de data: `cellXfs` índice 1 aponta para `numFmtId="14"`, que é
// o `dd/mm/yyyy` embutido do OOXML.
const ABA = `<?xml version="1.0"?>
<worksheet><sheetData>
  <row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="inlineStr"><is><t>Excel 365</t></is></c></row>
  <row r="3"><c r="A3"><v>44197</v></c><c r="B3" s="1"><v>44197</v></c>
             <c r="C3" t="b"><v>1</v></c><c r="D3" t="s"><v>1</v></c></row>
  <row r="4"><c r="B4" s="2"><v>7.5</v></c><c r="D4" t="str"><v>SIM</v></c></row>
</sheetData></worksheet>`;

function construir({ date1904 = false } = {}) {
  return zip([
    {
      nome: 'xl/workbook.xml',
      texto: `<?xml version="1.0"?><workbook>`
        + (date1904 ? '<workbookPr date1904="1"/>' : '')
        + '<sheets><sheet name="Ger. Apost" sheetId="1" r:id="rId1"/></sheets></workbook>',
    },
    {
      nome: 'xl/_rels/workbook.xml.rels',
      texto: '<?xml version="1.0"?><Relationships>'
        + '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      // Sem compressão de propósito: um `.xlsx` real mistura os dois métodos, e o
      // leitor precisa aceitar `stored` além de `deflate`.
      comprimir: false,
    },
    {
      nome: 'xl/sharedStrings.xml',
      texto: `<?xml version="1.0"?><sst>${COMPARTILHADAS
        .map((s) => `<si><t>${s.replace(/&/g, '&amp;').replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')}</t></si>`).join('')}</sst>`,
    },
    {
      nome: 'xl/styles.xml',
      texto: '<?xml version="1.0"?><styleSheet>'
        + '<numFmts><numFmt numFmtId="165" formatCode="#,##0.00 &quot;dias&quot;"/></numFmts>'
        + '<cellXfs count="3"><xf numFmtId="0"/><xf numFmtId="14"/><xf numFmtId="165"/>'
        + '</cellXfs></styleSheet>',
    },
    { nome: 'xl/worksheets/sheet1.xml', texto: ABA },
  ]);
}

// --- O que o leitor precisa entregar ---------------------------------------

describe('leitor de .xlsx', () => {
  const planilha = abrirBuffer(construir());
  const linhas = planilha.linhas('Ger. Apost');

  it('devolve as abas pelo nome que a pessoa vê, com acento e ponto', () => {
    assert.deepEqual(planilha.abas(), ['Ger. Apost']);
  });

  it('texto compartilhado, texto embutido e entidade XML voltam legíveis', () => {
    assert.equal(linhas[0][0], 'Windows 11');
    assert.equal(linhas[0][2], 'Excel 365');
    // `&amp;` e `&lt;` no meio de um nome não são exóticos numa planilha digitada.
    assert.equal(linhas[2][3], 'Beatriz & Cia <ME>');
  });

  it('o mesmo número é NÚMERO sem estilo de data e DATA com ele', () => {
    // 44197 é o serial de 2021-01-01. O valor está pinado à mão de propósito: é o
    // que prova a época 1899-12-30 (o "30" absorve o bug do ano bissexto de 1900).
    // Recalculá-lo com a fórmula do próprio leitor mediria o leitor contra si mesmo.
    assert.equal(linhas[2][0], 44197);
    assert.ok(linhas[2][1] instanceof Date);
    assert.equal(linhas[2][1].toISOString().slice(0, 10), '2021-01-01');
  });

  it('formato customizado que não é data não vira data', () => {
    // ⚠️ O literal é `"dias"` e não `"kg"` de propósito, e a diferença foi MEDIDA:
    // com `"kg"` a contraprova PASSOU VERDE — tirar ou não o que está entre aspas
    // dá o mesmo resultado quando o literal não tem d, m nem y, e o teste não
    // media nada. Com `"dias"`, uma varredura que não limpe as aspas vê o `d`,
    // decide que é data e transforma 7,5 em 1900-01-06.
    assert.equal(linhas[3][1], 7.5);
  });

  it('booleano e string de fórmula chegam como valor, não como marcação', () => {
    assert.equal(linhas[2][2], true);
    assert.equal(linhas[3][3], 'SIM');
  });

  it('linha e coluna vazias mantêm a POSIÇÃO das que vêm depois', () => {
    // O XML omite a linha 2 inteira e a coluna B da linha 1. O mapa de colunas do
    // `layout.mjs` é posicional: um deslocamento de uma linha jogaria todo o bloco
    // de horário para o aluno de baixo, e nada acusaria.
    assert.equal(linhas.length, 4);
    assert.deepEqual(linhas[1], []);
    assert.equal(linhas[0][1], null);
  });

  it('planilha no sistema de datas 1904 é RECUSADA, não convertida errado', () => {
    // Salva no Excel para Mac antigo, toda data sairia quatro anos adiantada — e a
    // conferência do card 9.4 bateria os totais e não as datas.
    assert.throws(() => abrirBuffer(construir({ date1904: true })), /1904/);
  });

  it('arquivo que não é ZIP morre dizendo isso', () => {
    assert.throws(() => abrirBuffer(Buffer.from('isto aqui é um CSV;de verdade\n')),
      /não parece um \.xlsx/);
  });
});
