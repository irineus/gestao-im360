// Da planilha para o arquivo do card 9.1 — a parte que decide, e que é pura.
//
// Recebe uma `planilha` (qualquer objeto com `abas()` e `linhas(aba)`) e devolve
// `{ arquivo, ocorrencias }`. Não abre arquivo, não descompacta nada, não olha o
// relógio: a data do snapshot é argumento. É isso que torna a suíte executável sem
// a planilha real — que não está neste repositório — e que faz o extrator ser
// determinístico.
//
// A regra que organiza o módulo inteiro: **transformar e denunciar, nunca decidir
// regra de negócio**. Capacidade de bloco, transição de status e trilha derivada do
// combo são do banco, e o importador do card 9.1 existe justamente para não haver
// uma segunda implementação delas aqui (a ideia central do §1 daquele documento).

import * as L from './layout.mjs';
import * as v from './valores.mjs';
import { AVISO, ERRO, ocorrencia } from './relatorio.mjs';

class Extracao {
  constructor(planilha, snapshot, salaLaboratorio) {
    this.planilha = planilha;
    this.snapshot = snapshot;
    this.sala = salaLaboratorio || L.SALA_LABORATORIO_PADRAO;
    this.ocorrencias = [];
    this.entidades = {};
    this.abasExistentes = new Set(planilha.abas());
    this.cache = new Map();
  }

  diz(severidade, codigo, entidade, chave, detalhe = '') {
    this.ocorrencias.push(ocorrencia(severidade, codigo, entidade, chave, detalhe));
  }

  todas(aba) {
    if (!this.cache.has(aba)) {
      this.cache.set(aba, this.abasExistentes.has(aba) ? this.planilha.linhas(aba) : []);
    }
    return this.cache.get(aba);
  }

  linhas(aba, aPartirDe = 1) {
    return this.todas(aba).slice(aPartirDe - 1);
  }

  static cel(linha, indice) {
    const valor = linha[indice];
    return valor === undefined ? null : valor;
  }

  /** Acesso 1-based, como no protótipo — as abas de dia são posicionais. */
  celula(aba, linha, coluna) {
    const linhas = this.todas(aba);
    if (linha < 1 || linha > linhas.length) return null;
    return Extracao.cel(linhas[linha - 1], coluna - 1);
  }

  // -- 1. material ---------------------------------------------------------

  materiais() {
    const materiais = [];
    const vistos = new Set();
    const descartados = L.CAT_NOMES_DESCARTADOS.map(v.norm);
    for (const [aba, metodo] of L.CATALOGO) {
      if (!this.abasExistentes.has(aba)) {
        this.diz(ERRO, 'ABA_AUSENTE', 'material', aba,
          `a aba de catálogo de ${metodo} não existe na planilha.`);
        continue;
      }
      for (const linha of this.linhas(aba, L.CAT_LINHA_INICIAL)) {
        const cod = v.codigo(Extracao.cel(linha, L.CAT_CODIGO));
        const nome = v.texto(Extracao.cel(linha, L.CAT_NOME));
        if (cod === null || nome === null) continue;
        if (descartados.includes(v.norm(nome))) {
          this.diz(AVISO, 'MATERIAL_DESCARTADO', 'material', `${metodo}/${cod}`,
            `"${nome}" não é apostila — é marcador da planilha.`);
          continue;
        }
        if (metodo === L.INTERATIVO && nome.toUpperCase().endsWith(L.CAT_SUFIXO_ENCERRADO)) {
          this.diz(AVISO, 'MATERIAL_DESCARTADO', 'material', `${metodo}/${cod}`,
            `"${nome}" é do catálogo MSE, encerrado em 31/08/2026.`);
          continue;
        }
        const chave = `${metodo}/${cod}`;
        if (vistos.has(chave)) {
          this.diz(ERRO, 'MATERIAL_DUPLICADO', 'material', chave,
            `o código aparece mais de uma vez no catálogo; "${nome}" foi descartado.`);
          continue;
        }
        vistos.add(chave);
        materiais.push({
          metodo, codigo: cod, nome, categoria: L.CATEGORIA_PRESUMIDA,
        });
      }
      this.diz(AVISO, 'CATEGORIA_PRESUMIDA', 'material', metodo,
        `todo material saiu com categoria "${L.CATEGORIA_PRESUMIDA}": a categoria fina `
        + '(Informática, Design Gráfico, Kids…) vive na aba Pedidos, que não está mapeada.');
    }
    this.entidades.material = materiais;
    return vistos;
  }

