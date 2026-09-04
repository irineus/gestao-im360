import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../alunos/alunos.dart';
import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../pendencias/pendencias_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../trilha/trilha.dart';
import '../../trilha/trilha_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/escolha.dart';
import '../../widgets/formulario.dart';

/// Os formulários da aba Trilha (card 6.6): gerar a trilha pelo combo, incluir,
/// remover e reordenar item, e estornar uma entrega. Todos devolvem uma string
/// ao fechar, para a aba mostrar a confirmação efêmera certa
/// (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — motivo obrigatório e
/// escolha feita.
///
/// ⚠️ A entrega **não tem formulário**: ela é um botão só, e o que ela produz é
/// um RESULTADO (três status), não um "salvou". Quem a mostra é
/// `mostrarResultado` (design-system §5.8), a partir da própria aba.

/// Recarrega a trilha e a central de pendências: a entrega e o estorno mexem
/// nas duas (`COMPRA_SEM_ESTOQUE`, `ESTOQUE_ZERO`, `ULTIMO_LIVRO`), e uma
/// pendência que a tela acabou de criar e não mostra é a central perdendo
/// credibilidade (card 5.8).
void _recarregar(WidgetRef ref) {
  ref.read(versaoTrilhaProvider.notifier).incrementar();
  ref.read(versaoPendenciasProvider.notifier).incrementar();
}

// ---------------------------------------------------------------------------
// Gerar a trilha pelo combo
// ---------------------------------------------------------------------------

/// A ação do estado vazio (design-system §7.2: "Gere a partir do combo em
/// **Editar trilha**") e o "regerar" do card 6.2.
///
/// `substituir` fica **desligado** e é uma escolha explícita: `fn_trilha_gerar`
/// recusa a segunda geração com `TRILHA_JA_EXISTE`, e é essa recusa que o
/// formulário quer — a pessoa vê o aviso e decide, em vez de a tela decidir por
/// ela e apagar a trilha que alguém editou à mão.
class FormularioGerarTrilha extends ConsumerStatefulWidget {
  const FormularioGerarTrilha({super.key, required this.aluno});

  final Aluno aluno;

  @override
  ConsumerState<FormularioGerarTrilha> createState() =>
      _FormularioGerarTrilhaState();
}

class _FormularioGerarTrilhaState extends ConsumerState<FormularioGerarTrilha> {
  final _chave = GlobalKey<FormState>();
  bool _substituir = false;

  @override
  Widget build(BuildContext context) {
    final combos = ref.watch(combosProvider).value ?? const <Combo>[];
    String? nomeCombo;
    for (final c in combos) {
      if (c.id == widget.aluno.comboId) nomeCombo = c.nome;
    }
    final semCombo = widget.aluno.comboId == null;

    return FormularioIm360(
      titulo: 'Gerar trilha pelo combo',
      rotuloSalvar: 'Gerar trilha',
      chave: _chave,
      legendaObrigatorio: false,
      aviso: semCombo
          ? 'O aluno não tem combo definido. Informe o combo nos dados do '
                'aluno.'
          : _substituir
          ? 'Substituir apaga os itens pendentes que vieram do combo e refaz a '
                'trilha na ordem do catálogo. O que foi incluído à mão e o que '
                'já foi entregue continuam.'
          : null,
      campos: [
        Text(
          semCombo
              ? 'A trilha nasce do combo, e este aluno está sem combo.'
              : 'A trilha será gerada a partir do combo $nomeCombo, na ordem '
                    'dos cursos e das apostilas do catálogo.',
          style: Tipografia.corpo,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _substituir,
          title: const Text('Substituir a trilha existente'),
          subtitle: const Text(
            'Só marque se a trilha atual estiver errada. Trilha com apostila '
            'entregue não é substituível.',
          ),
          onChanged: semCombo
              ? null
              : (valor) => setState(() => _substituir = valor),
        ),
      ],
      aoSalvar: semCombo
          ? null
          : () async {
              final quantos = await ref
                  .read(trilhaRepositorioProvider)
                  .gerarTrilha(widget.aluno.id!, substituir: _substituir);
              _recarregar(ref);
              return 'Trilha gerada com $quantos '
                  '${quantos == 1 ? 'apostila' : 'apostilas'}.';
            },
    );
  }
}

