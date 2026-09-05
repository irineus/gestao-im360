// Leitor de `.xlsx` sem dependência nenhuma — a única camada que abre arquivo.
//
// Por que não uma biblioteca: nenhuma ferramenta deste repositório tem dependência
// de terceiro (`worker-vigia`, `portao-migracoes`, o guarda de destrutivos e a
// lógica das Edge Functions rodam com `node --test` puro, e o `ci-cd.md` §2 diz por
// quê). Um `.xlsx` é um ZIP de XML, e o Node já traz o `inflateRaw` — o que falta
// são ~120 linhas de diretório central e ~40 de varredura de células.
//
// Por que isso é POUCO código e não pouca ambição: o que este leitor precisa
// devolver é exatamente o que o `openpyxl` devolvia com `values_only=True` — a
// matriz de valores de cada aba. Fórmula não interessa (as colunas de nome de livro
// são lookup e o que vale é o valor calculado, que o Excel grava em `<v>`), e é a
// mesma escolha do `data_only=True` do protótipo.
//
// ⚠️ **Não decidir nada aqui.** Toda regra — descarte, correção, chave, severidade
// — mora em `transformacao.mjs`. Uma conversão escondida neste módulo seria
// invisível para a suíte de transformação, que roda sem tocar em arquivo.
//
// Limites assumidos, os dois medidos contra o formato e não contra a planilha:
// não há suporte a ZIP64 (arquivo de 4 GB ou 65 mil entradas, o que um snapshot da
// escola não alcança) e o sistema de datas 1904 do Excel para Mac não é tratado —
// se um dia a planilha vier de lá, TODA data sai quatro anos adiantada, e é por
// isso que o leitor RECUSA o arquivo em vez de converter errado.

import { inflateRawSync } from 'node:zlib';
import { readFileSync } from 'node:fs';

// --- ZIP ---------------------------------------------------------------------

const FIM_DIRETORIO = 0x06054b50;
const ENTRADA_DIRETORIO = 0x02014b50;
const CABECALHO_LOCAL = 0x04034b50;

function lerZip(buffer) {
  let fim = -1;
  // O comentário final do ZIP tem até 64 KB; procura-se a assinatura de trás para
  // frente, que é o que o próprio formato manda fazer.
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 65535); i -= 1) {
    if (buffer.readUInt32LE(i) === FIM_DIRETORIO) { fim = i; break; }
  }
  if (fim < 0) throw new Error('não parece um .xlsx: fim do diretório do ZIP não encontrado.');

  const quantas = buffer.readUInt16LE(fim + 10);
  let posicao = buffer.readUInt32LE(fim + 16);
  if (posicao === 0xffffffff || quantas === 0xffff) {
    throw new Error('ZIP64 não é suportado por este leitor (arquivo grande demais).');
  }

  const entradas = new Map();
  for (let n = 0; n < quantas; n += 1) {
    if (buffer.readUInt32LE(posicao) !== ENTRADA_DIRETORIO) {
      throw new Error('diretório do ZIP corrompido.');
    }
    const metodo = buffer.readUInt16LE(posicao + 10);
    const comprimido = buffer.readUInt32LE(posicao + 20);
    const tamanhoNome = buffer.readUInt16LE(posicao + 28);
    const tamanhoExtra = buffer.readUInt16LE(posicao + 30);
    const tamanhoComentario = buffer.readUInt16LE(posicao + 32);
    const local = buffer.readUInt32LE(posicao + 42);
    const nome = buffer.toString('utf8', posicao + 46, posicao + 46 + tamanhoNome);
    entradas.set(nome, { metodo, comprimido, local });
    posicao += 46 + tamanhoNome + tamanhoExtra + tamanhoComentario;
  }

  return (nome) => {
    const entrada = entradas.get(nome);
    if (!entrada) return null;
    if (buffer.readUInt32LE(entrada.local) !== CABECALHO_LOCAL) {
      throw new Error(`cabeçalho local corrompido em ${nome}.`);
    }
    // O cabeçalho local repete nome e extra com tamanhos PRÓPRIOS, que podem
    // diferir dos do diretório central. Usar os do diretório aqui é o erro clássico
    // de leitor de ZIP escrito às pressas: funciona até o primeiro arquivo com
    // campo extra de alinhamento.
    const inicio = entrada.local + 30
      + buffer.readUInt16LE(entrada.local + 26)
      + buffer.readUInt16LE(entrada.local + 28);
    const bruto = buffer.subarray(inicio, inicio + entrada.comprimido);
    if (entrada.metodo === 0) return bruto;
    if (entrada.metodo === 8) return inflateRawSync(bruto);
    throw new Error(`método de compressão ${entrada.metodo} não suportado em ${nome}.`);
  };
}

