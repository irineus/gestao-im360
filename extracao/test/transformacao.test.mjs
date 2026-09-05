import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { extrair } from '../transformacao.mjs';
import { SNAPSHOT, planilha } from './fixture.mjs';

const { arquivo, ocorrencias } = extrair(planilha(), SNAPSHOT);

const doCodigo = (codigo) => ocorrencias.filter((o) => o.codigo === codigo);

function uma(codigo) {
  const achadas = doCodigo(codigo);
  assert.equal(achadas.length, 1, `${codigo}: ${JSON.stringify(achadas)}`);
  return achadas[0];
}

const linhas = (entidade) => arquivo[entidade] ?? [];

describe('formato do arquivo', () => {
  it('traz snapshot_em e as entidades na ordem de dependência', () => {
    // A ordem das chaves é a ordem de aplicação do importador (`importacao.md` §3).
    // Ordenar alfabeticamente destruiria a leitura de quem confere o arquivo à mão,
    // que é o uso do card 9.4.
    const chaves = Object.keys(arquivo);
    assert.equal(chaves[0], 'snapshot_em');
    assert.equal(arquivo.snapshot_em, SNAPSHOT);
    assert.deepEqual(chaves.slice(1), [
      'professor', 'sala', 'material', 'curso', 'aluno',
      'bloco_horario', 'bloco_aluno', 'aluno_material', 'movimento_estoque',
    ]);
  });

  it('entidade sem mapa fica AUSENTE, e não vazia', () => {
    // Ausente é "não sei"; `[]` é "não há". Confundir os dois faz a conferência do
    // card 9.4 comparar contra um buraco sem perceber.
    for (const entidade of ['pc', 'pc_manutencao', 'turma_modular', 'modulo', 'curso_material']) {
      assert.equal(entidade in arquivo, false, entidade);
    }
    const abas = new Set(doCodigo('ABA_NAO_MAPEADA').map((o) => o.chave));
    assert.equal(abas.has('Base Modular'), true);
    assert.equal(abas.has('PCS'), true);
    assert.equal(abas.has('Pedidos'), true);
    assert.equal(doCodigo('ABA_NAO_MAPEADA').every((o) => o.severidade === 'ERRO'), true);
  });

  it('combo fica de fora e isso NÃO é lacuna', () => {
    // A planilha não cadastra combo (resposta 3 da análise): inventar um seria
    // escrever dado que ninguém digitou.
    assert.equal('combo' in arquivo, false);
    assert.equal(doCodigo('ABA_NAO_MAPEADA').filter((o) => o.entidade.includes('combo')).length, 0);
  });

  it('toda referência vai por chave natural e nunca por id', () => {
    for (const [entidade, lista] of Object.entries(arquivo)) {
      if (!Array.isArray(lista)) continue;
      for (const registro of lista) {
        assert.equal('id' in registro, false, `${entidade}: ${JSON.stringify(registro)}`);
      }
    }
  });
});

describe('material', () => {
  it('as duas limpezas do plano saem do catálogo e entram no relatório', () => {
    const nomes = new Set(linhas('material').map((m) => m.nome));
    assert.equal(nomes.has('Word MSE'), false); // catálogo encerrado em 31/08/2026
    assert.equal(nomes.has('FIM'), false); // marcador, não apostila
    assert.equal(doCodigo('MATERIAL_DESCARTADO').length, 2);
  });

  it('o mesmo código em métodos diferentes é material diferente', () => {
    // Código 1 é "Windows 11" no Interativo e "Inglês - Check-In" no Inglês
    // (análise §2). A chave é metodo + codigo justamente por isso.
    const um = linhas('material').filter((m) => m.codigo === '1');
    assert.deepEqual(new Set(um.map((m) => m.metodo)),
      new Set(['INTERATIVO', 'INGLES', 'MODULAR']));
  });
});

