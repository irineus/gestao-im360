// Mapa de abas e colunas da planilha `Gestão Interativo.xlsx` (card 9.2).
//
// Tudo o que depende da POSIÇÃO de uma célula mora aqui, e em nenhum outro lugar.
// Número mágico espalhado pelo corpo vira decisão invisível: quando a planilha
// muda uma coluna de lugar, o script continua lendo — só que outra coisa.
//
// As posições MEDIDAS vêm da análise de 29–30/08/2026
// (`docs/analise-planilha-entendimento.md` §2 e o protótipo de
// `docs/script-extracao-planilha.md`), que leu o snapshot de 29/08/2026 célula a
// célula. Elas foram portadas SEM MUDANÇA na virada para Node.
//
// ⚠️ As posições NÃO MEDIDAS estão em `ABAS_NAO_MAPEADAS`, com as entidades que
// alimentariam. Elas não são chute: são o que ninguém abriu. O extrator emite ERRO
// `ABA_NAO_MAPEADA` para cada uma em vez de deixar a entidade sair vazia —
// entidade vazia por falta de mapa é indistinguível de entidade vazia por não
// haver dado, e é essa confusão que faria a conferência do card 9.4 comparar
// contra um buraco sem perceber.

export const INTERATIVO = 'INTERATIVO';
export const INGLES = 'INGLES';
export const MODULAR = 'MODULAR';

// --- Abas de catálogo de apostilas -------------------------------------------
// Índices 0-based dentro da linha, a partir da linha 3:
//   2 = código, 3 = nome, 4 = estoque, 5 = demanda, 6 = pedido
export const CATALOGO = [
  ['Ger. Apost', INTERATIVO],
  ['Apost. Inglês', INGLES],
  ['Apost. Modular', MODULAR],
];

export const CAT_LINHA_INICIAL = 3;
export const CAT_CODIGO = 2;
export const CAT_NOME = 3;

// Linhas que não são material (a limpeza do plano §8).
export const CAT_NOMES_DESCARTADOS = ['FIM', 'NÃO RECEBEU'];
// Catálogo MSE encerrado em 31/08/2026 (resposta 13 da análise): não entra.
export const CAT_SUFIXO_ENCERRADO = 'MSE';

// `material.categoria` é `not null` no DDL e a categoria fina (Informática, Design
// Gráfico, Kids…) vive na aba `Pedidos`, que não está mapeada. Vale o rótulo do
// exemplo do próprio contrato (`docs/importacao.md` §3) e um AVISO por método.
export const CATEGORIA_PRESUMIDA = 'APOSTILA';

// --- Movimentos de estoque ---------------------------------------------------
// Só `Ger. Apost` os tem, segundo o plano §8 e a contagem da análise (234 saídas,
// 110 entradas). As outras duas abas de catálogo são varridas nas MESMAS colunas
// só para denunciar a premissa, se um dia ela deixar de valer.
export const MOV_ABA = 'Ger. Apost';
export const MOV_METODO = INTERATIVO;

export const MOV_SAIDA_DATA = 8; // I
export const MOV_SAIDA_CODIGO = 9; // J
export const MOV_SAIDA_QTD = 11; // L
export const MOV_SAIDA_ALUNO = 12; // M

export const MOV_ENTRADA_DATA = 15; // P
export const MOV_ENTRADA_CODIGO = 16; // Q
export const MOV_ENTRADA_QTD = 18; // S

// --- Abas de cadastro de aluno ----------------------------------------------

export const GERENCIA_ABA = 'Gerência';
export const GERENCIA_CODIGO = 1;
export const GERENCIA_NOME = 2;
export const GERENCIA_PREV = 3;
export const GERENCIA_STATUS = 4;
// Trilha: 17 posições em blocos de 3 (código, nome por lookup, entregue), de J a BE.
export const GERENCIA_TRILHA = Array.from({ length: 17 }, (_, i) => 9 + i * 3);

export const INGLES_ABA = 'Ger. Inglês';
export const INGLES_CODIGO = 1;
export const INGLES_NOME = 2;
export const INGLES_PREV = 3;
export const INGLES_STATUS = 4;
export const INGLES_TRILHA = [10, 13, 16, 19];

export const MODULAR_ABA = 'Ger. Modular';
export const MODULAR_CODIGO = 1;
export const MODULAR_NOME = 2;
export const MODULAR_PREV = 3;
export const MODULAR_CURSO = 4;
export const MODULAR_STATUS = 5;

export const ALUNO_LINHA_INICIAL = 3;
export const TRILHA_DESLOCAMENTO_ENTREGUE = 2; // código + 2 = flag "Entregue"

// Registros técnicos da planilha, não alunos (plano §8 e resposta 5 da análise).
export const ALUNOS_DESCARTADOS = ['MACRO', 'BALANÇO', 'FAKE 02'];

