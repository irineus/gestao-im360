/// Tradução `codigo` -> mensagem em tela.
///
/// Fonte dos textos: docs/design-system.md §7.1 (card 2.7), mais `PC_INEXISTENTE`
/// (card 2.9) e os três do card 3.5. O contrato do conjunto é
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