// --- XML ----------------------------------------------------------------------

const ENTIDADES = {
  amp: '&', lt: '<', gt: '>', quot: '"', apos: "'",
};

function desescapar(texto) {
  return texto.replace(/&(#x?[0-9a-fA-F]+|[a-z]+);/g, (inteiro, corpo) => {
    if (corpo[0] === '#') {
      const ponto = corpo[1] === 'x' || corpo[1] === 'X'
        ? parseInt(corpo.slice(2), 16)
        : parseInt(corpo.slice(1), 10);
      return Number.isFinite(ponto) ? String.fromCodePoint(ponto) : inteiro;
    }
    return ENTIDADES[corpo] ?? inteiro;
  });
}

function atributo(tag, nome) {
  // `(?:^|\s)` não é zelo: sem ele, procurar `r=` acharia o `r` de `sr=` ou de
  // qualquer atributo terminado em `r`, e a coluna da célula sairia de outro campo.
  const m = new RegExp(`(?:^|\\s)${nome}="([^"]*)"`).exec(tag);
  return m ? desescapar(m[1]) : null;
}

// --- Datas --------------------------------------------------------------------

// Formatos de data embutidos no OOXML (§18.8.30 da norma). 14–22 são data e hora;
// 45–47 são duração. Fora deles, só o `formatCode` responde.
const FORMATOS_DATA = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47]);

function pareceData(formatCode) {
  // Tira o que está entre aspas e os códigos de cor/condição: `"h"` dentro de um
  // literal não faz de um formato monetário um formato de hora.
  const limpo = formatCode.replace(/"[^"]*"/g, '').replace(/\[[^\]]*\]/g, '');
  return /[dmy]/i.test(limpo);
}

// O Excel conta dias desde 1899-12-30 (o "30" absorve o bug do ano bissexto de
// 1900, que o formato preserva de propósito para compatibilidade com o Lotus 1-2-3).
const EPOCA = Date.UTC(1899, 11, 30);

function serialParaData(numero) {
  const dias = Math.floor(numero);
  const fracao = numero - dias;
  const ms = EPOCA + dias * 86400000 + Math.round(fracao * 86400000);
  return new Date(ms);
}

// --- Planilha -----------------------------------------------------------------

function colunaParaIndice(referencia) {
  let indice = 0;
  for (const letra of referencia) {
    const codigo = letra.charCodeAt(0);
    if (codigo < 65 || codigo > 90) break;
    indice = indice * 26 + (codigo - 64);
  }
  return indice - 1;
}

function textosCompartilhados(ler) {
  const bruto = ler('xl/sharedStrings.xml');
  if (!bruto) return [];
  const xml = bruto.toString('utf8');
  const textos = [];
  for (const si of xml.split('<si>').slice(1)) {
    const corpo = si.split('</si>')[0];
    let junto = '';
    // Uma `<si>` com formatação vem partida em vários `<r><t>`: concatenar é o que
    // devolve o texto que a pessoa vê na célula.
    for (const m of corpo.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)) {
      junto += desescapar(m[1]);
    }
    textos.push(junto);
  }
  return textos;
}

function estilosDeData(ler) {
  const bruto = ler('xl/styles.xml');
  if (!bruto) return new Set();
  const xml = bruto.toString('utf8');
  const customizados = new Map();
  for (const m of xml.matchAll(/<numFmt\s[^>]*\/>/g)) {
    const id = Number(atributo(m[0], 'numFmtId'));
    const codigo = atributo(m[0], 'formatCode') ?? '';
    if (Number.isFinite(id)) customizados.set(id, codigo);
  }
  const secao = /<cellXfs[^>]*>([\s\S]*?)<\/cellXfs>/.exec(xml);
  const eData = new Set();
  if (!secao) return eData;
  let indice = 0;
  for (const m of secao[1].matchAll(/<xf\s[^>]*?(?:\/>|>)/g)) {
    const id = Number(atributo(m[0], 'numFmtId') ?? '0');
    if (FORMATOS_DATA.has(id) || (customizados.has(id) && pareceData(customizados.get(id)))) {
      eData.add(indice);
    }
    indice += 1;
  }
  return eData;
}

