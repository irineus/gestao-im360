// Uma planilha mínima em memória, com uma armadilha em cada célula.
//
// A planilha real (`Gestão Interativo.xlsx`) **não está neste repositório** — é
// upload do projeto —, então um teste que dependesse dela nunca rodaria no CI. Esta
// fixture é o equivalente da escola-fixture do banco (card 3.4.5): pequena, mas com
// um exemplar de cada caso que o extrator precisa separar.
//
// O que está plantado aqui, de propósito:
//
// - material MSE e "FIM" no catálogo (as duas limpezas do plano §8);
// - duas saídas IDÊNTICAS no mesmo dia (a colisão que a chave do movimento resolve);
// - uma saída sem aluno (vira AJUSTE);
// - uma saída sem "Entregue = SIM" na trilha, e uma entrega de Inglês sem saída;
// - "MACRO", que é registro técnico e não aluno;
// - status "Faltante", que não existe no sistema;
// - previsão em 2023 para quem está ATIVO;
// - "R" no tipo de presença, que se lê REP;
// - código na turma divergente do cadastro, resolvido por nome único;
// - um código na turma que não existe em cadastro nenhum;
// - um aluno de Inglês sentado num bloco de Interativo;
// - "(12/09)" no nome de quem entrou como NOVO;
// - o mesmo aluno em dois blocos (aceleração);
// - "Massagem Terapêutica" e "Massagem Terapeutica", que são o mesmo curso.

import { PlanilhaEmMemoria } from '../xlsx.mjs';

export const SNAPSHOT = '2026-08-29';

function linha(tamanho, valores) {
  const saida = new Array(tamanho).fill(null);
  for (const [indice, valor] of Object.entries(valores)) saida[Number(indice)] = valor;
  return saida;
}

const vazia = (tamanho) => new Array(tamanho).fill(null);

function catalogoEMovimento({ codigo, nome, saida, entrada }) {
  const valores = {};
  if (codigo !== undefined) { valores[2] = codigo; valores[3] = nome; }
  if (saida) { [valores[8], valores[9], valores[11], valores[12]] = saida; }
  if (entrada) { [valores[15], valores[16], valores[18]] = entrada; }
  return linha(20, valores);
}

function gerencia(codigo, nome, prev, status, trilha = []) {
  const valores = {
    1: codigo, 2: nome, 3: prev, 4: status,
  };
  trilha.forEach(([material, entregue], posicao) => {
    valores[9 + posicao * 3] = material;
    valores[11 + posicao * 3] = entregue;
  });
  return linha(60, valores);
}

function ingles(codigo, nome, prev, status, trilha = []) {
  const valores = {
    1: codigo, 2: nome, 3: prev, 4: status,
  };
  trilha.forEach(([material, entregue], posicao) => {
    const base = [10, 13, 16, 19][posicao];
    valores[base] = material;
    valores[base + 2] = entregue;
  });
  return linha(22, valores);
}

const modular = (codigo, nome, prev, curso, status) => linha(12, {
  1: codigo, 2: nome, 3: prev, 4: curso, 5: status,
});

/** cabecalhos: { coluna1Based: texto }; alunos: [[linha, coluna1Based, cod, nome, tipo]]. */
function dia(cabecalhos, alunos) {
  const linhas = Array.from({ length: 26 }, () => vazia(14));
  for (const [coluna, texto] of Object.entries(cabecalhos)) {
    linhas[0][Number(coluna) - 1] = texto;
  }
  for (const [r, coluna, cod, nome, tipo] of alunos) {
    linhas[r - 1][coluna - 1] = cod;
    linhas[r - 1][coluna] = nome;
    linhas[r - 1][coluna + 2] = tipo;
  }
  return linhas;
}

/**
 * `extraMovimentos` acrescenta saídas no fim de `Ger. Apost` — é como o teste de
 * estabilidade simula o snapshot seguinte, que é o caso real: a planilha muda todo
 * dia até a virada (card 9.4).
 */
export function planilha(extraMovimentos = []) {
  const gerApost = [
    vazia(20), vazia(20),
    catalogoEMovimento({
      codigo: 1,
      nome: 'Windows 11',
      saida: ['2026-03-01', 1, 1, 4433],
      entrada: ['2026-02-01', 1, 10],
    }),
    catalogoEMovimento({
      codigo: 2, nome: 'Excel 365 InterativoIM', saida: ['2026-03-01', 1, 1, 4433],
    }),
    catalogoEMovimento({ codigo: 3, nome: 'Word MSE', saida: ['2026-04-02', 2, 1, null] }),
    catalogoEMovimento({ codigo: 4, nome: 'FIM', saida: ['2026-05-03', 2, 1, 3605] }),
  ];
  for (const saida of extraMovimentos) gerApost.push(catalogoEMovimento({ saida }));

  return new PlanilhaEmMemoria({
    'Ger. Apost': gerApost,
    'Apost. Inglês': [
      vazia(20), vazia(20),
      catalogoEMovimento({ codigo: 1, nome: 'Inglês - Check-In' }),
      catalogoEMovimento({ codigo: 2, nome: 'Take Off' }),
    ],
    'Apost. Modular': [
      vazia(20), vazia(20), catalogoEMovimento({ codigo: 1, nome: 'Chef Profissional' }),
    ],
    'Gerência': [
      vazia(60), vazia(60),
      gerencia(4433, 'Afonso Henrique Alves', '2026-12-01', 'ATIVO', [[1, 'SIM'], [2, 'NÃO']]),
      gerencia(3605, 'Beatriz Souza', '2023-01-10', 'ATIVO', [[2, 'NÃO']]),
      gerencia(1000, 'MACRO', null, 'ATIVO'),
      gerencia(7777, 'Carlos Andrade', null, 'Faltante'),
    ],
    'Ger. Inglês': [
      vazia(22), vazia(22),
      ingles(5001, 'Diana Prince', '2027-06-30', 'ATIVO', [[1, 'SIM']]),
    ],
    'Ger. Modular': [
      vazia(12), vazia(12),
      modular(6001, 'Elis Regina', null, 'Massagem Terapêutica', 'ATIVO'),
      modular(6002, 'Fábio Junior', null, 'Massagem Terapeutica', 'STANDBY'),
      // O terceiro existe para o desempate de grafia MEDIR alguma coisa: com um de
      // cada, "a mais frequente" e "a primeira vista" dão o mesmo resultado, e a
      // regra passaria verde sem ser exercitada.
      modular(6003, 'Gilberto Gil', null, 'Massagem Terapêutica', 'STANDBY'),
    ],
    Segunda: dia({ 2: '8H - CLAUDIR', 6: '10H - LINDOMAR' }, [
      [3, 2, 4433, 'Afonso Henrique Alves', 'PRE'],
      [4, 2, 9999, 'Beatriz Souza', 'R'],
      [5, 2, 8888, 'Ninguém Aqui', 'PRE'],
      [6, 2, 5001, 'Diana Prince', 'REM'],
      [3, 6, 4433, 'Afonso Henrique Alves (12/09)', 'NOVO'],
    ]),
    Quinta: dia({ 2: '8H - GILBERTO' }, [[3, 2, 5001, 'Diana Prince', 'REM']]),
    // As abas de dia sem bloco existem porque a AUSÊNCIA de uma delas é ERRO
    // `ABA_AUSENTE`, e com razão: dia que some da planilha some do sistema.
    'Terça': dia({}, []),
    Quarta: dia({}, []),
    Sexta: dia({}, []),
    'Sábado': dia({}, []),
  });
}
