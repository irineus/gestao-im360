// Conversões de célula da planilha para os tipos do contrato
// (`docs/importacao.md` §3).
//
// Nenhuma destas funções decide regra de negócio: elas convertem, e quando não
// conseguem devolvem `null`. Quem transforma `null` em ocorrência é a transformação.

/**
 * Forma canônica para COMPARAR nomes: sem acento, sem caixa, sem espaço duplo.
 *
 * Usada para achar grafia duplicada (Terapêutica × Terapeutica) e para casar o
 * nome do aluno na turma com o do cadastro quando os códigos divergem. Nunca é o
 * valor gravado no arquivo — o arquivo leva a grafia da planilha.
 */
export function norm(valor) {
  if (valor === null || valor === undefined) return '';
  return String(valor)
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .replace(/\s+/g, ' ')
    .toLowerCase();
}

/**
 * Texto aparado, ou `null` para célula vazia.
 *
 * Célula vazia vira `null` e nunca `''`: `aluno_codigo_sgf_ck` recusa string vazia
 * de propósito, e o comentário da coluna diz por quê — dois alunos com `''`
 * colidiriam no índice parcial e o erro falaria de chave duplicada quando o que
 * houve foi célula em branco.
 */
export function texto(valor) {
  if (valor === null || valor === undefined) return null;
  if (valor instanceof Date) return valor.toISOString().slice(0, 10);
  const s = String(valor).trim();
  return s === '' ? null : s;
}

/**
 * Código numérico da planilha como texto canônico, sem zero à esquerda.
 *
 * `1`, `1.0`, `'01'` e `' 1 '` são o mesmo código na planilha e precisam ser o
 * mesmo texto no arquivo: a chave natural de `material` é `metodo` + `codigo`, e o
 * catálogo, a trilha e os movimentos referenciam o mesmo material por caminhos
 * diferentes. Duas grafias do mesmo código viram dois materiais, e o V7 do
 * importador acusaria `REFERENCIA_AUSENTE` numa linha que existe.
 */
export function codigo(valor) {
  const s = texto(valor);
  if (s === null) return null;
  if (/^[+-]?\d+(\.\d+)?$/.test(s)) {
    const n = Number(s);
    if (Number.isInteger(n)) return String(n);
  }
  return s;
}

export function inteiro(valor) {
  const s = texto(valor);
  if (s === null) return null;
  const n = Number(s);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/**
 * `AAAA-MM-DD`, ou `null` quando a célula não é data.
 *
 * Aceita o `Date` que o leitor devolve para célula formatada como data e as duas
 * grafias que aparecem digitadas na planilha.
 */
export function data(valor) {
  if (valor === null || valor === undefined) return null;
  if (valor instanceof Date) {
    return Number.isNaN(valor.getTime()) ? null : valor.toISOString().slice(0, 10);
  }
  const s = typeof valor === 'string' ? valor.trim() : texto(valor);
  if (s === null || s === '') return null;
  let m = /^(\d{4})-(\d{2})-(\d{2})/.exec(s);
  if (m) return montar(+m[1], +m[2], +m[3]);
  m = /^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/.exec(s);
  if (m) {
    const ano = m[3].length === 2 ? 2000 + Number(m[3]) : Number(m[3]);
    return montar(ano, +m[2], +m[1]);
  }
  return null;
}

function montar(ano, mes, dia) {
  if (mes < 1 || mes > 12 || dia < 1 || dia > 31) return null;
  const d = new Date(Date.UTC(ano, mes - 1, dia));
  if (d.getUTCMonth() !== mes - 1 || d.getUTCDate() !== dia) return null;
  return d.toISOString().slice(0, 10);
}

/**
 * `8H`, `13H30`, `13:30`, `8` → `HH:MM`. Fora disso, `null`.
 *
 * O contrato exige `HH:MM` e o cabeçalho do bloco traz o horário como a secretaria
 * o digita. `8H` e `08:00` são o MESMO bloco, e a chave natural de `bloco_horario`
 * é sala + dia + hora: sem canonizar, o mesmo bloco entraria duas vezes.
 */
export function hora(valor) {
  const s = texto(valor);
  if (s === null) return null;
  const m = /^(\d{1,2})\s*(?:[hH:]\s*(\d{2})?)?$/.exec(s);
  if (!m) return null;
  const h = Number(m[1]);
  const minuto = m[2] === undefined ? 0 : Number(m[2]);
  if (h > 23 || minuto > 59) return null;
  return `${String(h).padStart(2, '0')}:${String(minuto).padStart(2, '0')}`;
}

const DATA_NO_NOME = /\((\d{1,2})\s*\/\s*(\d{1,2})\)/;

/**
 * `"Fulano (12/09)"` → `["Fulano", "2026-09-12"]`.
 *
 * O "(dd/mm)" no nome é o início previsto de quem foi lançado como NOVO (plano §8).
 * O ano não está escrito: vale o ano do SNAPSHOT, e se isso jogasse a data mais de
 * seis meses à frente dele, vale o ano anterior — é o caso do bloco lançado em
 * dezembro e conferido em janeiro. Comparar com HOJE em vez do snapshot faria a
 * mesma planilha produzir datas diferentes conforme o dia da extração, que é a
 * lição do V12 do importador.
 */
export function dataNoNome(nome, snapshot) {
  const s = texto(nome);
  if (s === null) return [null, null];
  const m = DATA_NO_NOME.exec(s);
  const limpo = texto(s.replace(DATA_NO_NOME, ''));
  if (!m) return [limpo, null];
  const dia = Number(m[1]);
  const mes = Number(m[2]);
  const base = Date.parse(`${snapshot}T00:00:00Z`);
  const anoBase = Number(snapshot.slice(0, 4));
  for (const ano of [anoBase, anoBase - 1]) {
    const iso = montar(ano, mes, dia);
    if (iso === null) return [limpo, null];
    const dias = (Date.parse(`${iso}T00:00:00Z`) - base) / 86400000;
    if (dias <= 183) return [limpo, iso];
  }
  return [limpo, null];
}

/** A flag `SIM`/`NÃO` da planilha. Só `SIM` é verdadeiro; vazio é falso. */
export function sim(valor) {
  return norm(valor) === 'sim';
}
