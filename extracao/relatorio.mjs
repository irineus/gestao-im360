// O relatório de inconsistências do card 9.2 — o entregável "auditável" do plano §8.
//
// Duas severidades, e a diferença entre elas não é intensidade:
//
// - **ERRO** — o arquivo sairia errado ou incompleto, e a conferência do card 9.4
//   compararia contra um buraco. Quem lê precisa consertar a planilha ou o mapa
//   antes de importar.
// - **AVISO** — o arquivo está bom e uma pessoa precisa olhar. É a lista que o
//   card 9.3 revisa caso a caso.
//
// ⚠️ Isto NÃO é a validação do importador. As dezesseis verificações de
// `fn_importacao_validar` (card 9.1) conferem o arquivo contra si mesmo e contra o
// banco; estas aqui conferem **o que só a planilha responde** — grafia duplicada,
// código divergente resolvido por nome, transformação aplicada, linha descartada.
// Uma não substitui a outra, e as duas listas se encontram no dry-run do card 9.4.

export const ERRO = 'ERRO';
export const AVISO = 'AVISO';

export const CABECALHO = ['severidade', 'codigo', 'entidade', 'chave', 'detalhe'];

export function ocorrencia(severidade, codigo, entidade, chave, detalhe = '') {
  return {
    severidade,
    codigo,
    entidade,
    chave: chave === null || chave === undefined ? '' : String(chave),
    detalhe,
  };
}

/**
 * ERRO primeiro, e depois ordem estável por código/entidade/chave.
 *
 * A ordem é parte do contrato de determinismo: duas extrações do mesmo snapshot
 * têm de produzir o mesmo relatório byte a byte, ou "o que mudou entre ontem e
 * hoje" vira um diff de ruído.
 */
export function ordenar(ocorrencias) {
  const peso = { [ERRO]: 0, [AVISO]: 1 };
  return [...ocorrencias].sort((a, b) => {
    const chaveA = [peso[a.severidade] ?? 9, a.codigo, a.entidade, a.chave, a.detalhe];
    const chaveB = [peso[b.severidade] ?? 9, b.codigo, b.entidade, b.chave, b.detalhe];
    for (let i = 0; i < chaveA.length; i += 1) {
      if (chaveA[i] < chaveB[i]) return -1;
      if (chaveA[i] > chaveB[i]) return 1;
    }
    return 0;
  });
}

function campo(valor) {
  const s = String(valor);
  // Só escapa quando precisa: aspas em todo campo transformam um relatório de
  // quarenta linhas num relatório ilegível a olho nu, e a olho nu é como ele é
  // lido na revisão do card 9.3.
  return /[";\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/**
 * CSV com separador `;`, que é o que o Excel em português espera.
 *
 * Mesma escolha do "Baixar relatório" da tela 13 (`docs/importacao.md` §6): o
 * relatório do extrator e o do importador se abrem do mesmo jeito, e quem confere
 * os dois lado a lado não troca de ferramenta no meio.
 */
export function comoCsv(ocorrencias) {
  const linhas = [CABECALHO.join(';')];
  for (const o of ordenar(ocorrencias)) {
    linhas.push([o.severidade, o.codigo, o.entidade, o.chave, o.detalhe]
      .map(campo).join(';'));
  }
  return `${linhas.join('\n')}\n`;
}

/** `{ erros, avisos }`. */
export function contar(ocorrencias) {
  const erros = ocorrencias.filter((o) => o.severidade === ERRO).length;
  return { erros, avisos: ocorrencias.length - erros };
}
