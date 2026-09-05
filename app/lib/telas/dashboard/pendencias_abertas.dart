import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../dashboard/dashboard.dart';
import '../../pendencias/pendencias.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../rotas/rotas.dart';
import '../../theme/cores.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/estados.dart';

/// A região "Pendências abertas" do wireframe §5: quantas há em cada severidade
/// e o caminho para a central (card 5.8).
///
/// **Não abre consulta nenhuma:** `pendenciasProvider` já é observado pelo shell
/// em toda tela, para o contador do menu — este bloco só conta o que está em
/// memória. É o ajuste que o card 5.8 deixou escrito para o 5.9, e é o que faz
/// `pendencias.ler` ter um consumidor no conjunto mínimo da rota do dashboard.
///
/// ⚠️ **Erro aqui não vira zero.** O contador do menu mostra zero quando a
/// leitura falha, de propósito (card 5.8): é um aviso de canto de tela, e um "!"
/// por falha de rede mandaria a pessoa abrir a central para não achar nada. Uma
/// **região do dashboard é diferente** — ela é um número reportado, e "0 ALTA"
/// por falha de leitura é exatamente a família de falha calada que este projeto
/// cataloga: a direção lê "está tudo em ordem" quando ninguém sabe.
class PendenciasAbertas extends ConsumerWidget {
  const PendenciasAbertas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final abertas = ref.watch(pendenciasProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pendências abertas',
                overflow: TextOverflow.ellipsis,
                style: Tipografia.subtitulo,
              ),
            ),
            // A rota de Pendências exige só `pendencias.ler`, que o conjunto
            // mínimo do dashboard já contém — este atalho, ao contrário do de
            // Turmas, nunca leva a "Sem acesso".
            TextButton(
              onPressed: () => context.go(_rotaPendencias.caminho),
              child: const Text('Abrir a central'),
            ),
          ],
        ),
        const SizedBox(height: Dim.e4),
        // ⚠️ A pergunta é `hasError`, e **não** um `case AsyncError()`.
        // O Riverpod 3 **repete sozinho** o provider que falhou, com espera
        // crescente: o estado passa por `AsyncError` e volta a `AsyncLoading`
        // logo em seguida, guardando o erro anterior. Casar pela classe faria a
        // mensagem piscar e a região terminar em "Carregando…" para sempre —
        // medido na bancada deste card, com o teste vermelho antes da correção.
        // ⚠️ Era texto: "Carregando…" no lugar do esqueleto que o §5.6 pede,
        // e a mensagem de erro **sem "Tentar de novo"** — a região de vagas da
        // mesma tela já fazia os dois. Sem a saída, a única forma de repetir a
        // leitura era recarregar a página (item D1).
        if (abertas.hasError)
          EstadoErro(
            mensagem: erroPendenciasDashboard,
            aoRepetir: ref.read(versaoPendenciasProvider.notifier).incrementar,
          )
        else if (!abertas.hasValue)
          const EstadoCarregando(linhas: 2)
        else
          _Contagens(
            totais: totaisPorSeveridade(abertas.requireValue),
            // Toda célula/número do dashboard é atalho (wireframes §5 e §3.3):
            // tocar "ALTA 3" abre a central **já filtrada** por ALTA. Sem isso
            // o número dizia quantas são e mandava procurá-las de novo.
            aoTocar: (severidade) {
              ref
                  .read(filtroPendenciasProvider.notifier)
                  .definir(FiltroPendencias(severidade: severidade));
              context.go(_rotaPendencias.caminho);
            },
          ),
      ],
    );
  }
}

/// O texto que substitui os números quando a leitura falha — nunca um zero.
const erroPendenciasDashboard =
    'Não foi possível ler as pendências agora. Abra a central para conferir.';

class _Contagens extends StatelessWidget {
  const _Contagens({required this.totais, required this.aoTocar});

  final List<TotalSeveridade> totais;
  final void Function(String severidade) aoTocar;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    final escuro = tema.brightness == Brightness.dark;

    Color cor(String severidade) => switch (severidade) {
      'ALTA' => cores.error,
      'MEDIA' => escuro ? Cores.atencaoEscuro : Cores.atencao,
      _ => cores.onSurfaceVariant,
    };

    return Wrap(
      spacing: Dim.e24,
      runSpacing: Dim.e8,
      children: [
        for (final total in totais)
          Semantics(
            button: true,
            label:
                '${total.qtd} '
                '${total.qtd == 1 ? 'pendência' : 'pendências'} '
                'de severidade ${total.rotulo.toLowerCase()} em aberto',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => aoTocar(total.severidade),
              borderRadius: BorderRadius.circular(Dim.raio),
              child: ConstrainedBox(
                // Alvo de toque do §8.4 — o número é botão, e botão de 16 px
                // não se acerta com o polegar.
                constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A severidade é ícone + texto, e não um terceiro
                    // vocabulário de badge (card 5.8, decisão 5): o sistema já
                    // usa badge preenchido para status do aluno e de contorno
                    // para tipo na turma.
                    Icon(
                      Icons.flag_outlined,
                      size: 14,
                      color: cor(total.severidade),
                    ),
                    const SizedBox(width: Dim.e4),
                    Text(
                      total.rotulo,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: Dim.e8),
                    Text(
                      '${total.qtd}',
                      style: Tipografia.numero(Tipografia.rotulo)
                          .copyWith(color: cor(total.severidade)),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Rota get _rotaPendencias =>
    rotasAplicacao.firstWhere((rota) => rota.id == 'pendencias');