function nomesDasAbas(ler) {
  const workbook = ler('xl/workbook.xml').toString('utf8');
  if (/<workbookPr[^>]*date1904="(1|true)"/.test(workbook)) {
    throw new Error(
      'a planilha usa o sistema de datas 1904 (Excel para Mac): toda data sairia '
      + 'quatro anos adiantada. Reabrir e salvar no sistema 1900 antes de extrair.',
    );
  }
  const rels = ler('xl/_rels/workbook.xml.rels').toString('utf8');
  const alvos = new Map();
  for (const m of rels.matchAll(/<Relationship\s[^>]*\/>/g)) {
    alvos.set(atributo(m[0], 'Id'), atributo(m[0], 'Target'));
  }
  const abas = [];
  for (const m of workbook.matchAll(/<sheet\s[^>]*\/>/g)) {
    const alvo = alvos.get(atributo(m[0], 'r:id'));
    if (!alvo) continue;
    const caminho = alvo.startsWith('/')
      ? alvo.slice(1)
      : `xl/${alvo.replace(/^\.\//, '')}`;
    abas.push({ nome: atributo(m[0], 'name'), caminho });
  }
  return abas;
}

function lerAba(xml, textos, estilos) {
  const linhas = [];
  for (const linhaXml of xml.split('<row').slice(1)) {
    const numero = Number(atributo(linhaXml.slice(0, linhaXml.indexOf('>')), 'r') ?? 0);
    const celulas = [];
    for (const m of linhaXml.matchAll(/<c\s([^>]*?)(\/>|>([\s\S]*?)<\/c>)/g)) {
      const atributos = m[1];
      const corpo = m[3] ?? '';
      const indice = colunaParaIndice(atributo(atributos, 'r') ?? '');
      const coluna = indice >= 0 ? indice : celulas.length;
      const tipo = atributo(atributos, 't');
      let valor = null;
      if (tipo === 'inlineStr') {
        let junto = '';
        for (const t of corpo.matchAll(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g)) junto += desescapar(t[1]);
        valor = junto;
      } else {
        const bruto = /<v>([\s\S]*?)<\/v>/.exec(corpo);
        if (bruto) {
          const conteudo = desescapar(bruto[1]);
          if (tipo === 's') valor = textos[Number(conteudo)] ?? null;
          else if (tipo === 'b') valor = conteudo === '1';
          else if (tipo === 'str' || tipo === 'e') valor = conteudo;
          else {
            const numero2 = Number(conteudo);
            const estilo = Number(atributo(atributos, 's') ?? '0');
            valor = Number.isFinite(numero2) && estilos.has(estilo)
              ? serialParaData(numero2)
              : (Number.isFinite(numero2) ? numero2 : conteudo);
          }
        }
      }
      while (celulas.length < coluna) celulas.push(null);
      celulas[coluna] = valor === '' ? null : valor;
    }
    // Linha vazia é omitida do XML; a matriz precisa mantê-la, porque o mapa de
    // colunas do `layout.mjs` é POSICIONAL e um deslocamento de uma linha jogaria
    // todo o bloco de horário para o aluno de baixo.
    while (numero > 0 && linhas.length < numero - 1) linhas.push([]);
    linhas.push(celulas);
  }
  return linhas;
}

class PlanilhaXlsx {
  constructor(buffer) {
    const ler = lerZip(buffer);
    const textos = textosCompartilhados(ler);
    const estilos = estilosDeData(ler);
    this._abas = new Map();
    for (const { nome, caminho } of nomesDasAbas(ler)) {
      const bruto = ler(caminho);
      this._abas.set(nome, bruto ? lerAba(bruto.toString('utf8'), textos, estilos) : []);
    }
  }

  abas() { return [...this._abas.keys()]; }

  linhas(aba) { return this._abas.get(aba) ?? []; }
}

export function abrirXlsx(caminho) {
  return new PlanilhaXlsx(readFileSync(caminho));
}

export function abrirBuffer(buffer) {
  return new PlanilhaXlsx(buffer);
}

/**
 * A mesma interface a partir de um objeto aba → matriz de valores.
 *
 * É o que a suíte de transformação usa: a planilha real (`Gestão Interativo.xlsx`)
 * **não está neste repositório** — é upload do projeto —, então um teste que
 * dependesse dela nunca rodaria no CI.
 */
export class PlanilhaEmMemoria {
  constructor(dados) {
    this._dados = dados;
  }

  abas() { return Object.keys(this._dados); }

  linhas(aba) { return this._dados[aba] ?? []; }
}
