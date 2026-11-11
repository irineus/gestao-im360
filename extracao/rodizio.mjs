// A turma em rodízio na planilha (card 9.2,91, docs/turma-rodizio.md §8).
//
// ⚠️ ESTE ARQUIVO É A REGRA, SEM O MAPA. As abas de turma por curso (Massagem,
// Chef+Panificação, …) e a `Base Modular` continuam em `ABAS_NAO_MAPEADAS`: a
// planilha não está neste repositório, e a posição das colunas só se mede com
// ela aberta (`--mapear`, card 9.4). O que se conhece — pelos prints e áudios do
// dono do produto de 06/11/2026 — é a FORMA da linha do aluno:
//
//     aluno | Módulo 01 | Início | Previsão | Módulo 02 | Início | Previsão | …
//
// A lista é a sequência DO ALUNO, na ordem em que ele faz: o `Módulo 01` é aquele
// em que ele entrou na turma, e não o primeiro do curso. `Início` é SIM/NÃO.
//
// Daqui saem as duas coisas que o importador passou a aceitar:
//
//   • `turma_modular_aluno.modulo_entrada` — a ordem, NO CURSO, do `Módulo 01`;
//   • `aluno_modulo` — os módulos que ele já fez, com a data.
//
// Quando o mapa das colunas existir, quem lê a aba monta `{ modulos: [...] }` e
// chama `derivarRodizio`. A regra não muda de forma.

import * as v from './valores.mjs';

/**
 * `nome do módulo (normalizado)` → `ordem no curso`, a partir das linhas de
 * `modulo` do curso (as que a `Base Modular` dá).
 *
 * Dois módulos do mesmo curso com o mesmo nome normalizado ficam FORA do mapa e
 * voltam em `ambiguos`: escolher um deles daria ao aluno um módulo que talvez
 * não seja o dele, sem erro nenhum.
 */
export function catalogoDoCurso(modulos) {
  const porNome = new Map();
  const ambiguos = new Set();
  for (const m of modulos) {
    const chave = v.norm(m.nome);
    if (chave === '') continue;
    if (porNome.has(chave) && porNome.get(chave) !== m.ordem) ambiguos.add(chave);
    porNome.set(chave, m.ordem);
  }
  for (const chave of ambiguos) porNome.delete(chave);
  return { porNome, ambiguos };
}

/**
 * A linha de um aluno numa aba de turma → módulo de entrada e módulos feitos.
 *
 * @param {{nome: unknown, inicio: unknown, previsao: unknown}[]} modulos
 *   os módulos NA ORDEM DA LINHA (Módulo 01, 02, …); célula de nome vazia é
 *   ignorada, que é como a planilha termina a lista.
 * @param {{porNome: Map<string, number>, ambiguos: Set<string>}} catalogo
 * @param {string} snapshot `AAAA-MM-DD`
 * @returns {{
 *   moduloEntrada: number|null,
 *   feitos: {modulo_ordem: number, data_conclusao: string}[],
 *   emCurso: number|null,
 *   ocorrencias: {codigo: string, mensagem: string}[],
 * }}
 *
 * As regras, e por que cada uma:
 *
 * 1. **Entrada = o primeiro módulo da linha.** A linha começa onde o aluno
 *    começou.
 *
 * 2. **O ÚLTIMO módulo com Início = SIM é o que ele está fazendo; os iniciados
 *    antes dele estão feitos.** A planilha marca módulo *iniciado*, não
 *    *concluído* — e a turma dá um módulo de cada vez, então ter começado o
 *    seguinte é o que diz que o anterior acabou.
 *
 * 3. **A data de conclusão do módulo feito é a previsão que ficou gravada na
 *    linha.** É o que a planilha tem. Sem previsão, o módulo NÃO sai como feito
 *    e a linha ganha `MODULO_FEITO_SEM_DATA`: o importador exige a data, e
 *    inventar uma faria a ficha do aluno afirmar um dia que ninguém registrou.
 *
 * 4. **Módulo com Início = NÃO no meio de dois SIM não é erro.** É o módulo que
 *    o aluno perdeu (STANDBY): no sistema, "a fazer" é a ausência do registro, e
 *    ele o refaz quando a turma voltar a ele. Simplesmente não entra nos feitos.
 *
 * 5. **Nome que o catálogo do curso não conhece** vira `MODULO_FORA_DO_CATALOGO`
 *    e não entra em lugar nenhum. É a pergunta 5 da proposta, com nome próprio:
 *    a `Base Modular` e a aba da turma podem não listar os mesmos módulos.
 */
