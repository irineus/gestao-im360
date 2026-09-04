/// Tradução `codigo` -> mensagem em tela.
///
/// Fonte dos textos: docs/design-system.md §7.1 (card 2.7), mais `PC_INEXISTENTE`
/// (card 2.9), os três do card 3.5, `ALUNO_INEXISTENTE` (card 4.2),
/// `PC_COM_HISTORICO` (card 4.3), `BLOCO_COM_ALOCACAO` (card 5.1), os três do
/// card 6.1 (trilha e estoque), `MATERIAL_JA_NA_TRILHA` (card 6.2),
/// `MOVIMENTO_INEXISTENTE` (card 6.3) e os dez do card 6.5 (pedidos de compra,
/// recebimento e ajuste de estoque). O contrato do conjunto é
/// `test/fixtures/codigos_erro.txt`, na raiz do repositório.
///
/// O app trata SEMPRE pelo código, nunca pelo texto do banco (card 2.2 §1.2):
/// o texto pode mudar numa migração; o código é estável.
library;

abstract final class CatalogoErros {
  /// O caso não mapeado sempre exibe o código — é o que a direção manda ao
  /// suporte (docs/design-system.md §7.1).
  static const naoMapeado =
      'Não foi possível concluir. Tente de novo; se continuar, avise a direção '
      '(código {codigo}).';

