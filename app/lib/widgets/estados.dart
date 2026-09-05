import 'package:flutter/material.dart';

import '../theme/dimensoes.dart';
import '../theme/tipografia.dart';

/// Os quatro estados obrigatórios de toda tela (docs/wireframes.md §2.3),
/// componentizados uma vez (docs/design-system.md §5.6).

/// Skeleton com a silhueta do conteúdo — nunca spinner solto, nunca tela branca.
class EstadoCarregando extends StatefulWidget {
  const EstadoCarregando({super.key, this.linhas = 6});

  final int linhas;

  @override
  State<EstadoCarregando> createState() => _EstadoCarregandoState();
}

class _EstadoCarregandoState extends State<EstadoCarregando>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: 'Carregando',
      liveRegion: true,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulso),
        child: Padding(
          padding: const EdgeInsets.all(Dim.e16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.linhas; i++)
                Container(
                  height: Dim.alturaLinha - Dim.e8,
                  margin: const EdgeInsets.only(bottom: Dim.e8),
                  decoration: BoxDecoration(
                    color: cor,
                    borderRadius: BorderRadius.circular(Dim.raio),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Diz *por que* pode estar vazio e oferece **uma** ação. Estado vazio de tabela
/// nunca é só uma tabela sem linhas. Textos por tela em design-system §7.2.
class EstadoVazio extends StatelessWidget {
  const EstadoVazio({
    super.key,
    required this.mensagem,
    this.icone = Icons.inbox_outlined,
    this.rotuloAcao,
    this.aoAgir,
  });

  final String mensagem;
  final IconData icone;
  final String? rotuloAcao;
  final VoidCallback? aoAgir;

  @override
  Widget build(BuildContext context) => _Centro(
    icone: icone,
    corIcone: Theme.of(context).colorScheme.onSurfaceVariant,
    texto: mensagem,
    rotuloAcao: rotuloAcao,
    aoAgir: aoAgir,
  );
}

/// Mensagem vinda do catálogo do card 2.7 §7.1 (já traduzida pelo `ErroApp`),
/// botão de repetir e o código técnico em apoio quando não mapeado.
/// Sem stack trace em tela — isso vai ao Sentry (card 3.12).
class EstadoErro extends StatelessWidget {
  const EstadoErro({
    super.key,
    required this.mensagem,
    this.codigoTecnico,
    this.aoRepetir,
  });

  final String mensagem;
  final String? codigoTecnico;
  final VoidCallback? aoRepetir;

  @override
  Widget build(BuildContext context) => _Centro(
    icone: Icons.error_outline,
    corIcone: Theme.of(context).colorScheme.error,
    texto: mensagem,
    apoio: codigoTecnico == null ? null : 'Código: $codigoTecnico',
    rotuloAcao: aoRepetir == null ? null : 'Tentar de novo',
    aoAgir: aoRepetir,
  );
}

const semAcessoTela = 'Você não tem acesso a esta tela.';

/// Tela inteira, sem nada da tela por trás (deep-link, permissão revogada em
/// sessão aberta). Mostra o conjunto que falta — é diagnóstico, não vazamento:
/// o usuário já pode descobrir isso chamando `tem_permissao` código a código.
class EstadoSemAcesso extends StatelessWidget {
  const EstadoSemAcesso({
    super.key,
    this.faltando = const {},
    this.texto = semAcessoTela,
    this.rotuloAcao,
    this.aoAgir,
  });

  final Set<String> faltando;

  /// O padrão fala de **tela**. Dentro de uma aba isso é falso — a tela abriu,
  /// e o que não abre é aquele pedaço —, então quem o usa numa aba passa o
  /// texto daquele pedaço (achado da revisão da fase 05).
  final String texto;

  final String? rotuloAcao;
  final VoidCallback? aoAgir;

  @override
  Widget build(BuildContext context) => _Centro(
    icone: Icons.lock_outline,
    corIcone: Theme.of(context).colorScheme.onSurfaceVariant,
    texto: texto,
    apoio: faltando.isEmpty
        ? null
        : 'Falta: ${(faltando.toList()..sort()).join(', ')}',
    rotuloAcao: rotuloAcao,
    aoAgir: aoAgir,
  );
}

class _Centro extends StatelessWidget {
  const _Centro({
    required this.icone,
    required this.corIcone,
    required this.texto,
    this.apoio,
    this.rotuloAcao,
    this.aoAgir,
  });

  final IconData icone;
  final Color corIcone;
  final String texto;
  final String? apoio;
  final String? rotuloAcao;
  final VoidCallback? aoAgir;

  @override
  Widget build(BuildContext context) {
    // ⚠️ `SingleChildScrollView` desde 04/09/2026 (card 6.8), e não é zelo: os
    //    quatro estados moram em `Expanded` dentro de PAINÉIS — o de
    //    movimentações (6.7) e o de pedido (6.8) ocupam 2/5 da altura —, e ali o
    //    conjunto ícone + frase + código + botão não cabe. Sem o scroll o
    //    Flutter desenha as listras amarelas de overflow POR CIMA do botão
    //    "Tentar de novo", e o estado de erro deixa de ter saída justamente na
    //    tela em que a pessoa precisa dela. Medido no `tela_compras_test`, com
    //    o painel de itens falhando: `A RenderFlex overflowed by 40 pixels`.
    //    Continua CENTRADO: o scroll só entra quando não cabe.
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Dim.larguraFormularioMax),
          child: Padding(
            padding: const EdgeInsets.all(Dim.e24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 40, color: corIcone),
                const SizedBox(height: Dim.e16),
                Text(
                  texto,
                  style: Tipografia.corpo,
                  textAlign: TextAlign.center,
                ),
                if (apoio != null) ...[
                  const SizedBox(height: Dim.e8),
                  Text(
                    apoio!,
                    style: Tipografia.apoio.copyWith(color: corIcone),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (rotuloAcao != null && aoAgir != null) ...[
                  const SizedBox(height: Dim.e24),
                  FilledButton(onPressed: aoAgir, child: Text(rotuloAcao!)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
