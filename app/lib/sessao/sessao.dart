import 'package:flutter/foundation.dart';

/// A sessão montada depois do login: quem é, em que unidade, e o que pode.
///
/// Ordem de carga fixada em docs/acesso-autenticacao.md §4:
///   1. a própria linha de `usuario` (funciona para todo perfil por causa do
///      `or id = auth.uid()` da política do card 3.4);
///   2. `rpc('fn_minhas_permissoes')`;
///   3. a unidade.
@immutable
class Sessao {
  const Sessao({
    required this.usuarioId,
    required this.nome,
    required this.email,
    required this.unidadeId,
    required this.permissoes,
    this.unidadeNome,
  });

  final String usuarioId;
  final String nome;
  final String email;
  final String unidadeId;

  /// Nome da unidade para o cabeçalho. Nulo quando o perfil não tem
  /// `unidades.ler` — o cabeçalho degrada, o app funciona.
  final String? unidadeNome;

  final Set<String> permissoes;

  bool pode(String codigo) => permissoes.contains(codigo);
}

/// Estado da sessão. É `sealed` de propósito: cada modo de falha tem uma tela,
/// e o `switch` reprova na compilação quando um modo novo aparecer.
@immutable
sealed class EstadoSessao {
  const EstadoSessao();
}

/// Ainda decidindo — restaurando sessão salva ou carregando o usuário.
class SessaoCarregando extends EstadoSessao {
  const SessaoCarregando();
}

/// Sem token: a tela de login.
class SessaoDeslogada extends EstadoSessao {
  const SessaoDeslogada({this.aviso});

  /// Mensagem a exibir no login depois de um `sair` provocado por erro.
  final String? aviso;
}

/// **Autenticado e sem linha em `usuario`** — o achado que este card existe para
/// não deixar virar tela muda (docs/acesso-autenticacao.md §4).
///
/// O Auth não sabe nada sobre o espelho: a pessoa consegue token. Sem espelho,
/// `fn_unidade_atual()` devolve `null`, toda política nega e o app abriria
/// **todas as telas vazias, sem erro nenhum**.
///
/// ⚠️ O app **não distingue** este caso do usuário **desativado**: `tem_permissao`
/// e `fn_unidade_atual` exigem `usuario.ativo` (card 3.4), então o desativado
/// também lê zero linhas da própria linha de `usuario`. Por isso o texto cobre
/// os dois — dizer "ainda não foi liberado" a quem foi desligado seria mentira
/// com cara de bug.
class SessaoSemEspelho extends EstadoSessao {
  const SessaoSemEspelho(this.email);

  final String email;
}

/// Autenticado, com espelho, e **sem nenhuma permissão** — convidado antes de
/// alguém lhe atribuir perfil (docs/acesso-autenticacao.md §3.1).
///
/// Sem este estado o app abriria um shell sem nenhum item de menu: o mesmo
/// silêncio de novo, com outra roupa.
class SessaoSemPerfil extends EstadoSessao {
  const SessaoSemPerfil(this.sessao);

  final Sessao sessao;
}

/// A carga da sessão falhou (rede, RLS inesperada). Distinta de deslogado:
/// mandar de volta ao login faria a pessoa digitar a senha para reencontrar o
/// mesmo erro.
class SessaoErro extends EstadoSessao {
  const SessaoErro(this.mensagem, {this.codigo});

  final String mensagem;
  final String? codigo;
}

/// Sessão pronta.
class SessaoAtiva extends EstadoSessao {
  const SessaoAtiva(this.sessao);

  final Sessao sessao;
}

/// Permissões do estado atual — vazio quando não há sessão pronta.
Set<String> permissoesDe(EstadoSessao estado) => switch (estado) {
  SessaoAtiva(:final sessao) => sessao.permissoes,
  _ => const <String>{},
};
