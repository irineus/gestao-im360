import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../erros/erro_app.dart';
import '../../estoque/estoque.dart';
import '../../estoque/estoque_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../util/datas.dart';
import '../../widgets/barra_filtros.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';

/// O painel "Movimentações INT-04" do wireframe §9 (card 6.7): a história de um
/// material, com filtro de período e de tipo.
///
/// ⚠️ **É conferência, e por isso não tem botão de estorno.** O estorno de uma
/// SAÍDA mora na aba Trilha do aluno (wireframe §9, última linha; card 6.6), que
/// é onde há contexto — quem recebeu, qual apostila, o que volta a ficar
/// pendente. Um "Estornar" solto aqui desfaria a entrega de alguém a partir de
/// uma linha que não diz de quem ela é quando o leitor não tem `alunos.ler`.
///
/// ⚠️ **A soma das linhas NÃO é recalculada em Dart.** O saldo do cabeçalho é o
/// da própria `v_estoque_atual` (card 6.4) — com o filtro de período ligado, uma
/// soma local mostraria um pedaço da história com cara de saldo.
class PainelMovimentos extends ConsumerWidget {
  const PainelMovimentos({
    super.key,
    required this.material,
    required this.aoEditar,
    required this.aoAjustar,
    this.aoFechar,
  });

  final MaterialEstoque material;

  /// Editar o cadastro do material (`materiais.editar`) — o `[+ Novo material]
  /// / edição` do wireframe §9.
  final VoidCallback aoEditar;

  /// Lançar AJUSTE (`estoque.ajustar`).
  final VoidCallback aoAjustar;