describe('movimento de estoque', () => {
  it('a chave é única mesmo com duas saídas idênticas no mesmo dia', () => {
    // `movimento_estoque` é imutável: chave repetida faz a segunda importação
    // duplicar o movimento, e a sobra não se apaga — só se estorna.
    const chaves = linhas('movimento_estoque').map((m) => m.chave);
    assert.equal(chaves.length, new Set(chaves).size);
    assert.deepEqual(
      chaves.filter((c) => c.startsWith('SAIDA-2026-03-01-INTERATIVO-1-4433-1-')).sort(),
      ['SAIDA-2026-03-01-INTERATIVO-1-4433-1-1', 'SAIDA-2026-03-01-INTERATIVO-1-4433-1-2'],
    );
  });

  it('o sinal vem do tipo', () => {
    // `movimento_sinal_ck`: ENTRADA > 0 e SAIDA < 0. Sinal trocado custaria a
    // transação inteira no check, com o relatório do importador já escrito.
    for (const m of linhas('movimento_estoque')) {
      if (m.tipo === 'ENTRADA') assert.ok(m.quantidade > 0, m.chave);
      else assert.ok(m.quantidade < 0, m.chave);
    }
  });

  it('saída sem aluno vira AJUSTE', () => {
    const ajustes = linhas('movimento_estoque').filter((m) => m.tipo === 'AJUSTE');
    assert.equal(ajustes.length, 1);
    assert.equal('aluno' in ajustes[0], false);
    assert.equal(uma('SAIDA_SEM_ALUNO').entidade, 'movimento_estoque');
  });

  it('movimento que aponta para material descartado não entra', () => {
    // O código 3 é MSE e saiu do catálogo: um movimento para ele seria
    // REFERENCIA_AUSENTE no importador, no meio de milhares de linhas.
    assert.equal(linhas('movimento_estoque').every((m) => ['1', '2'].includes(m.material)), true);
  });
});

describe('aluno e trilha', () => {
  const alunos = new Map(linhas('aluno').map((a) => [a.codigo, a]));

  it('registro técnico não vira aluno', () => {
    assert.equal(alunos.has('1000'), false);
    assert.equal(uma('ALUNO_DESCARTADO').chave, '1000');
  });

  it('status que o sistema não conhece sai em branco, com aviso', () => {
    // "Faltante" está na planilha e não está no check da coluna. Traduzi-lo aqui
    // seria adivinhar a transição que o card 9.3 existe para decidir.
    assert.equal('status' in alunos.get('7777'), false);
    assert.equal(uma('STATUS_DESCONHECIDO').chave, '7777');
  });

  it('previsão atípica só para quem está em turma', () => {
    assert.deepEqual(new Set(doCodigo('PREVISAO_ATIPICA').map((o) => o.chave)), new Set(['3605']));
  });

  it('a trilha é MANUAL e numerada a partir de 1', () => {
    // Sem combo não há trilha derivada: marcar COMBO faria `tg_aluno_trilha_inicial`
    // disputar a trilha com o arquivo.
    const doAfonso = linhas('aluno_material').filter((t) => t.aluno === '4433');
    assert.deepEqual(doAfonso.map((t) => t.ordem), [1, 2]);
    assert.equal(linhas('aluno_material').every((t) => t.origem === 'MANUAL'), true);
  });

  it('a data de entrega vem da saída de estoque', () => {
    // A trilha só diz SIM/NÃO; a data só existe nas SAÍDAS. Sem esta junção o
    // histórico entra mudo e o card 9.5 calibraria ritmo sobre nada.
    const entregue = linhas('aluno_material')
      .find((t) => t.aluno === '4433' && t.material === '1');
    assert.equal(entregue.data_entrega, '2026-03-01');
  });

  it('os dois lados da divergência entrega × saída', () => {
    // Hoje a entrega exige DOIS lançamentos manuais e nada garante os dois.
    assert.equal(uma('SAIDA_SEM_ENTREGA').chave, '3605');
    assert.equal(uma('TRILHA_SEM_DATA').chave, 'INGLES');
  });
});

