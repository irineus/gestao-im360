import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalogo/catalogo.dart';
import '../../catalogo/catalogo_provider.dart';
import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../turmas/turmas.dart';
import '../../turmas/turmas_provider.dart';
import '../../widgets/botoes.dart';
import '../../widgets/estados.dart';
import '../../widgets/formulario.dart';
import '../../widgets/painel_detalhe.dart';

/// Os formulários da grade semanal (card 5.6). Devolvem `'salvo'` ou
/// `'excluido'` ao fechar, para a tela mostrar a confirmação efêmera certa
/// (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório, número,
/// horário como `hh:mm`. Quem recusa dois blocos na mesma sala, dia e hora é a
/// `unique` do banco (23505, já traduzido desde o card 4.4); quem recusa apagar
/// bloco com histórico é `tg_bloco_exclusao_valida` (`BLOCO_COM_ALOCACAO`).

void _recarregar(WidgetRef ref) =>
    ref.read(versaoTurmasProvider.notifier).incrementar();

class FormularioBloco extends ConsumerStatefulWidget {
  const FormularioBloco({
    super.key,
    this.bloco,
    this.celula,
    this.diaSemana,
    this.horaInicio,
  });

  /// Nulo = bloco novo.
  final BlocoHorario? bloco;

  /// A célula de onde o formulário foi aberto, quando houve uma: é dela que
  /// vem a ocupação **daquela semana**, usada só para avisar.
  final CelulaGrade? celula;

  /// Pré-seleção quando o formulário abre de uma célula vazia da grade.
  final int? diaSemana;
  final String? horaInicio;

  @override
  ConsumerState<FormularioBloco> createState() => _FormularioBlocoState();
}

class _FormularioBlocoState extends ConsumerState<FormularioBloco> {
  final _chave = GlobalKey<FormState>();
  late int _dia = widget.bloco?.diaSemana ?? widget.diaSemana ?? 1;
  late final _hora = TextEditingController(
    text: widget.bloco?.horaInicio ?? widget.horaInicio ?? '08:00',
  );
  late final _override = TextEditingController(
    text: widget.bloco?.capacidadeOverride?.toString() ?? '',
  );
  late String? _metodoId = widget.bloco?.metodoId;
  late String? _salaId = widget.bloco?.salaId;
  late String? _professorId = widget.bloco?.professorId;
  late bool _ativo = widget.bloco?.ativo ?? true;