  // -- 2. movimento_estoque ------------------------------------------------

  movimentos(materiais) {
    const brutos = [];
    for (const linha of this.linhas(L.MOV_ABA, L.CAT_LINHA_INICIAL)) {
      if (Extracao.cel(linha, L.MOV_SAIDA_DATA) !== null) {
        brutos.push(this.movimentoSaida(linha));
      }
      if (Extracao.cel(linha, L.MOV_ENTRADA_DATA) !== null) {
        brutos.push(this.movimentoEntrada(linha));
      }
    }
    this.denunciarMovimentoForaDeGerApost();

    const movimentos = [];
    const ordinais = new Map();
    for (const m of brutos) {
      if (m === null) continue;
      if (!materiais.has(`${m.metodo}/${m.material}`)) {
        this.diz(ERRO, 'MOVIMENTO_SEM_MATERIAL', 'movimento_estoque',
          `${m.metodo}/${m.material}`,
          `movimento de ${m.ocorrido_em} aponta para código que não está no catálogo; `
          + 'a linha foi descartada.');
        continue;
      }
      // A chave é composta pelo CONTEÚDO da linha, nunca pela posição dela: linha
      // inserida no meio é o que mais acontece numa planilha viva, e uma chave que
      // carregasse o número da linha deslocaria todas as de baixo — a reimportação
      // duplicaria o histórico inteiro, e `movimento_estoque` é imutável.
      const identidade = [m.tipo, m.ocorrido_em, m.metodo, m.material,
        m.aluno ?? 'SEM_ALUNO', Math.abs(m.quantidade)];
      const raiz = identidade.join('-');
      const ordinal = (ordinais.get(raiz) ?? 0) + 1;
      ordinais.set(raiz, ordinal);
      movimentos.push({ chave: `${raiz}-${ordinal}`, ...m });
    }
    this.entidades.movimento_estoque = movimentos;
    return movimentos;
  }

  movimentoSaida(linha) {
    const bruta = Extracao.cel(linha, L.MOV_SAIDA_DATA);
    const iso = v.data(bruta);
    const cod = v.codigo(Extracao.cel(linha, L.MOV_SAIDA_CODIGO));
    const qtd = v.inteiro(Extracao.cel(linha, L.MOV_SAIDA_QTD));
    const aluno = v.codigo(Extracao.cel(linha, L.MOV_SAIDA_ALUNO));
    if (iso === null || cod === null || !qtd) {
      this.diz(ERRO, 'MOVIMENTO_ILEGIVEL', 'movimento_estoque', cod ?? '',
        `saída com data ${JSON.stringify(v.texto(bruta))}, código ${JSON.stringify(cod)} e `
        + `quantidade ${JSON.stringify(qtd)} — a linha foi descartada.`);
      return null;
    }
    // Saída sem aluno vira AJUSTE (plano §8): não houve entrega a ninguém, e chamar
    // aquilo de SAIDA daria ao estoque um consumo com dono inexistente.
    if (!aluno) {
      this.diz(AVISO, 'SAIDA_SEM_ALUNO', 'movimento_estoque', `${L.MOV_METODO}/${cod}`,
        `saída de ${iso} sem código de aluno — entrou como AJUSTE.`);
      return {
        metodo: L.MOV_METODO, material: cod, tipo: 'AJUSTE',
        quantidade: -Math.abs(qtd), ocorrido_em: iso,
      };
    }
    return {
      metodo: L.MOV_METODO, material: cod, tipo: 'SAIDA',
      quantidade: -Math.abs(qtd), ocorrido_em: iso, aluno,
    };
  }