describe('curso', () => {
  it('grafias do mesmo curso viram um curso só e uma linha de relatório', () => {
    // Vence a MAIS FREQUENTE, não a primeira em ordem alfabética: em ordem de code
    // unit "Terapeutica" vem antes de "Terapêutica", e a escola inteira entraria
    // com o typo.
    assert.deepEqual(linhas('curso').map((c) => c.nome), ['Massagem Terapêutica']);
    assert.match(uma('GRAFIA_DUPLICADA').detalhe, /"Massagem Terapêutica" \(2×\)/);
    assert.match(uma('GRAFIA_DUPLICADA').detalhe, /"Massagem Terapeutica" \(1×\)/);
  });
});

describe('bloco e alocação', () => {
  const blocos = new Map(linhas('bloco_horario').map((b) => [`${b.dia_semana}/${b.hora_inicio}`, b]));

  it('o método do bloco sai da regra do Dashboard', () => {
    assert.equal(blocos.get('1/08:00').metodo, 'INTERATIVO');
    assert.equal(blocos.get('4/08:00').metodo, 'INGLES');
  });

  it('professor sai do cabeçalho e vira entidade, sem repetir', () => {
    assert.deepEqual(linhas('professor').map((p) => p.nome), ['CLAUDIR', 'GILBERTO', 'LINDOMAR']);
    assert.equal(blocos.get('1/08:00').professor, 'CLAUDIR');
  });

  it('"R" se lê REP', () => {
    assert.equal(uma('TIPO_CORRIGIDO').chave, '3605');
    assert.deepEqual(
      linhas('bloco_aluno').filter((a) => a.aluno === '3605').map((a) => a.tipo), ['REP'],
    );
  });

  it('código divergente na turma é resolvido pelo nome único', () => {
    // A turma é digitada à mão, sem fórmula ligando à Gerência: o código é a parte
    // frágil e o nome é a confiável.
    assert.equal(uma('CODIGO_DIVERGENTE').chave, '9999');
    const alocados = new Set(linhas('bloco_aluno').map((a) => a.aluno));
    assert.equal(alocados.has('3605'), true);
    assert.equal(alocados.has('9999'), false);
  });

  it('código sem cadastro e sem homônimo não vira alocação', () => {
    assert.equal(uma('TURMA_SEM_CADASTRO').chave, '8888');
  });

  it('aluno de Inglês em bloco de Interativo não entra', () => {
    // O trigger de admissão recusaria a linha e levaria a transação inteira junto,
    // na décima sétima entidade.
    assert.equal(uma('METODO_DIVERGENTE').chave, '5001');
    assert.deepEqual(
      linhas('bloco_aluno').filter((a) => a.aluno === '5001').map((a) => a.dia_semana), [4],
    );
  });

  it('NOVO carrega a data do nome, e o nome fica sem ela', () => {
    // `bloco_aluno_novo_ck` exige `data_inicio_prevista` quando o tipo é NOVO.
    const novo = linhas('bloco_aluno').find((a) => a.tipo === 'NOVO');
    assert.equal(novo.data_inicio_prevista, '2026-09-12');
    assert.equal(doCodigo('NOVO_SEM_DATA').length, 0);
  });

  it('o mesmo aluno em dois blocos é aceleração, e não erro', () => {
    assert.equal(uma('MULTI_BLOCO').chave, '4433');
  });

  it('ativo fora de turma é aviso', () => {
    assert.deepEqual(new Set(doCodigo('ALUNO_SEM_TURMA').map((o) => o.chave)),
      new Set(['6001', '7777']));
  });

  it('a sala do laboratório é presumida e diz que é', () => {
    assert.deepEqual(linhas('sala'), [{
      nome: 'Laboratório de Informática', tipo: 'LABORATORIO', capacidade_nominal: 10,
    }]);
    assert.equal(uma('SALA_PRESUMIDA').severidade, 'AVISO');
  });

  it('nenhuma aba de dia foi dada por ausente', () => {
    assert.equal(doCodigo('ABA_AUSENTE').length, 0);
  });
});