  /// Fechar o painel. Nulo no mobile, onde quem fecha é o próprio diálogo.
  final VoidCallback? aoFechar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final filtro = ref.watch(filtroMovimentoProvider);
    final movimentos = ref.watch(
      movimentosDoMaterialProvider(material.materialId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Dim.e16, Dim.e12, Dim.e16, Dim.e8),
          // ⚠️ Em 390 px o `Wrap` das ações não cabia ao lado do título e a
          // `Row` estourava 80 px à direita: `Row` dá largura infinita ao filho
          // não flexível, então o `Wrap` não tinha onde quebrar. No celular
          // título e ações empilham (item H6).
          child: CabecalhoDePainel(
            titulo: TituloSecao(
              texto: 'Movimentações ${material.codigo}',
              apoio:
                  '${material.nome} · saldo ${material.saldo} · mínimo '
                  '${material.estoqueMinimo}',
              maxLinhasApoio: 2,
            ),
            acoes: Wrap(
              spacing: Dim.e8,
              children: [
                // ⚠️ **Sem guarda de permissão, e é a exceção da regra do
                // §5.7 — de propósito.** O botão não escreve nada: ele abre o
                // cadastro do material, que quem tem `materiais.ler` sempre
                // pôde ver (card 4.4, tocando a linha). Guardá-lo por
                // `materiais.editar` tiraria a leitura de quem já a tinha,
                // porque desde este card a linha abre o PAINEL. Quem decide
                // se há "Salvar" é o próprio `FormularioMaterial`, pela
                // permissão — e o rótulo diz de antemão o que vai acontecer.
                BotaoAcao(
                  rotulo:
                      ref.watch(permissoesProvider).contains('materiais.editar')
                      ? 'Editar material'
                      : 'Ver cadastro',
                  nivel: NivelBotao.secundario,
                  aoTocar: aoEditar,
                ),
                BotaoAcao(
                  rotulo: 'Ajustar',
                  icone: Icons.tune,
                  exigePermissao: 'estoque.ajustar',
                  aoTocar: aoAjustar,
                ),
                if (aoFechar != null)
                  IconButton(
                    tooltip: 'Fechar movimentações',
                    icon: const Icon(Icons.close),
                    onPressed: aoFechar,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Dim.e16),
          child: _FiltrosMovimento(filtro: filtro),
        ),
        const SizedBox(height: Dim.e8),
        Expanded(
          child: movimentos.when(
            loading: () => const EstadoCarregando(linhas: 4),
            error: (erro, _) {
              final traduzido = erro is ErroApp ? erro : traduzirErro(erro);
              return EstadoErro(
                mensagem: traduzido.mensagem,
                codigoTecnico: traduzido.traduzido ? null : traduzido.codigo,
                aoRepetir: ref.read(versaoEstoqueProvider.notifier).incrementar,
              );
            },
            data: (todos) {
              final linhas = filtrarMovimentos(
                todos,
                filtro,
                hoje: hojeSaoPaulo(),
              );
              if (linhas.isEmpty) {
                return todos.isEmpty
                    // O texto do design-system §7.2 diz ONDE se lança entrada,
                    // porque é a pergunta que um painel vazio produz.
                    ? const EstadoVazio(
                        mensagem: vazioMovimentos,
                        icone: Icons.inventory_2_outlined,
                      )
                    : EstadoVazio(
                        mensagem: vazioMovimentosFiltro,
                        icone: Icons.filter_alt_off_outlined,
                        rotuloAcao: 'Limpar filtros',
                        aoAgir: ref
                            .read(filtroMovimentoProvider.notifier)
                            .limpar,
                      );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  Dim.e16,
                  0,
                  Dim.e16,
                  Dim.e16,
                ),
                itemCount: linhas.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: cores.outlineVariant),
                itemBuilder: (context, i) => _LinhaMovimento(mov: linhas[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Período e tipo (wireframe §9). Dois `DropdownMenu` compactos, como o §5.3
/// pede — e nenhum deles vira `where` na consulta: a view devolve a história
/// inteira e quem esconde é a tela (card 2.3 §2.3(h)).
class _FiltrosMovimento extends ConsumerWidget {
  const _FiltrosMovimento({required this.filtro});

  final FiltroMovimento filtro;

  static const _tipos = ['ENTRADA', 'SAIDA', 'AJUSTE', 'ESTORNO'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controlador = ref.read(filtroMovimentoProvider.notifier);
    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FiltroSuspenso<PeriodoMovimento>(
          key: ValueKey('periodo-${filtro.periodo}'),
          rotulo: 'Período',
          largura: 200,
          selecao: filtro.periodo,
          entradas: [
            for (final p in PeriodoMovimento.values)
              DropdownMenuEntry(value: p, label: rotuloPeriodo(p)),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(periodo: valor ?? PeriodoMovimento.todos),
          ),
        ),
        FiltroSuspenso<String>(
          key: ValueKey('tipo-${filtro.tipo}'),
          rotulo: 'Tipo',
          largura: 180,
          selecao: filtro.tipo ?? '',
          entradas: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final t in _tipos) DropdownMenuEntry(value: t, label: t),
          ],
          aoSelecionar: (valor) => controlador.definir(
            filtro.copiar(
              tipo: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Uma movimentação: data, tipo, quantidade com sinal, origem e autor.
///
/// ⚠️ Cor não é portadora única (design-system §8.2): o sinal está escrito
/// (`+10`, `−1`) e o tipo aparece por extenso — quem só enxergasse a cor do
/// número leria uma entrada como saída.
class _LinhaMovimento extends StatelessWidget {
  const _LinhaMovimento({required this.mov});

  final MovimentoMaterial mov;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final autor = autorDoMovimento(mov);
    final origem = origemDoMovimento(mov);
    return Semantics(
      label: [
        formatarData(mov.ocorridoEm),
        mov.tipo,
        mov.quantidadeFormatada,
        origem,
        ?autor,
      ].join(', '),
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: Dim.alvoMobile),
        padding: const EdgeInsets.symmetric(vertical: Dim.e8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                formatarData(mov.ocorridoEm),
                style: Tipografia.numero(Tipografia.corpoTabela),
              ),
            ),
            SizedBox(
              width: 84,
              child: Text(mov.tipo, style: Tipografia.corpoTabela),
            ),
            SizedBox(
              width: 56,
              child: Text(
                mov.quantidadeFormatada,
                textAlign: TextAlign.end,
                style: Tipografia.numero(Tipografia.corpoTabela).copyWith(
                  color: mov.quantidade < 0 ? cores.error : cores.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: Dim.e12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(origem, style: Tipografia.corpoTabela),
                  if (mov.observacao != null && mov.observacao!.isNotEmpty)
                    Text(
                      mov.observacao!,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  // "por Débora" só aparece quando o nome é legível: sem
                  // `admin.ler` a política de `usuario` devolve nulo, e "por —"
                  // seria a mentira que o card 4.6 recusou (pendência 9.13).
                  if (autor != null)
                    Text(
                      autor,
                      style: Tipografia.apoio.copyWith(
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ajuste de estoque — a única escrita desta tela
// ---------------------------------------------------------------------------

/// `[Ajustar]` do wireframe §9: lança um AJUSTE por `fn_ajustar_estoque`
/// (card 6.5), com **motivo obrigatório**.
///
/// ⚠️ **A tela não pré-verifica saldo** (card 2.6 decisão 2): quem recusa o
/// ajuste que deixaria o estoque negativo é a função, dentro da transação e com
/// o advisory lock por material — e a recusa chega como `SALDO_INSUFICIENTE`,
/// traduzido pelo catálogo do card 2.7 §7.1. Conferir aqui seria a terceira
/// implementação da soma, e ela erraria justamente na corrida de dois ajustes
/// simultâneos, que é onde o banco acerta.
class FormularioAjusteEstoque extends ConsumerStatefulWidget {
  const FormularioAjusteEstoque({super.key, required this.material});

  final MaterialEstoque material;

  @override
  ConsumerState<FormularioAjusteEstoque> createState() =>
      _FormularioAjusteEstoqueState();
}

class _FormularioAjusteEstoqueState
    extends ConsumerState<FormularioAjusteEstoque> {
  final _chave = GlobalKey<FormState>();
  final _quantidade = TextEditingController();
  final _motivo = TextEditingController();
  bool _realceMotivo = false;
  bool _realceQuantidade = false;

  @override
  void dispose() {
    _quantidade.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Ajustar estoque',
    rotuloSalvar: 'Lançar ajuste',
    chave: _chave,
    aviso: avisoAjuste,
    campos: [
      Text(
        '${widget.material.rotulo} · saldo atual '
        '${widget.material.saldo}',
        style: Tipografia.corpoTabela,
      ),
      const SizedBox(height: Dim.e12),
      TextFormField(
        controller: _quantidade,
        style: Tipografia.corpo,
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-−0-9]')),
        ],
        decoration: InputDecoration(
          labelText: 'Quantidade (com sinal) *',
          helperText: 'Ex.: 5 acrescenta cinco; -5 tira cinco.',
          errorText: _realceQuantidade
              ? 'Informe uma quantidade válida.'
              : null,
        ),
        validator: validarInteiroComSinalNaoZero,
      ),
      const SizedBox(height: Dim.e12),
      TextFormField(
        controller: _motivo,
        style: Tipografia.corpo,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Motivo *',
          helperText: 'Fica no histórico do material, ao lado do movimento.',
          errorText: _realceMotivo ? 'Informe o motivo para continuar.' : null,
        ),
        validator: validarObrigatorio,
      ),
      const SizedBox(height: Dim.e12),
      const AvisoTonal(mensagem: avisoAjusteNaoEEntrada),
    ],
    aoErro: (erro) => setState(() {
      _realceMotivo = erro.codigo == 'MOTIVO_OBRIGATORIO';
      _realceQuantidade = erro.codigo == 'QUANTIDADE_INVALIDA';
    }),
    aoSalvar: () async {
      await ref
          .read(estoqueRepositorioProvider)
          .ajustar(
            widget.material.materialId,
            quantidade: lerInteiroComSinal(_quantidade.text)!,
            motivo: _motivo.text,
          );
      ref.read(versaoEstoqueProvider.notifier).incrementar();
      return 'Ajuste lançado.';
    },
  );
}

/// Lê "−5" (menos tipográfico) e "-5". O campo aceita os dois porque o teclado
/// do celular e o texto colado de uma planilha não produzem o mesmo caractere.
int? lerInteiroComSinal(String texto) =>
    int.tryParse(texto.trim().replaceAll('−', '-'));

/// Validação local **só de formato** (design-system §5.4). Que o ajuste caiba no
/// saldo é regra, e quem decide é `fn_ajustar_estoque`.
String? validarInteiroComSinalNaoZero(String? valor) {
  final texto = valor?.trim() ?? '';
  if (texto.isEmpty) return 'Campo obrigatório.';
  final numero = lerInteiroComSinal(texto);
  if (numero == null) return 'Informe um número inteiro.';
  if (numero == 0) return 'A quantidade do ajuste não pode ser zero.';
  return null;
}