  movimentoEntrada(linha) {
    const bruta = Extracao.cel(linha, L.MOV_ENTRADA_DATA);
    const iso = v.data(bruta);
    const cod = v.codigo(Extracao.cel(linha, L.MOV_ENTRADA_CODIGO));
    const qtd = v.inteiro(Extracao.cel(linha, L.MOV_ENTRADA_QTD));
    if (iso === null || cod === null || !qtd) {
      this.diz(ERRO, 'MOVIMENTO_ILEGIVEL', 'movimento_estoque', cod ?? '',
        `entrada com data ${JSON.stringify(v.texto(bruta))}, código ${JSON.stringify(cod)} e `
        + `quantidade ${JSON.stringify(qtd)} — a linha foi descartada.`);
      return null;
    }
    return {
      metodo: L.MOV_METODO, material: cod, tipo: 'ENTRADA',
      quantidade: Math.abs(qtd), ocorrido_em: iso,
    };
  }

  /**
   * A premissa do plano §8 é que só `Ger. Apost` tem movimento. Se ela deixar de
   * valer, o estoque de Inglês e Modular sai vazio e ninguém repara — então a
   * premissa é conferida em vez de assumida.
   */
  denunciarMovimentoForaDeGerApost() {
    for (const [aba, metodo] of L.CATALOGO) {
      if (aba === L.MOV_ABA) continue;
      const achou = this.linhas(aba, L.CAT_LINHA_INICIAL).some((linha) => (
        Extracao.cel(linha, L.MOV_SAIDA_DATA) !== null
        || Extracao.cel(linha, L.MOV_ENTRADA_DATA) !== null
      ));
      if (achou) {
        this.diz(ERRO, 'MOVIMENTO_FORA_DE_GER_APOST', 'movimento_estoque', aba,
          'a aba tem células nas colunas de SAÍDAS/ENTRADAS e o extrator só lê '
          + `movimento de ${L.MOV_ABA}: o estoque de ${metodo} sairia vazio.`);
      }
    }
  }

  // -- 3. aluno, trilha e curso -------------------------------------------