export const STATUS_VALIDOS = [
  'ATIVO', 'ACELERAR', 'STANDBY', 'TRANCADO', 'CANCELADO', 'FORMADO',
];
export const STATUS_EM_TURMA = ['ATIVO', 'ACELERAR'];

// --- Abas de turma por dia da semana ----------------------------------------

export const DIAS = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];
export const DIA_ISO = {
  Segunda: 1, Terça: 2, Quarta: 3, Quinta: 4, Sexta: 5, Sábado: 6,
};

// [linha do cabeçalho, primeira linha de aluno, última, coluna do código] — 1-based.
export const BLOCOS = [
  [1, 3, 12, 2], [1, 3, 12, 6], [1, 3, 12, 10],
  [14, 16, 25, 2], [14, 16, 25, 6], [14, 16, 25, 10],
];
// Deslocamentos a partir da coluna do código.
export const BLOCO_NOME = 1;
export const BLOCO_PREV = 2;
export const BLOCO_TIPO = 3;

// Regra do Dashboard (análise §3, item 5): Quinta inteira + Sexta 20H + Sábado 8H
// e 10H são Inglês; todo o resto é Interativo.
export const INGLES_DIA_INTEIRO = ['Quinta'];
export const INGLES_BLOCOS = [
  ['Sexta', '20:00'], ['Sábado', '08:00'], ['Sábado', '10:00'],
];

export const TIPOS_ALOCACAO = ['REM', 'PRE', 'REP', 'NOVO'];
// "R" foi lançamento incorreto e se lê REP (resposta 6 da análise, 30/08/2026).
export const TIPOS_CORRIGIDOS = { R: 'REP' };

// A sala do laboratório: a aba `PCS` não está mapeada, então o nome é presumido e
// a capacidade vem da resposta 8 da análise (10 PCs, e é isso que dá as 10 vagas).
export const SALA_LABORATORIO_PADRAO = 'Laboratório de Informática';
export const SALA_LABORATORIO_CAPACIDADE = 10;

// --- O que não foi mapeado ---------------------------------------------------

export const ABAS_NAO_MAPEADAS = [
  {
    aba: 'Base Modular',
    entidades: ['curso_material', 'modulo'],
    porque: 'curso → livro → módulos do Modular; a posição das colunas nunca foi lida.',
  },
  {
    aba: 'abas por curso (Massagem, Manicure, Chef+Panificação, Combo Beleza, '
      + 'Violão, Pizzaiolo, Eletricista, Corte e Costura, Depilação)',
    entidades: ['turma_modular', 'turma_modular_modulo', 'turma_modular_aluno'],
    porque: 'datas de início e previsão por módulo da turma; o layout está descrito '
      + 'em prosa na análise §2, sem posições.',
  },
  {
    aba: 'Pedidos',
    entidades: ['material.estoque_minimo', 'material.categoria'],
    porque: 'os ajustes manuais (+5, +7) estão DENTRO das fórmulas e exigem o '
      + 'workbook de fórmulas; nem as posições nem o formato foram lidos.',
  },
  {
    aba: 'PCS',
    entidades: ['sala', 'pc', 'pc_manutencao'],
    porque: 'credencial nunca se migra (card 2.9 §1.5, e as atuais estão queimadas); '
      + 'o resto da aba não foi lido.',
  },
];

// Abas mapeadas de propósito para NADA.
export const ABAS_IGNORADAS = [
  ['Dashboard', 'é recalculado por views; serve de conferência, não de fonte.'],
  ['Certificados', 'não se importa (card 8.3 e docs/importacao.md §2.2): a aba não '
    + 'guarda quem marcou nem quando, que é o que a tabela existe para guardar.'],
];

// --- Saída --------------------------------------------------------------------

// Ordem de dependência do contrato (`docs/importacao.md` §3). O extrator escreve
// as chaves NESTA ordem, e só as que ele sabe produzir.
export const ORDEM_ENTIDADES = [
  'professor', 'sala', 'pc', 'pc_manutencao', 'material', 'curso',
  'curso_material', 'modulo', 'combo', 'combo_curso', 'aluno', 'bloco_horario',
  'bloco_aluno', 'turma_modular', 'turma_modular_modulo', 'turma_modular_aluno',
  'aluno_material', 'movimento_estoque',
];

// As que este script produz hoje. `combo`/`combo_curso` estão fora e NÃO é falta de
// mapa: a planilha não cadastra combo (resposta 3 da análise, 30/08/2026) — a
// hierarquia combo → curso → material é do sistema novo, e inventá-la aqui seria
// escrever dado que ninguém digitou.
export const ENTIDADES_PRODUZIDAS = [
  'professor', 'sala', 'material', 'curso', 'aluno',
  'bloco_horario', 'bloco_aluno', 'aluno_material', 'movimento_estoque',
];