  @override
  void dispose() {
    _hora.dispose();
    _override.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final bloco = widget.bloco;
    final editando = bloco != null;
    final somenteLeitura = editando
        ? !permissoes.contains('turmas.editar')
        : !permissoes.contains('turmas.criar');

    // ⚠️ As três listas são ESPERADAS, não lidas com `?? const []`.
    // `DropdownButtonFormField` tem um `assert` que exige que o valor inicial
    // exista entre os itens: com a lista ainda vazia, abrir o formulário de um
    // bloco que já tem professor derrubava a tela com uma asserção do
    // framework — e `professoresProvider` só começa a carregar quando ESTE
    // formulário abre, então o caso não era raro, era o normal. Visto em teste
    // antes de ser corrigido.
    final metodosAsync = ref.watch(metodosProvider);
    final salasAsync = ref.watch(salasProvider);
    final professoresAsync = ref.watch(professoresProvider);
    final pcsAsync = ref.watch(pcsProvider);
    if (!metodosAsync.hasValue ||
        !salasAsync.hasValue ||
        !professoresAsync.hasValue ||
        !pcsAsync.hasValue) {
      return FormularioIm360(
        titulo: editando ? 'Bloco de horário' : 'Novo bloco',
        chave: _chave,
        somenteLeitura: true,
        legendaObrigatorio: false,
        campos: const [EstadoCarregando(linhas: 5)],
      );
    }

    final metodos = metodosAsync.requireValue;
    final salas = salasAsync.requireValue;
    final professores = professoresAsync.requireValue;
    final resumo = resumirSalas(salas, pcsAsync.requireValue);
    final ocupacao = widget.celula?.ocupacao ?? 0;

    // Segunda barreira contra a mesma asserção: id que o catálogo não resolve
    // degrada para "não escolhido" em vez de derrubar o formulário. Com a
    // matriz inicial isto não acontece (`materiais.ler`, `salas.ler` e
    // `professores.ler` são dos quatro perfis, card 2.4), e é por isso que a
    // degradação é aceitável: quando ela agir, o dado já estava inalcançável.
    final metodoSelecionado = metodos.any((m) => m.id == _metodoId)
        ? _metodoId
        : null;
    final salaSelecionada = salas.any((s) => s.id == _salaId) ? _salaId : null;
    final professorSelecionado = professores.any((p) => p.id == _professorId)
        ? _professorId!
        : '';

    return FormularioIm360(
      titulo: editando ? 'Bloco de horário' : 'Novo bloco',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      // O único aviso do formulário, e ele é sobre o que a tela NÃO resolve:
      // desativar tira o bloco da grade e não realoca ninguém. A realocação é
      // da tela do card 5.7, e dizer isto aqui é melhor do que descobrir na
      // semana seguinte que uma turma inteira sumiu do horário.
      aviso: (!_ativo && ocupacao > 0)
          ? 'Este bloco tem $ocupacao aluno(s) nesta semana. Desativá-lo o tira '
                'da grade, mas não realoca ninguém — realoque antes, na tela do '
                'bloco.'
          : null,
      campos: [
        DropdownButtonFormField<int>(
          initialValue: _dia,
          decoration: const InputDecoration(labelText: 'Dia da semana *'),
          items: [
            for (final entrada in nomesDia.entries)
              DropdownMenuItem(value: entrada.key, child: Text(entrada.value)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _dia = valor!),
        ),
        TextFormField(
          controller: _hora,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Horário de início *',
            hintText: 'hh:mm',
            helperText:
                'A mesma sala não pode ter dois blocos no mesmo dia e '
                'horário.',
            helperMaxLines: 3,
          ),
          validator: validarHora,
        ),
        DropdownButtonFormField<String>(
          initialValue: metodoSelecionado,
          decoration: const InputDecoration(labelText: 'Método *'),
          items: [
            for (final m in metodos)
              if (m.ativo || m.id == _metodoId)
                DropdownMenuItem(value: m.id, child: Text(m.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _metodoId = valor),
          validator: (valor) => valor == null ? 'Escolha o método.' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: salaSelecionada,
          decoration: InputDecoration(
            labelText: 'Sala *',
            helperText: _salaId == null
                ? 'A capacidade do bloco sai dos PCs operacionais da sala.'
                : 'Capacidade derivada: '
                      '${resumo[_salaId]?.efetiva ?? 0} '
                      '(${resumo[_salaId]?.operacionais ?? 0} PCs operacionais).',
            helperMaxLines: 3,
          ),
          items: [
            for (final s in salas)
              if (s.id != null && (s.ativo || s.id == _salaId))
                DropdownMenuItem(value: s.id, child: Text(s.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _salaId = valor),
          validator: (valor) => valor == null ? 'Escolha a sala.' : null,
        ),
        DropdownButtonFormField<String>(
          initialValue: professorSelecionado,
          decoration: const InputDecoration(
            labelText: 'Professor',
            helperText:
                'Opcional. Bloco sem professor aparece marcado na '
                'grade.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Nenhum')),
            for (final p in professores)
              if (p.ativo || p.id == _professorId)
                DropdownMenuItem(value: p.id, child: Text(p.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(
                  () => _professorId = (valor == null || valor.isEmpty)
                      ? null
                      : valor,
                ),
        ),
        TextFormField(
          controller: _override,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.number,
          inputFormatters: [somenteDigitos],
          decoration: const InputDecoration(
            labelText: 'Capacidade manual',
            helperText:
                'Opcional. Preenchida, vence a conta dos PCs. Para '
                'fechar o bloco, desative-o em vez de pôr 0.',
            helperMaxLines: 3,
          ),
          validator: (valor) => (valor == null || valor.trim().isEmpty)
              ? null
              : validarInteiroPositivo(valor),
        ),
        if (editando)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ativo', style: Tipografia.corpo),
            subtitle: const Text(
              'Inativo sai da grade e não recebe aluno novo; as alocações e o '
              'histórico ficam.',
              style: Tipografia.apoio,
            ),
            value: _ativo,
            onChanged: somenteLeitura
                ? null
                : (valor) => setState(() => _ativo = valor),
          ),
      ],
      aoSalvar: () async {
        final texto = _override.text.trim();
        await ref
            .read(turmasRepositorioProvider)
            .salvarBloco(
              BlocoHorario(
                id: bloco?.id,
                diaSemana: _dia,
                horaInicio: _hora.text.trim(),
                metodoId: _metodoId!,
                salaId: _salaId!,
                professorId: _professorId,
                capacidadeOverride: texto.isEmpty ? null : int.parse(texto),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
      acoes: [
        if (editando)
          AcaoFormulario(
            rotulo: 'Excluir',
            nivel: NivelBotao.destrutivo,
            exigePermissao: 'turmas.excluir',
            confirmacao: const ConfirmacaoAcao(
              titulo: 'Excluir bloco?',
              mensagem:
                  'Se alguém já esteve neste bloco — alocação, mesmo encerrada, '
                  'ou reposição —, a exclusão é recusada; nesse caso, desative '
                  'o bloco.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref.read(turmasRepositorioProvider).excluirBloco(bloco.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

/// Os blocos desativados, que não estão na grade.
///
/// Existe para que desativar não seja porta de mão única: sem esta lista, o
/// bloco desativado sumiria da única tela que fala de blocos e só voltaria por
/// alguém escrevendo no banco.
class DialogoBlocosInativos extends ConsumerWidget {
  const DialogoBlocosInativos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cores = Theme.of(context).colorScheme;
    final inativos =
        ref.watch(blocosInativosProvider).value ?? const <BlocoHorario>[];
    final metodos = {
      for (final m in ref.watch(metodosProvider).value ?? const <Metodo>[])
        m.id: m.nome,
    };
    final salas = {
      for (final s in ref.watch(salasProvider).value ?? const <Sala>[])
        s.id: s.nome,
    };

    return PainelDetalhe(
      titulo: 'Blocos inativos',
      subtitulo: 'Fora da grade e sem receber aluno novo. Reabra para editar.',
      acoes: const [],
      filho: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (inativos.isEmpty)
            Text(
              'Nenhum bloco inativo.',
              style: Tipografia.corpo.copyWith(color: cores.onSurfaceVariant),
            ),
          for (final bloco in inativos)
            Padding(
              padding: const EdgeInsets.only(bottom: Dim.e8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${nomeDia(bloco.diaSemana)} · ${bloco.horaInicio}',
                          style: Tipografia.numero(Tipografia.rotulo),
                        ),
                        Text(
                          '${metodos[bloco.metodoId] ?? '—'} · '
                          '${salas[bloco.salaId] ?? '—'}',
                          style: Tipografia.apoio.copyWith(
                            color: cores.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BotaoAcao(
                    rotulo: 'Abrir',
                    nivel: NivelBotao.secundario,
                    exigePermissao: 'turmas.editar',
                    aoTocar: () async {
                      final resultado = await mostrarFormulario<String>(
                        context,
                        construtor: (_) => FormularioBloco(bloco: bloco),
                      );
                      if (resultado != null && context.mounted) {
                        Navigator.of(context).pop(resultado);
                      }
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
