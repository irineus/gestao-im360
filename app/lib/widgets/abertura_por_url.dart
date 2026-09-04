import 'package:flutter/widgets.dart';

/// Abre **uma vez** o detalhe que a URL pediu.
///
/// Os atalhos da central de pendências chegam às telas de destino como
/// parâmetro de consulta (`/turmas?bloco=…`, `/salas?pc=…`,
/// `/materiais?material=…`, wireframe §14.3). O alvo, porém, só existe depois
/// que a consulta da tela volta — e o `build` roda várias vezes até lá, e mais
/// algumas depois. Sem guarda, o painel reabriria a cada rebuild, inclusive
/// depois de a pessoa o fechar.
///
/// Duas regras, e as duas importam: **uma vez só** (o marcador é por estado do
/// widget, não por frame) e **depois do frame** — abrir um diálogo durante o
/// `build` é erro do framework.
mixin AberturaPorUrl<T extends StatefulWidget> on State<T> {
  bool _abriu = false;

  /// Chame no `build`. [alvo] nulo = a tela ainda não sabe o que abrir (a
  /// consulta não voltou, ou o id da URL não existe mais).
  void abrirUmaVez<I extends Object>(I? alvo, void Function(I alvo) acao) {
    if (_abriu || alvo == null) return;
    _abriu = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) acao(alvo);
    });
  }

  /// Depois de uma navegação nova para a mesma tela com outro id, o alvo volta
  /// a valer. Chamar em `didUpdateWidget` quando o parâmetro mudou.
  void reabrirNaProxima() => _abriu = false;
}