// ---------------------------------------------------------------------------
// Incluir apostila
// ---------------------------------------------------------------------------

/// Inclui uma apostila **depois** de outra — é o `p_apos_material_id` de
/// `fn_trilha_inserir`, que ocupa a fresta entre duas ordens sem renumerar a
/// trilha (card 6.2 §5.1).
class FormularioIncluirNaTrilha extends ConsumerStatefulWidget {
  const FormularioIncluirNaTrilha({
    super.key,
    required this.aluno,
    required this.trilha,
  });

  final Aluno aluno;
  final List<ItemTrilha> trilha;

  @override
  ConsumerState<FormularioIncluirNaTrilha> createState() =>
      _FormularioIncluirNaTrilhaState();
}

class _FormularioIncluirNaTrilhaState
    extends ConsumerState<FormularioIncluirNaTrilha> {
  final _chave = GlobalKey<FormState>();
  String? _materialId;

  /// Vazio = no começo da trilha (o `null` da função).
  String _aposMaterialId = '';

  @override
  Widget build(BuildContext context) {
    final materiais =
        ref.watch(materiaisProvider).value ?? const <MaterialDidatico>[];
    final candidatos = candidatosParaTrilha<MaterialDidatico>(
      materiais,
      idDe: (m) => m.id!,
      metodoDe: (m) => m.metodoId,
      ativoDe: (m) => m.ativo,
      metodoDoAluno: widget.aluno.metodoId,
      jaNaTrilha: {for (final i in widget.trilha) i.materialId},
    )..sort((a, b) => a.codigo.compareTo(b.codigo));

    return FormularioIm360(
      titulo: 'Incluir apostila na trilha',
      rotuloSalvar: 'Incluir',
      chave: _chave,
      campos: [
        Text(
          candidatos.isEmpty
              ? 'Todas as apostilas ativas do método do aluno já estão na '
                    'trilha.'
              : 'Apostilas do método do aluno que ainda não estão na trilha.',
          style: Tipografia.corpo,
        ),
        const SizedBox(height: Dim.e8),
        for (final m in candidatos)
          LinhaEscolha(
            rotulo: '${m.codigo} ${m.nome}',
            apoio: m.categoria,
            marcada: _materialId == m.id,
            aoTocar: () => setState(() => _materialId = m.id),
          ),
        // Validação local só de formato: "escolheu?" é formato; "pode?" é do
        // banco (`MATERIAL_JA_NA_TRILHA`, `SEM_PERMISSAO`).
        FormField<String>(
          initialValue: _materialId,
          validator: (_) => _materialId == null ? 'Escolha a apostila.' : null,
          builder: (estado) => estado.hasError
              ? Padding(
                  padding: const EdgeInsets.only(top: Dim.e4),
                  child: Text(
                    estado.errorText!,
                    style: Tipografia.apoio.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        DropdownButtonFormField<String>(
          initialValue: _aposMaterialId,
          decoration: const InputDecoration(
            labelText: 'Entra depois de',
            helperText:
                'A posição na trilha. "No começo" coloca antes de tudo o que '
                'está pendente.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('No começo')),
            for (final i in widget.trilha)
              DropdownMenuItem(
                value: i.materialId,
                child: Text('${i.posicao}. ${i.rotulo}'),
              ),
          ],
          onChanged: (valor) => setState(() => _aposMaterialId = valor ?? ''),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(trilhaRepositorioProvider)
            .inserirItem(
              widget.aluno.id!,
              materialId: _materialId!,
              aposMaterialId: _aposMaterialId.isEmpty ? null : _aposMaterialId,
            );
        _recarregar(ref);
        return 'Apostila incluída na trilha.';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Remover item
// ---------------------------------------------------------------------------

/// Remove um item PENDENTE. Item entregue não sai (card 6.1 §10.1): ele é a
/// única ligação entre a SAIDA de estoque e o aluno que a recebeu, e a tela
/// nem oferece o botão — a recusa `ITEM_JA_ENTREGUE` continua embaixo, para
/// quem chegar por outro caminho.
class FormularioRemoverDaTrilha extends ConsumerStatefulWidget {
  const FormularioRemoverDaTrilha({
    super.key,
    required this.aluno,
    required this.item,
  });

  final Aluno aluno;
  final ItemTrilha item;

  @override
  ConsumerState<FormularioRemoverDaTrilha> createState() =>
      _FormularioRemoverDaTrilhaState();
}

class _FormularioRemoverDaTrilhaState
    extends ConsumerState<FormularioRemoverDaTrilha> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  bool _realceMotivo = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Remover da trilha',
    rotuloSalvar: 'Remover',
    nivelSalvar: NivelBotao.destrutivo,
    chave: _chave,
    aviso:
        'A remoção fica no histórico da trilha, com o motivo. O aluno deixa '
        'de receber ${widget.item.rotulo}.',
    campos: [
      TextFormField(
        controller: _motivo,
        style: Tipografia.corpo,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Motivo *',
          errorText: _realceMotivo ? 'Informe o motivo para continuar.' : null,
        ),
        validator: validarObrigatorio,
      ),
    ],
    // `MOTIVO_OBRIGATORIO` vindo do banco realça o campo, não só o banner
    // (design-system §5.4).
    aoErro: (erro) =>
        setState(() => _realceMotivo = erro.codigo == 'MOTIVO_OBRIGATORIO'),
    aoSalvar: () async {
      await ref
          .read(trilhaRepositorioProvider)
          .removerItem(
            widget.aluno.id!,
            materialId: widget.item.materialId,
            motivo: _motivo.text,
          );
      _recarregar(ref);
      return 'Apostila removida da trilha.';
    },
  );
}

// ---------------------------------------------------------------------------
// Estornar entrega
// ---------------------------------------------------------------------------

/// Desfaz uma entrega: devolve o exemplar ao estoque e a apostila à trilha,
/// **sem apagar nada**. O movimento original continua lá e o estorno entra ao
/// lado — é o contrato do card 2.2 §6.3, e é ele que explica um saldo três
/// meses depois.
class FormularioEstornarEntrega extends ConsumerStatefulWidget {
  const FormularioEstornarEntrega({super.key, required this.item});

  final ItemTrilha item;

  @override
  ConsumerState<FormularioEstornarEntrega> createState() =>
      _FormularioEstornarEntregaState();
}

class _FormularioEstornarEntregaState
    extends ConsumerState<FormularioEstornarEntrega> {
  final _chave = GlobalKey<FormState>();
  final _motivo = TextEditingController();
  bool _realceMotivo = false;

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Estornar entrega',
    rotuloSalvar: 'Estornar',
    nivelSalvar: NivelBotao.destrutivo,
    chave: _chave,
    aviso:
        'O exemplar volta ao estoque e ${widget.item.rotulo} volta a ficar '
        'pendente na trilha. O movimento original continua no histórico, com '
        'o estorno ao lado.',
    campos: [
      TextFormField(
        controller: _motivo,
        style: Tipografia.corpo,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Motivo *',
          errorText: _realceMotivo ? 'Informe o motivo para continuar.' : null,
        ),
        validator: validarObrigatorio,
      ),
    ],
    aoErro: (erro) =>
        setState(() => _realceMotivo = erro.codigo == 'MOTIVO_OBRIGATORIO'),
    aoSalvar: () async {
      await ref
          .read(trilhaRepositorioProvider)
          .estornarEntrega(
            widget.item.movimentoEstoqueId!,
            motivo: _motivo.text,
          );
      _recarregar(ref);
      return 'Entrega estornada.';
    },
  );
}

// ---------------------------------------------------------------------------
// Reordenar — a divergência registrada deste card
// ---------------------------------------------------------------------------

/// Move um item pendente para outra POSIÇÃO da trilha.
///
/// ⚠️ **Divergência do wireframe §6.3, registrada no §17:** o desenho pede "modo
/// de reordenação (arrastar)". A aba usa **setas** (subir/descer) e este
/// formulário para saltos longos. Três razões, e nenhuma é preguiça:
/// (a) arrastar dentro de um `TabBarView` que já rola disputa o gesto vertical
/// com a rolagem, e a trilha tem 14 a 17 itens — o alvo de arraste seria menor
/// que os 44 px do §8.4; (b) arrastar **não tem equivalente por teclado**, e o
/// §8.3 exige navegação completa por teclado no desktop; (c) `fn_trilha_reordenar`
/// recebe uma POSIÇÃO (card 6.2 §5.3), que é exatamente o que a seta e este
/// campo produzem — o arraste teria de traduzir pixels para a mesma posição.
class FormularioReordenarTrilha extends ConsumerStatefulWidget {
  const FormularioReordenarTrilha({
    super.key,
    required this.aluno,
    required this.item,
    required this.total,
  });

  final Aluno aluno;
  final ItemTrilha item;
  final int total;

  @override
  ConsumerState<FormularioReordenarTrilha> createState() =>
      _FormularioReordenarTrilhaState();
}

class _FormularioReordenarTrilhaState
    extends ConsumerState<FormularioReordenarTrilha> {
  final _chave = GlobalKey<FormState>();
  late final _posicao = TextEditingController(text: '${widget.item.posicao}');

  @override
  void dispose() {
    _posicao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Mover na trilha',
    rotuloSalvar: 'Mover',
    chave: _chave,
    campos: [
      Text(
        '${widget.item.rotulo} está na posição ${widget.item.posicao} de '
        '${widget.total}.',
        style: Tipografia.corpo,
      ),
      TextFormField(
        controller: _posicao,
        style: Tipografia.numero(Tipografia.corpo),
        keyboardType: TextInputType.number,
        inputFormatters: [somenteDigitos],
        decoration: const InputDecoration(
          labelText: 'Nova posição *',
          helperText:
              'Posição na trilha, começando em 1. Fora das bordas, vai para a '
              'ponta mais próxima.',
          helperMaxLines: 3,
        ),
        validator: validarInteiroPositivo,
      ),
    ],
    aoSalvar: () async {
      await ref
          .read(trilhaRepositorioProvider)
          .reordenarItem(
            widget.aluno.id!,
            materialId: widget.item.materialId,
            novaPosicao: int.parse(_posicao.text.trim()),
          );
      _recarregar(ref);
      return 'Trilha reordenada.';
    },
  );
}

/// Move o item uma casa, sem formulário — é o que as setas da aba chamam.
/// Devolve a mensagem da confirmação efêmera.
Future<String> moverNaTrilha(
  WidgetRef ref, {
  required String alunoId,
  required ItemTrilha item,
  required int novaPosicao,
}) async {
  await ref
      .read(trilhaRepositorioProvider)
      .reordenarItem(
        alunoId,
        materialId: item.materialId,
        novaPosicao: novaPosicao,
      );
  _recarregar(ref);
  return 'Trilha reordenada.';
}

/// Quem pode editar a trilha — usado pela aba para decidir se o modo de edição
/// existe. Repetido aqui para o widget não importar `sessao_provider` só por
/// uma linha.
bool podeEditarTrilha(WidgetRef ref) =>
    ref.watch(permissoesProvider).contains('alunos.editar_trilha');