  alunos(materiais) {
    const alunos = [];
    const trilha = [];
    const vistos = new Map();
    const nomes = new Map();
    const descartados = L.ALUNOS_DESCARTADOS.map(v.norm);
    let semDataInicio = 0;

    const registrar = (cod, nome, metodo, prev, statusBruto, itens) => {
      if (cod === null || nome === null) return;
      if (descartados.includes(v.norm(nome)) || descartados.includes(v.norm(cod))) {
        this.diz(AVISO, 'ALUNO_DESCARTADO', 'aluno', cod,
          `"${nome}" é registro técnico da planilha, não aluno.`);
        return;
      }
      if (vistos.has(cod)) {
        const anterior = vistos.get(cod);
        this.diz(ERRO, 'ALUNO_DUPLICADO', 'aluno', cod,
          `o código já saiu como "${anterior.nome}" (${anterior.metodo}); `
          + `"${nome}" (${metodo}) foi descartado.`);
        return;
      }
      const registro = { codigo: cod, nome, metodo };
      const status = this.status(cod, nome, statusBruto);
      if (status) registro.status = status;
      const iso = v.data(prev);
      if (iso) {
        registro.prev_conclusao_curso = iso;
        this.previsaoAtipica(cod, nome, iso, status);
      } else if (prev !== null && prev !== undefined) {
        this.diz(AVISO, 'DATA_ILEGIVEL', 'aluno', cod,
          `previsão de conclusão ${JSON.stringify(v.texto(prev))} não é data — saiu em branco.`);
      }
      semDataInicio += 1;
      vistos.set(cod, registro);
      const canonico = v.norm(nome);
      if (!nomes.has(canonico)) nomes.set(canonico, new Set());
      nomes.get(canonico).add(cod);
      alunos.push(registro);
      this.trilha(cod, metodo, itens, materiais, trilha);
    };

    for (const linha of this.linhas(L.GERENCIA_ABA, L.ALUNO_LINHA_INICIAL)) {
      registrar(
        v.codigo(Extracao.cel(linha, L.GERENCIA_CODIGO)),
        v.texto(Extracao.cel(linha, L.GERENCIA_NOME)),
        L.INTERATIVO,
        Extracao.cel(linha, L.GERENCIA_PREV),
        Extracao.cel(linha, L.GERENCIA_STATUS),
        L.GERENCIA_TRILHA.map((i) => [
          Extracao.cel(linha, i),
          Extracao.cel(linha, i + L.TRILHA_DESLOCAMENTO_ENTREGUE),
        ]),
      );
    }
    for (const linha of this.linhas(L.INGLES_ABA, L.ALUNO_LINHA_INICIAL)) {
      registrar(
        v.codigo(Extracao.cel(linha, L.INGLES_CODIGO)),
        v.texto(Extracao.cel(linha, L.INGLES_NOME)),
        L.INGLES,
        Extracao.cel(linha, L.INGLES_PREV),
        Extracao.cel(linha, L.INGLES_STATUS),
        L.INGLES_TRILHA.map((i) => [
          Extracao.cel(linha, i),
          Extracao.cel(linha, i + L.TRILHA_DESLOCAMENTO_ENTREGUE),
        ]),
      );
    }

    const cursos = new Map();
    for (const linha of this.linhas(L.MODULAR_ABA, L.ALUNO_LINHA_INICIAL)) {
      const cod = v.codigo(Extracao.cel(linha, L.MODULAR_CODIGO));
      registrar(
        cod,
        v.texto(Extracao.cel(linha, L.MODULAR_NOME)),
        L.MODULAR,
        Extracao.cel(linha, L.MODULAR_PREV),
        Extracao.cel(linha, L.MODULAR_STATUS),
        [],
      );
      // `Ger. Modular` é a fonte oficial dos alunos (resposta 9 da análise) e é
      // também a única lista de cursos do Modular com posição conhecida — a `Base
      // Modular`, que traz curso → livro → módulos, não está mapeada.
      const nomeCurso = v.texto(Extracao.cel(linha, L.MODULAR_CURSO));
      if (nomeCurso && vistos.has(cod)) {
        const canonico = v.norm(nomeCurso);
        if (!cursos.has(canonico)) cursos.set(canonico, new Map());
        const grafias = cursos.get(canonico);
        const anterior = grafias.get(nomeCurso);
        grafias.set(nomeCurso, anterior
          ? { vezes: anterior.vezes + 1, ordem: anterior.ordem }
          : { vezes: 1, ordem: grafias.size });
      }
    }

    const listaCursos = [];
    for (const canonico of [...cursos.keys()].sort()) {
      // Qual grafia vence: a MAIS FREQUENTE, e a primeira vista no desempate.
      // ⚠️ Ordem alfabética foi a primeira tentativa e o teste a derrubou: em ordem
      // de code unit "Terapeutica" vem antes de "Terapêutica", então o vencedor
      // seria SEMPRE o sem acento — a escola inteira entraria com o typo, e o card
      // 9.3 receberia a correção já aplicada ao contrário.
      const grafias = [...cursos.get(canonico).entries()]
        .sort((a, b) => (b[1].vezes - a[1].vezes) || (a[1].ordem - b[1].ordem))
        .map(([grafia, dados]) => ({ grafia, ...dados }));
      const vencedora = grafias[0].grafia;
      if (grafias.length > 1) {
        this.diz(AVISO, 'GRAFIA_DUPLICADA', 'curso', vencedora,
          'o mesmo curso aparece escrito de mais de um jeito: '
          + grafias.map((g) => `"${g.grafia}" (${g.vezes}×)`).join(', ')
          + `; valeu "${vencedora}", a mais frequente.`);
      }
      listaCursos.push({ metodo: L.MODULAR, nome: vencedora });
    }

    if (semDataInicio) {
      this.diz(AVISO, 'DATA_INICIO_AUSENTE', 'aluno', '',
        `${semDataInicio} alunos saíram sem \`data_inicio\`: a planilha não registra a `
        + 'data de matrícula, e o banco assume a data da carga.');
    }

    this.entidades.aluno = alunos;
    this.entidades.curso = listaCursos;
    this.entidades.aluno_material = trilha;
    return { alunos: vistos, nomes };
  }

