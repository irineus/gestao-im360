// Um escritor de `.xlsx` mínimo, só para a suíte.
//
// Existe por uma razão só: sem ele, a camada que abre arquivo (`xlsx.mjs`) ficaria
// fora do CI — a planilha real não está no repositório, e um leitor não exercitado
// é o pedaço do sistema onde o defeito espera o dia da carga para aparecer.
//
// Escreve ZIP com deflate e com stored, porque um `.xlsx` real mistura os dois.
// Não escreve ZIP64 nem criptografia: o leitor também não os aceita, e é melhor que
// os dois lados tenham o MESMO limite declarado do que um limite que só aparece na
// planilha de alguém.

import { deflateRawSync } from 'node:zlib';

const TABELA_CRC = (() => {
  const tabela = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    tabela[n] = c;
  }
  return tabela;
})();

function crc32(buffer) {
  let c = -1;
  for (const byte of buffer) c = TABELA_CRC[(c ^ byte) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

export function zip(arquivos) {
  const locais = [];
  const centrais = [];
  let deslocamento = 0;
  arquivos.forEach(({ nome, texto, comprimir = true }) => {
    const dados = Buffer.from(texto, 'utf8');
    const corpo = comprimir ? deflateRawSync(dados) : dados;
    const metodo = comprimir ? 8 : 0;
    const nomeBytes = Buffer.from(nome, 'utf8');
    const crc = crc32(dados);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(metodo, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(corpo.length, 18);
    local.writeUInt32LE(dados.length, 22);
    local.writeUInt16LE(nomeBytes.length, 26);
    locais.push(local, nomeBytes, corpo);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(metodo, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(corpo.length, 20);
    central.writeUInt32LE(dados.length, 24);
    central.writeUInt16LE(nomeBytes.length, 28);
    central.writeUInt32LE(deslocamento, 42);
    centrais.push(central, nomeBytes);

    deslocamento += 30 + nomeBytes.length + corpo.length;
  });

  const diretorio = Buffer.concat(centrais);
  const fim = Buffer.alloc(22);
  fim.writeUInt32LE(0x06054b50, 0);
  fim.writeUInt16LE(arquivos.length, 8);
  fim.writeUInt16LE(arquivos.length, 10);
  fim.writeUInt32LE(diretorio.length, 12);
  fim.writeUInt32LE(deslocamento, 16);
  return Buffer.concat([...locais, diretorio, fim]);
}

function escapar(texto) {
  return String(texto)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function letra(indice) {
  let saida = '';
  let n = indice + 1;
  while (n > 0) {
    const resto = (n - 1) % 26;
    saida = String.fromCharCode(65 + resto) + saida;
    n = Math.floor((n - resto) / 26);
  }
  return saida;
}

function aba(linhas) {
  const partes = ['<?xml version="1.0"?><worksheet><sheetData>'];
  linhas.forEach((linha, i) => {
    const celulas = [];
    linha.forEach((valor, coluna) => {
      if (valor === null || valor === undefined || valor === '') return;
      const referencia = `${letra(coluna)}${i + 1}`;
      celulas.push(typeof valor === 'number'
        ? `<c r="${referencia}"><v>${valor}</v></c>`
        : `<c r="${referencia}" t="inlineStr"><is><t>${escapar(valor)}</t></is></c>`);
    });
    // Linha sem célula nenhuma é OMITIDA, como o Excel faz — é assim que o teste
    // ponta a ponta prova que o leitor repõe o buraco na posição certa.
    if (celulas.length) partes.push(`<row r="${i + 1}">${celulas.join('')}</row>`);
  });
  partes.push('</sheetData></worksheet>');
  return partes.join('');
}

/** `{ nomeDaAba: [[valor, ...], ...] }` → um `.xlsx` de verdade, em memória. */
export function comoXlsx(dados) {
  const abas = Object.entries(dados);
  return zip([
    {
      nome: 'xl/workbook.xml',
      texto: '<?xml version="1.0"?><workbook><sheets>'
        + abas.map(([nome], i) => `<sheet name="${escapar(nome)}" sheetId="${i + 1}" `
          + `r:id="rId${i + 1}"/>`).join('')
        + '</sheets></workbook>',
    },
    {
      nome: 'xl/_rels/workbook.xml.rels',
      texto: '<?xml version="1.0"?><Relationships>'
        + abas.map((_, i) => `<Relationship Id="rId${i + 1}" `
          + `Target="worksheets/sheet${i + 1}.xml"/>`).join('')
        + '</Relationships>',
      comprimir: false,
    },
    ...abas.map(([, linhas], i) => ({
      nome: `xl/worksheets/sheet${i + 1}.xml`, texto: aba(linhas),
    })),
  ]);
}