export function derivarRodizio(modulos, catalogo, snapshot) {
  const ocorrencias = [];
  const linha = [];

  for (const m of modulos) {
    const nome = v.texto(m.nome);
    if (nome === null) continue;
    const chave = v.norm(nome);
    const ordem = catalogo.porNome.get(chave) ?? null;
    if (ordem === null) {
      ocorrencias.push({
        codigo: catalogo.ambiguos.has(chave)
          ? 'MODULO_AMBIGUO'
          : 'MODULO_FORA_DO_CATALOGO',
        mensagem: catalogo.ambiguos.has(chave)
          ? `o módulo "${nome}" aparece mais de uma vez no catálogo do curso, em `
            + 'posições diferentes — não dá para saber qual é o do aluno.'
          : `o módulo "${nome}" não está entre os módulos do curso na Base Modular.`,
      });
    }
    linha.push({
      nome,
      ordem,
      iniciado: v.sim(m.inicio),
      previsao: v.data(m.previsao),
    });
  }

  if (linha.length === 0) {
    return { moduloEntrada: null, feitos: [], emCurso: null, ocorrencias };
  }

  // 1. a entrada
  const moduloEntrada = linha[0].ordem;

  // 2. o último iniciado é o que está em curso
  let ultimo = -1;
  linha.forEach((m, i) => {
    if (m.iniciado) ultimo = i;
  });

  // 3 e 4. os iniciados ANTES dele estão feitos, com a previsão gravada
  const feitos = [];
  const jaVistos = new Set();
  for (let i = 0; i < ultimo; i += 1) {
    const m = linha[i];
    if (!m.iniciado || m.ordem === null) continue;
    if (jaVistos.has(m.ordem)) {
      ocorrencias.push({
        codigo: 'MODULO_REPETIDO',
        mensagem: `o módulo "${m.nome}" aparece duas vezes como iniciado na linha `
          + 'do aluno — ficou a primeira.',
      });
      continue;
    }
    if (m.previsao === null) {
      ocorrencias.push({
        codigo: 'MODULO_FEITO_SEM_DATA',
        mensagem: `o módulo "${m.nome}" foi iniciado e já há outro depois dele, mas `
          + 'a linha não tem a previsão de conclusão — sem data ele não entra como '
          + 'feito, e o aluno o veria de novo na sequência.',
      });
      continue;
    }
    if (m.previsao > snapshot) {
      // Não bloqueia: o importador avisa de novo (V18, MODULO_DATA_FUTURA). Aqui
      // o aviso tem a linha da planilha, que é onde se corrige.
      ocorrencias.push({
        codigo: 'MODULO_FEITO_COM_DATA_FUTURA',
        mensagem: `o módulo "${m.nome}" consta como já feito, com previsão em `
          + `${m.previsao}, depois do snapshot (${snapshot}).`,
      });
    }
    jaVistos.add(m.ordem);
    feitos.push({ modulo_ordem: m.ordem, data_conclusao: m.previsao });
  }

  return {
    moduloEntrada,
    feitos,
    emCurso: ultimo >= 0 ? linha[ultimo].ordem : null,
    ocorrencias,
  };
}

/**
 * As linhas que vão para o arquivo de importação, no formato do contrato
 * (`docs/importacao.md` §3): a alocação com `modulo_entrada` e os `aluno_modulo`.
 *
 * `modulo_entrada` só entra quando foi resolvido: ausente, no importador, é
 * "não sei" e não apaga o que já está gravado — escrever `null` daria no mesmo,
 * mas a chave ausente é o que o contrato diz.
 */
export function linhasDoRodizio({ aluno, turma, metodo, curso, dataEntrada }, derivado) {
  const alocacao = { turma, aluno };
  if (dataEntrada) alocacao.data_entrada = dataEntrada;
  if (derivado.moduloEntrada !== null) alocacao.modulo_entrada = derivado.moduloEntrada;
  return {
    turma_modular_aluno: alocacao,
    aluno_modulo: derivado.feitos.map((f) => ({
      aluno,
      metodo,
      curso,
      modulo_ordem: f.modulo_ordem,
      data_conclusao: f.data_conclusao,
    })),
  };
}