  status(cod, nome, bruto) {
    const s = v.texto(bruto);
    if (s === null) return null;
    const canonico = v.norm(s).toUpperCase().replace(/ /g, '_');
    if (L.STATUS_VALIDOS.includes(canonico)) return canonico;
    // "Faltante" está na planilha e não está no check da coluna. Traduzi-lo aqui
    // seria adivinhar a transição que o card 9.3 existe para decidir.
    this.diz(AVISO, 'STATUS_DESCONHECIDO', 'aluno', cod,
      `"${nome}" está como "${s}", que não é status do sistema — saiu em branco e o `
      + 'banco assume ATIVO.');
    return null;
  }

  /** 2023, 2050 e vencidas para quem está ativo (plano §8 e análise §3, item 6). */
  previsaoAtipica(cod, nome, iso, status) {
    const ano = Number(iso.slice(0, 4));
    const base = Number(this.snapshot.slice(0, 4));
    if (ano < base - 1 || ano > base + 9) {
      this.diz(AVISO, 'PREVISAO_ATIPICA', 'aluno', cod,
        `"${nome}" tem previsão de conclusão em ${iso}.`);
    } else if (iso < this.snapshot && L.STATUS_EM_TURMA.includes(status ?? 'ATIVO')) {
      this.diz(AVISO, 'PREVISAO_ATIPICA', 'aluno', cod,
        `"${nome}" está ${status ?? 'ATIVO'} com previsão vencida em ${iso}.`);
    }
  }

  trilha(cod, metodo, itens, materiais, saida) {
    let ordem = 0;
    const usados = new Set();
    for (const [bruto, entregue] of itens) {
      const material = v.codigo(bruto);
      if (material === null) continue;
      if (!materiais.has(`${metodo}/${material}`)) {
        this.diz(ERRO, 'TRILHA_SEM_MATERIAL', 'aluno_material', cod,
          `a trilha aponta para ${metodo}/${material}, que não está no catálogo; a `
          + 'linha foi descartada.');
        continue;
      }
      if (usados.has(material)) {
        this.diz(AVISO, 'TRILHA_MATERIAL_REPETIDO', 'aluno_material', cod,
          `${metodo}/${material} aparece mais de uma vez na trilha; valeu a primeira posição.`);
        continue;
      }
      usados.add(material);
      ordem += 1;
      saida.push({
        aluno: cod,
        metodo,
        material,
        ordem,
        // Sem combo não há trilha derivada: a planilha não cadastra combo (resposta
        // 3 da análise), então toda linha é MANUAL. Marcar COMBO aqui faria
        // `tg_aluno_trilha_inicial` disputar a trilha com o arquivo.
        origem: 'MANUAL',
        entregue: v.sim(entregue),
      });
    }
  }

  // -- 4. professor, sala, bloco_horario e bloco_aluno --------------------