  static const mensagens = <String, String>{
    // --- card 2.2 §12
    'SEM_PERMISSAO': 'Você não tem permissão para esta ação.',
    'TRANSICAO_INVALIDA':
        'Essa mudança de status não é permitida a partir do status atual.',
    'FORMATURA_SEM_CERTIFICADO':
        'Para formar o aluno, o checklist do certificado precisa estar como '
        'ENTREGUE — ou a direção pode confirmar mesmo assim.',
    'MOTIVO_OBRIGATORIO': 'Informe o motivo para continuar.',
    'ALUNO_INATIVO': 'Esta ação só vale para aluno ATIVO ou ACELERAR.',
    'METODO_INCOMPATIVEL': 'O método do aluno não é o método desta turma.',
    'BLOCO_LOTADO':
        'Esta turma está lotada. Escolha outro horário ou verifique a '
        'capacidade da sala.',
    'DATA_PREVISTA_OBRIGATORIA':
        'Aluno NOVO precisa de data prevista de início.',
    'TRILHA_JA_EXISTE':
        'Este aluno já tem trilha. Para gerar de novo, use a opção de '
        'substituir.',
    'TRILHA_COM_ENTREGA':
        'A trilha já tem apostila entregue e não pode ser regenerada. Edite a '
        'trilha em vez de substituí-la.',
    'ALUNO_SEM_COMBO':
        'O aluno não tem combo definido. Informe o combo nos dados do aluno.',
    'ITEM_JA_ENTREGUE':
        'Apostila já entregue não pode ser alterada na trilha. Para corrigir, '
        'estorne a entrega.',
    'TRILHA_EM_FIM':
        'A trilha deste aluno está concluída — não há apostila pendente para '
        'entregar.',
    'MATERIAL_FORA_DA_TRILHA':
        'Esta apostila não está pendente na trilha do aluno.',
    'MOVIMENTO_JA_ESTORNADO': 'Este movimento já foi estornado.',
    'MOVIMENTO_NAO_ESTORNAVEL': 'Este movimento não pode ser estornado.',
    'PEDIDO_NAO_RECEBIVEL': 'Este pedido não está aguardando recebimento.',
    'RECEBIMENTO_EXCEDE_PEDIDO':
        'Quantidade acima do pedido — o recebimento com excedente requer a '
        'direção.',
    'PARAMETRO_AUSENTE':
        'Um parâmetro do sistema está sem valor: {chave}. Avise a direção '
        '(tela de Administração → Parâmetros).',

    // --- card 2.5 (virada REP)
    'REP_JA_CONTINUO': 'Este aluno já está como REP contínuo.',
    'REP_NAO_CONTINUO': 'Este aluno não está como REP contínuo.',

    // --- card 2.9 (credenciais de PC)
    // Vale também para PC de outra unidade: quem não pode ver não descobre que
    // existe (docs/politica-credenciais-pcs.md §4).
    'PC_INEXISTENTE': 'Este computador não foi encontrado.',

    // --- card 4.2 (transições de status do aluno)
    // Vale também para aluno de outra unidade, pela mesma razão do
    // PC_INEXISTENTE acima. Não se confunde com ALUNO_INATIVO: aquele fala de
    // um aluno que existe e está no status errado para a ação.
    'ALUNO_INEXISTENTE': 'Este aluno não foi encontrado.',

    // --- card 4.3 (guarda de exclusão de PC)
    // A cascata das FKs apagava manutenção e log de credencial junto com o PC,
    // sem passar pela RLS de nenhuma das duas. A mensagem diz a saída, que é a
    // que a tela do card 4.5 oferece: desativar em vez de excluir.
    'PC_COM_HISTORICO':
        'Este computador tem histórico e não pode ser excluído. Marque-o '
        'como desativado.',

    // --- card 5.1 (guarda de exclusão de bloco de horário)
    // Mesma família do PC_COM_HISTORICO: `bloco_aluno.bloco_id` é
    // `on delete cascade` e a tabela não tem política de delete para ninguém,
    // então apagar o bloco levava junto, em silêncio, quem esteve na turma. A
    // mensagem diz a saída, que é a mesma que a grade do card 5.6 oferece.
    'BLOCO_COM_ALOCACAO':
        'Este bloco tem histórico de alunos e não pode ser excluído. '
        'Desative-o.',

    // --- card 5.3 (admissão, remoção e reposições)
    // BLOCO_INEXISTENTE vale também para bloco de outra unidade, pela mesma
    // razão do PC_INEXISTENTE: quem não pode ver não descobre que existe. É o
    // que o trigger de admissão devolve quando a capacidade vem nula — sem ele,
    // comparar com nulo deixaria a lotação passar em silêncio.
    'BLOCO_INEXISTENTE': 'Este bloco de horário não foi encontrado.',
    'ALOCACAO_INEXISTENTE': 'Este aluno não está nesta turma.',
    'REPOSICAO_INEXISTENTE': 'Esta reposição não foi encontrada.',
    'REPOSICAO_NAO_PREVISTA':
        'Esta reposição já foi registrada ou cancelada. Atualize a tela para '
        'ver a situação atual.',

    // --- card 5.5 (fechamento humano de pendência)
    // PENDENCIA_INEXISTENTE vale também para pendência de outra unidade, pela
    // mesma razão de PC_INEXISTENTE e BLOCO_INEXISTENTE: quem não pode ver não
    // descobre que existe.
    'PENDENCIA_INEXISTENTE': 'Esta pendência não foi encontrada.',
    'PENDENCIA_JA_RESOLVIDA':
        'Esta pendência já foi resolvida. Atualize a tela para ver a situação '
        'atual.',
    'RESOLUCAO_INVALIDA':
        'Escolha resolver ou ignorar a pendência para continuar.',

    // --- card 6.1 (trilha e estoque)
    // COMPOSICAO_METODO_DIVERGENTE é código NOVO, e não METODO_INCOMPATIVEL:
    // aquele compara o método do ALUNO com o da TURMA, e a mensagem dele seria
    // falsa em toda palavra aqui. A tela do card 4.4 já filtra os candidatos
    // pelo método do pai, então esta mensagem só aparece quando alguém chegar à
    // tabela por outro caminho — e é justamente aí que ela precisa ser clara.
    'COMPOSICAO_METODO_DIVERGENTE':
        'Este item é de outro método. A composição do catálogo não pode '
        'misturar métodos.',
    'PEDIDO_NAO_RASCUNHO':
        'Só dá para remover item de pedido em rascunho. Cancele o pedido ou '
        'ajuste as quantidades.',
    // Mesma família do PC_COM_HISTORICO e do BLOCO_COM_ALOCACAO, mas aqui a
    // recusa é total: movimento de estoque não se altera nem se apaga, e a
    // correção é sempre um movimento novo.
    'MOVIMENTO_IMUTAVEL':
        'Movimento de estoque não pode ser alterado nem apagado. Para corrigir, '
        'lance um estorno.',

    // --- card 6.2 (edição da trilha)
    // Sem este código a segunda inclusão da mesma apostila chegaria à tela como
    // um erro cru da unique — o que o card 2.2 §1.2 proíbe.
    'MATERIAL_JA_NA_TRILHA':
        'Esta apostila já está na trilha do aluno. Para mudá-la de lugar, use a '
        'reordenação.',

    // --- card 6.3 (entrega e estorno)
    // Vale também para movimento de outra unidade, pela mesma razão do
    // PC_INEXISTENTE. Não se confunde com MOVIMENTO_NAO_ESTORNAVEL: aquele fala
    // de um movimento que existe e é do tipo errado (ENTRADA, AJUSTE, ESTORNO).
    'MOVIMENTO_INEXISTENTE': 'Este movimento de estoque não foi encontrado.',

    // --- card 6.5 (pedidos de compra, recebimento e ajuste de estoque)
    // Os dois primeiros valem também para pedido e material de OUTRA unidade,
    // pela mesma razão do PC_INEXISTENTE: quem não pode ver não descobre que
    // existe.
    'PEDIDO_INEXISTENTE': 'Este pedido de compra não foi encontrado.',
    'MATERIAL_INEXISTENTE': 'Esta apostila não foi encontrada.',
    // Três estados, três frases: reaproveitar PEDIDO_NAO_RECEBIVEL nos outros
    // dois mandaria a pessoa procurar o problema no lugar errado.
    'PEDIDO_NAO_ENVIAVEL':
        'Só pedido em rascunho pode ser enviado. Este já saiu do rascunho.',
    'PEDIDO_NAO_CANCELAVEL':
        'Este pedido não pode ser cancelado. Pedido já recebido se corrige '
        'estornando as entradas de estoque.',
    'PEDIDO_SEM_ITEM': 'Informe ao menos um item para o pedido.',
    'MATERIAL_JA_NO_PEDIDO':
        'O mesmo material aparece mais de uma vez no pedido. Some as '
        'quantidades numa linha só.',
    'ITEM_FORA_DO_PEDIDO':
        'Este item não pertence ao pedido que está sendo recebido.',
    'QUANTIDADE_INVALIDA': 'Informe uma quantidade válida.',
    'ESTORNO_SINAL_INVALIDO':
        'O estorno tem de devolver exatamente o que o movimento original '
        'movimentou.',
    'SALDO_INSUFICIENTE':
        'O ajuste deixaria o estoque negativo. Confira a contagem.',

    // --- card 3.5 (espelho auth.users -> usuario)
    'USUARIO_SEM_UNIDADE':
        'Não deu para saber em que unidade cadastrar esta pessoa. Informe a '
        'unidade no convite.',
    'USUARIO_SEM_EMAIL': 'Não é possível criar um usuário sem e-mail.',
    'EMAIL_IMUTAVEL':
        'O e-mail é o endereço de acesso e só muda pelo próprio login da '
        'pessoa.',
  };

  /// Mensagem para o código, com as marcações `{...}` substituídas por
  /// [valores]. Código desconhecido (ou nulo) cai em [naoMapeado], que sempre
  /// exibe o próprio código.
  static String mensagem(
    String? codigo, {
    Map<String, String> valores = const {},
  }) {
    final modelo = mensagens[codigo] ?? naoMapeado;
    final todos = {'codigo': codigo ?? '?', ...valores};
    return todos.entries.fold(
      modelo,
      (texto, e) => texto.replaceAll('{${e.key}}', e.value),
    );
  }

  /// Verdadeiro quando o código tem tradução própria — o oposto do fallback.
  static bool mapeado(String? codigo) => mensagens.containsKey(codigo);
}