  turmas(alunos, nomes) {
    const professores = new Set();
    const blocos = [];
    const alocacoes = [];
    const vistos = new Set();
    for (const dia of L.DIAS) {
      if (!this.abasExistentes.has(dia)) {
        this.diz(ERRO, 'ABA_AUSENTE', 'bloco_horario', dia,
          'a aba de dia da semana não existe na planilha.');
        continue;
      }
      for (const [cabecalho, primeira, ultima, coluna] of L.BLOCOS) {
        const bruto = v.texto(this.celula(dia, cabecalho, coluna));
        if (bruto === null) continue;
        const partes = bruto.split('-').map((p) => p.trim());
        const hora = v.hora(partes[0]);
        const professor = partes.slice(1).filter(Boolean).join(' - ') || null;
        if (hora === null) {
          this.diz(ERRO, 'HORARIO_ILEGIVEL', 'bloco_horario', `${dia}/${bruto}`,
            'o cabeçalho do bloco não traz um horário reconhecível; o bloco inteiro '
            + 'foi descartado.');
          continue;
        }
        if (vistos.has(`${dia}/${hora}`)) {
          this.diz(ERRO, 'BLOCO_DUPLICADO', 'bloco_horario', `${dia}/${hora}`,
            'dois blocos da mesma aba têm o mesmo horário; valeu o primeiro.');
          continue;
        }
        vistos.add(`${dia}/${hora}`);
        if (professor) professores.add(professor);
        const metodo = Extracao.metodoDoBloco(dia, hora);
        const bloco = {
          dia_semana: L.DIA_ISO[dia], hora_inicio: hora, metodo, sala: this.sala,
        };
        if (professor) bloco.professor = professor;
        blocos.push(bloco);
        this.alocacoes(dia, hora, metodo, primeira, ultima, coluna, alunos, nomes, alocacoes);
      }
    }

    this.entidades.professor = [...professores].sort().map((nome) => ({ nome }));
    this.entidades.sala = blocos.length ? [{
      nome: this.sala, tipo: 'LABORATORIO',
      capacidade_nominal: L.SALA_LABORATORIO_CAPACIDADE,
    }] : [];
    if (blocos.length) {
      this.diz(AVISO, 'SALA_PRESUMIDA', 'sala', this.sala,
        'a aba PCS não está mapeada: a sala saiu com o nome padrão e capacidade '
        + `${L.SALA_LABORATORIO_CAPACIDADE} (os 10 PCs do laboratório, resposta 8 da `
        + 'análise). Conferir o nome real antes do dry-run.');
    }
    this.entidades.bloco_horario = blocos;
    this.entidades.bloco_aluno = alocacoes;
  }

  static metodoDoBloco(dia, hora) {
    if (L.INGLES_DIA_INTEIRO.includes(dia)) return L.INGLES;
    if (L.INGLES_BLOCOS.some(([d, h]) => d === dia && h === hora)) return L.INGLES;
    return L.INTERATIVO;
  }

  alocacoes(dia, hora, metodo, primeira, ultima, coluna, alunos, nomes, saida) {
    for (let r = primeira; r <= ultima; r += 1) {
      const bruto = v.codigo(this.celula(dia, r, coluna));
      if (bruto === null) continue;
      const [nome, prevista] = v.dataNoNome(this.celula(dia, r, coluna + L.BLOCO_NOME),
        this.snapshot);
      const cod = this.resolverCodigo(dia, hora, bruto, nome, alunos, nomes);
      if (cod === null) continue;
      const cadastro = alunos.get(cod);
      if (metodo !== cadastro.metodo) {
        this.diz(ERRO, 'METODO_DIVERGENTE', 'bloco_aluno', cod,
          `"${cadastro.nome}" é ${cadastro.metodo} no cadastro e está num bloco de `
          + `${metodo} (${dia} ${hora}); a alocação foi descartada porque o trigger de `
          + 'admissão a recusaria — e levaria a transação inteira junto.');
        continue;
      }
      const tipo = this.tipo(dia, hora, cod, this.celula(dia, r, coluna + L.BLOCO_TIPO));
      const alocacao = {
        aluno: cod, sala: this.sala, dia_semana: L.DIA_ISO[dia], hora_inicio: hora, tipo,
      };
      if (tipo === 'NOVO') {
        // `bloco_aluno_novo_ck`: NOVO sem data não entra. Descartar a alocação
        // perderia um aluno inteiro por causa de um parêntese que ninguém digitou.
        if (prevista === null) {
          this.diz(AVISO, 'NOVO_SEM_DATA', 'bloco_aluno', cod,
            `"${nome}" está como NOVO sem "(dd/mm)" no nome; assumida a data do `
            + `snapshot (${this.snapshot}), que o DDL exige.`);
        }
        alocacao.data_inicio_prevista = prevista ?? this.snapshot;
      } else if (prevista !== null) {
        this.diz(AVISO, 'DATA_NO_NOME_IGNORADA', 'bloco_aluno', cod,
          `"${nome}" traz "(dd/mm)" no nome mas está como ${tipo}; a data só vale para NOVO.`);
      }
      saida.push(alocacao);
    }
  }

  tipo(dia, hora, cod, bruto) {
    const s = v.texto(bruto);
    if (s === null) return 'PRE';
    const canonico = v.norm(s).toUpperCase();
    if (canonico in L.TIPOS_CORRIGIDOS) {
      this.diz(AVISO, 'TIPO_CORRIGIDO', 'bloco_aluno', cod,
        `"${s}" em ${dia} ${hora} foi lido como ${L.TIPOS_CORRIGIDOS[canonico]} `
        + '(lançamento incorreto, confirmado com o usuário em 30/08/2026).');
      return L.TIPOS_CORRIGIDOS[canonico];
    }
    if (L.TIPOS_ALOCACAO.includes(canonico)) return canonico;
    this.diz(AVISO, 'TIPO_DESCONHECIDO', 'bloco_aluno', cod,
      `"${s}" em ${dia} ${hora} não é tipo de presença; assumido PRE.`);
    return 'PRE';
  }

  /**
   * O código digitado na turma pode divergir do cadastro (4433 × 3605).
   *
   * A turma é digitada à mão, sem fórmula ligando à Gerência (análise §2), então o
   * código dela é a parte frágil e o nome é a confiável. Quando o código não existe
   * no cadastro e o nome bate com exatamente UM aluno, vale o do cadastro — e a
   * troca vira linha do relatório. Com mais de um homônimo ninguém decide sozinho:
   * sai AVISO e a alocação é descartada, para o card 9.3 resolver.
   */
  resolverCodigo(dia, hora, cod, nome, alunos, nomes) {
    if (alunos.has(cod)) return cod;
    const candidatos = nomes.get(v.norm(nome)) ?? new Set();
    if (candidatos.size === 1) {
      const certo = [...candidatos][0];
      this.diz(AVISO, 'CODIGO_DIVERGENTE', 'bloco_aluno', cod,
        `"${nome}" está com o código ${cod} em ${dia} ${hora} e ${certo} no cadastro; `
        + 'valeu o do cadastro.');
      return certo;
    }
    this.diz(AVISO, 'TURMA_SEM_CADASTRO', 'bloco_aluno', cod,
      `${dia} ${hora} tem o código ${cod} ("${nome}") e não há aluno com esse código no `
      + `cadastro${candidatos.size ? ` nem nome único (${candidatos.size} homônimos)` : ''}; `
      + 'a alocação foi descartada.');
    return null;
  }

  // -- 5. conferências que só a planilha responde -------------------------

  conferencias(alunos) {
    const alocados = new Map();
    for (const a of this.entidades.bloco_aluno ?? []) {
      alocados.set(a.aluno, (alocados.get(a.aluno) ?? 0) + 1);
    }
    for (const [cod, aluno] of alunos) {
      if (L.STATUS_EM_TURMA.includes(aluno.status ?? 'ATIVO') && !alocados.has(cod)) {
        this.diz(AVISO, 'ALUNO_SEM_TURMA', 'bloco_aluno', cod,
          `"${aluno.nome}" está ${aluno.status ?? 'ATIVO'} e não aparece em bloco nenhum.`);
      }
    }
    for (const cod of [...alocados.keys()].sort()) {
      if (alocados.get(cod) > 1) {
        this.diz(AVISO, 'MULTI_BLOCO', 'bloco_aluno', cod,
          `"${alunos.get(cod).nome}" está em ${alocados.get(cod)} blocos — aceleração, `
          + 'ou duplicidade de lançamento.');
      }
    }
    this.conferirEntregaContraSaida();
  }

  /**
   * A entrega hoje exige DOIS lançamentos manuais — a saída no estoque e o
   * "Entregue = SIM" na trilha (resposta 10 da análise) — e nada garante que os
   * dois aconteçam. A divergência entre eles é o que o plano §8 manda listar, e é a
   * mesma pergunta que o V13 do importador faz depois.
   *
   * É também aqui que a trilha ganha `data_entrega`: a data da entrega só existe
   * nas SAÍDAS, e sem ela o histórico entra mudo — o card 9.5 calibraria o ritmo
   * por método sobre uma trilha sem uma única data.
   */
  conferirEntregaContraSaida() {
    const saidas = new Map();
    for (const m of this.entidades.movimento_estoque ?? []) {
      if (m.tipo !== 'SAIDA') continue;
      const chave = `${m.aluno}\u0000${m.metodo}\u0000${m.material}`;
      const anterior = saidas.get(chave);
      if (anterior === undefined || m.ocorrido_em < anterior.quando) {
        saidas.set(chave, { quando: m.ocorrido_em, metodo: m.metodo, material: m.material });
      }
    }
    const semFonte = new Map();
    for (const item of this.entidades.aluno_material ?? []) {
      const chave = `${item.aluno}\u0000${item.metodo}\u0000${item.material}`;
      if (item.entregue) {
        if (saidas.has(chave)) {
          item.data_entrega = saidas.get(chave).quando;
          saidas.delete(chave);
        } else if (item.metodo === L.MOV_METODO) {
          this.diz(AVISO, 'ENTREGA_SEM_SAIDA', 'aluno_material', item.aluno,
            `${item.metodo}/${item.material} está marcado como entregue na trilha e não `
            + 'tem saída no estoque.');
        } else {
          semFonte.set(item.metodo, (semFonte.get(item.metodo) ?? 0) + 1);
        }
      } else if (saidas.has(chave)) {
        this.diz(AVISO, 'SAIDA_SEM_ENTREGA', 'aluno_material', item.aluno,
          `há saída de ${item.metodo}/${item.material} em ${saidas.get(chave).quando} e a `
          + 'trilha não diz entregue.');
        saidas.delete(chave);
      }
    }
    for (const chave of [...saidas.keys()].sort()) {
      const [aluno, metodo, material] = chave.split('\u0000');
      this.diz(AVISO, 'SAIDA_SEM_ENTREGA', 'movimento_estoque', aluno,
        `há saída de ${metodo}/${material} em ${saidas.get(chave)} e o material não está `
        + 'na trilha do aluno.');
    }
    for (const metodo of [...semFonte.keys()].sort()) {
      this.diz(AVISO, 'TRILHA_SEM_DATA', 'aluno_material', metodo,
        `${semFonte.get(metodo)} linhas de ${metodo} estão entregues e saíram SEM `
        + `\`data_entrega\`: a planilha só registra movimento de estoque em `
        + `${L.MOV_ABA} (${L.MOV_METODO}).`);
    }
  }

  // -- 6. o que não foi mapeado -------------------------------------------

  lacunas() {
    for (const { aba, entidades, porque } of L.ABAS_NAO_MAPEADAS) {
      this.diz(ERRO, 'ABA_NAO_MAPEADA', entidades.join(', '), aba,
        `${porque} As entidades ficaram FORA do arquivo — ausente é diferente de vazio, `
        + 'e é isso que impede a conferência do card 9.4 de comparar contra um buraco '
        + 'sem perceber. `--mapear` imprime as primeiras linhas da aba para fechar o '
        + 'mapa em extracao/layout.mjs.');
    }
  }

  // -- execução ------------------------------------------------------------

  executar() {
    const materiais = this.materiais();
    this.movimentos(materiais);
    const { alunos, nomes } = this.alunos(materiais);
    this.turmas(alunos, nomes);
    this.conferencias(alunos);
    this.lacunas();
    const arquivo = { snapshot_em: this.snapshot };
    for (const nome of L.ORDEM_ENTIDADES) {
      if (nome in this.entidades) arquivo[nome] = this.entidades[nome];
    }
    return { arquivo, ocorrencias: this.ocorrencias };
  }
}

export function extrair(planilha, snapshot, salaLaboratorio) {
  return new Extracao(planilha, snapshot, salaLaboratorio).executar();
}

/** Quantas linhas por entidade — o outro lado da conferência do card 9.4. */
export function totais(arquivo) {
  return Object.fromEntries(
    Object.entries(arquivo)
      .filter(([, valor]) => Array.isArray(valor))
      .map(([chave, valor]) => [chave, valor.length]),
  );
}
