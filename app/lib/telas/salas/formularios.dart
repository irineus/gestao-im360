import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../erros/erro_app.dart';
import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/botoes.dart';
import '../../widgets/confirmacao.dart';
import '../../widgets/formulario.dart';

/// Os formulários da tela de Salas e PCs (card 4.5). Todos devolvem `'salvo'`
/// ou `'excluido'` ao fechar, para a tela mostrar a confirmação efêmera certa
/// (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório, número,
/// data como dd/mm/aaaa.

void _recarregar(WidgetRef ref) =>
    ref.read(versaoInfraestruturaProvider.notifier).incrementar();

/// O status do PC e a manutenção em aberto deixaram de ser duas colunas soltas:
/// o card 5.4 as amarrou por trigger (`tg_pc_manutencao_status`), e `pc.status`
/// passou a ser DERIVADO de `pc_manutencao`. Por isso saíram daqui o interruptor
/// que oferecia a escolha e o aviso que dizia ao monitor que o status não
/// mudaria — os dois passaram a mentir no mesmo dia. A tela informa o que o
/// banco faz; não oferece uma decisão que ele já toma.
const _avisoStatusSegue =
    'O status do PC passa a "Em manutenção" automaticamente enquanto a '
    'manutenção estiver aberta.';
const _avisoStatusVolta =
    'Encerrada a manutenção, o PC volta a "Operacional" automaticamente e a '
    'contar na capacidade da sala.';

// ---------------------------------------------------------------------------
// Sala
// ---------------------------------------------------------------------------

class FormularioSala extends ConsumerStatefulWidget {
  const FormularioSala({super.key, this.sala});

  /// Nula = nova sala.
  final Sala? sala;

  @override
  ConsumerState<FormularioSala> createState() => _FormularioSalaState();
}

class _FormularioSalaState extends ConsumerState<FormularioSala> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.sala?.nome ?? '');
  late final _capacidade = TextEditingController(
    text: widget.sala == null ? '' : '${widget.sala!.capacidadeNominal}',
  );
  late String? _tipo = widget.sala?.tipo;
  late bool _ativo = widget.sala?.ativo ?? true;

  @override
  void dispose() {
    _nome.dispose();
    _capacidade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final sala = widget.sala;
    final editando = sala != null;
    final somenteLeitura = editando
        ? !permissoes.contains('salas.editar')
        : !permissoes.contains('salas.criar');

    return FormularioIm360(
      titulo: editando ? 'Sala' : 'Nova sala',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Nome *',
            helperText: 'Único na unidade.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(labelText: 'Tipo *'),
          items: [
            for (final tipo in tiposSala.entries)
              DropdownMenuItem(value: tipo.key, child: Text(tipo.value)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _tipo = valor),
          validator: (valor) => valor == null ? 'Escolha o tipo.' : null,
        ),
        TextFormField(
          controller: _capacidade,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.number,
          inputFormatters: [somenteDigitos],
          decoration: const InputDecoration(
            labelText: 'Capacidade nominal *',
            helperText:
                'Teto físico da sala. A capacidade efetiva conta os PCs '
                'operacionais até este teto.',
            helperMaxLines: 3,
          ),
          validator: validarInteiroPositivo,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativa', style: Tipografia.corpo),
          subtitle: const Text(
            'Inativa sai das listas e dos blocos novos; os PCs e o histórico '
            'ficam.',
            style: Tipografia.apoio,
          ),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(infraestruturaRepositorioProvider)
            .salvarSala(
              Sala(
                id: sala?.id,
                nome: _nome.text.trim(),
                tipo: _tipo!,
                capacidadeNominal: int.parse(_capacidade.text.trim()),
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
            exigePermissao: 'salas.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir sala?',
              mensagem:
                  '"${sala.nome}" será excluída. Se tiver computadores '
                  'cadastrados, a exclusão é recusada; nesse caso, marque-a '
                  'como inativa.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(infraestruturaRepositorioProvider)
                  .excluirSala(sala.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// PC — cadastro, status e a credencial (card 2.9 §8)
// ---------------------------------------------------------------------------

class FormularioPc extends ConsumerStatefulWidget {
  const FormularioPc({super.key, this.pc, this.salaId});

  /// Nulo = novo PC.
  final Pc? pc;

  /// Sala pré-selecionada quando o formulário abre de dentro do painel dela.
  final String? salaId;

  @override
  ConsumerState<FormularioPc> createState() => _FormularioPcState();
}

class _FormularioPcState extends ConsumerState<FormularioPc> {
  final _chave = GlobalKey<FormState>();
  late final _identificador = TextEditingController(
    text: widget.pc?.identificador ?? '',
  );
  late final _observacao = TextEditingController(
    text: widget.pc?.observacao ?? '',
  );
  late String? _salaId = widget.pc?.salaId ?? widget.salaId;
  late String _status = widget.pc?.status ?? 'OPERACIONAL';

  @override
  void dispose() {
    _identificador.dispose();
    _observacao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salas = ref.watch(salasProvider).value ?? const <Sala>[];
    final permissoes = ref.watch(permissoesProvider);
    // O carimbo da credencial vem da lista recarregada, não do `pc` recebido:
    // depois de gravar a credencial a ficha precisa mostrar o carimbo novo.
    Pc? pcAtual = widget.pc;
    for (final p in ref.watch(pcsProvider).value ?? const <Pc>[]) {
      if (p.id == widget.pc?.id) pcAtual = p;
    }
    final pc = pcAtual;
    final editando = pc != null;
    final somenteLeitura = editando
        ? !permissoes.contains('salas.editar')
        : !permissoes.contains('salas.criar');

    return FormularioIm360(
      titulo: editando ? 'Computador' : 'Novo PC',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _salaId,
          decoration: const InputDecoration(labelText: 'Sala *'),
          items: [
            for (final sala in salas)
              if (sala.ativo || sala.id == _salaId)
                DropdownMenuItem(value: sala.id, child: Text(sala.nome)),
          ],
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _salaId = valor),
          validator: (valor) => valor == null ? 'Escolha a sala.' : null,
        ),
        TextFormField(
          controller: _identificador,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Identificador *',
            helperText: 'Único na unidade. Ex.: LAB1-01.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        // PC novo nasce OPERACIONAL (default da coluna); o status só se edita.
        if (editando)
          DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status *',
              helperText:
                  '"Em manutenção" e "Desativado" saem da capacidade da sala.',
              helperMaxLines: 3,
            ),
            items: [
              for (final status in statusPc.entries)
                DropdownMenuItem(value: status.key, child: Text(status.value)),
            ],
            onChanged: somenteLeitura
                ? null
                : (valor) => setState(() => _status = valor!),
          ),
        TextFormField(
          controller: _observacao,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Observação'),
        ),
        if (editando) _SecaoCredencial(pc: pc),
      ],
      aoSalvar: () async {
        await ref
            .read(infraestruturaRepositorioProvider)
            .salvarPc(
              Pc(
                id: pc?.id,
                salaId: _salaId!,
                identificador: _identificador.text.trim(),
                status: _status,
                observacao: _observacao.text,
                credencialEm: pc?.credencialEm,
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
            exigePermissao: 'salas.excluir',
            confirmacao: ConfirmacaoAcao(
              titulo: 'Excluir computador?',
              mensagem:
                  '"${pc.identificador}" será excluído. Se tiver histórico — '
                  'manutenção registrada ou leitura de credencial —, a '
                  'exclusão é recusada; nesse caso, marque-o como desativado.',
              rotulo: 'Excluir',
            ),
            executar: () async {
              await ref
                  .read(infraestruturaRepositorioProvider)
                  .excluirPc(pc.id!);
              _recarregar(ref);
              return 'excluido';
            },
          ),
      ],
    );
  }
}

/// A ficha da credencial (docs/politica-credenciais-pcs.md §8): o carimbo
/// que qualquer um com `salas.ler` vê, e os dois botões que só quem tem
/// `salas.acessar_credencial` vê — ocultados, não desabilitados (card 2.6).
class _SecaoCredencial extends StatelessWidget {
  const _SecaoCredencial({required this.pc});

  final Pc pc;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Credencial de acesso', style: Tipografia.rotulo),
        const SizedBox(height: Dim.e4),
        Text(
          pc.temCredencial
              ? 'Credencial cadastrada · atualizada em '
                    '${formatarData(pc.credencialEm!)}.'
              : 'Sem credencial cadastrada.',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        const SizedBox(height: Dim.e8),
        Wrap(
          spacing: Dim.e8,
          runSpacing: Dim.e8,
          children: [
            if (pc.temCredencial)
              BotaoAcao(
                rotulo: 'Ver credencial',
                nivel: NivelBotao.secundario,
                icone: Icons.visibility_outlined,
                exigePermissao: 'salas.acessar_credencial',
                aoTocar: () => showDialog<void>(
                  context: context,
                  builder: (_) => DialogoCredencial(pc: pc),
                ),
              ),
            BotaoAcao(
              rotulo: pc.temCredencial
                  ? 'Rotacionar credencial'
                  : 'Gravar credencial',
              nivel: NivelBotao.secundario,
              icone: Icons.key_outlined,
              exigePermissao: 'salas.acessar_credencial',
              aoTocar: () async {
                final resultado = await mostrarFormulario<String>(
                  context,
                  construtor: (_) => FormularioCredencial(pc: pc),
                );
                if (resultado != null && context.mounted) {
                  confirmarEfemero(context, 'Credencial gravada.');
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// O diálogo com usuário e senha (card 2.7 (f): resultado que muda a próxima
/// ação vai em diálogo, nunca em snackbar). A leitura acontece ao abrir — e
/// só então, porque cada leitura grava uma linha de acesso no banco. O par
/// vive no estado deste widget e morre com ele.
class DialogoCredencial extends ConsumerStatefulWidget {
  const DialogoCredencial({super.key, required this.pc});

  final Pc pc;

  @override
  ConsumerState<DialogoCredencial> createState() => _DialogoCredencialState();
}

class _DialogoCredencialState extends ConsumerState<DialogoCredencial> {
  late final Future<CredencialPc?> _leitura = ref
      .read(infraestruturaRepositorioProvider)
      .lerCredencial(widget.pc.id!);

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text('Credencial de ${widget.pc.identificador}'),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<CredencialPc?>(
          future: _leitura,
          builder: (context, foto) {
            if (foto.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (foto.hasError) {
              return AvisoTonal(
                mensagem: traduzirErro(foto.error!).mensagem,
                erro: true,
              );
            }
            final credencial = foto.data;
            if (credencial == null) {
              return const Text(
                'Sem credencial cadastrada.',
                style: Tipografia.corpo,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _CampoCopiavel(rotulo: 'Usuário', valor: credencial.usuario),
                const SizedBox(height: Dim.e12),
                _CampoCopiavel(rotulo: 'Senha', valor: credencial.senha),
                const SizedBox(height: Dim.e12),
                Text(
                  'Esta leitura ficou registrada com o seu nome e a hora.',
                  style: Tipografia.apoio.copyWith(
                    color: cores.onSurfaceVariant,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _CampoCopiavel extends StatelessWidget {
  const _CampoCopiavel({required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                rotulo,
                style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
              ),
              SelectableText(valor, style: Tipografia.numero(Tipografia.corpo)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copiar',
          icon: const Icon(Icons.copy_outlined),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: valor));
            if (context.mounted) confirmarEfemero(context, '$rotulo copiado.');
          },
        ),
      ],
    );
  }
}

/// Gravar e rotacionar são o mesmo formulário, com os dois campos em branco —
/// não se pré-carrega senha (card 2.9 §8).
class FormularioCredencial extends ConsumerStatefulWidget {
  const FormularioCredencial({super.key, required this.pc});

  final Pc pc;

  @override
  ConsumerState<FormularioCredencial> createState() =>
      _FormularioCredencialState();
}

class _FormularioCredencialState extends ConsumerState<FormularioCredencial> {
  final _chave = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _senha = TextEditingController();
  bool _mostrarSenha = false;

  @override
  void dispose() {
    _usuario.dispose();
    _senha.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rotacao = widget.pc.temCredencial;
    return FormularioIm360(
      titulo: rotacao ? 'Rotacionar credencial' : 'Gravar credencial',
      chave: _chave,
      rotuloSalvar: 'Gravar',
      somenteLeitura: !ref
          .watch(permissoesProvider)
          .contains('salas.acessar_credencial'),
      aviso:
          'O par usuário e senha é guardado cifrado no cofre do banco, e cada '
          'leitura fica registrada com quem leu e quando.'
          '${rotacao ? ' A credencial atual é substituída.' : ''}',
      campos: [
        TextFormField(
          controller: _usuario,
          style: Tipografia.corpo,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Usuário *',
            helperText: 'O login da máquina — ${widget.pc.identificador}.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        TextFormField(
          controller: _senha,
          style: Tipografia.corpo,
          obscureText: !_mostrarSenha,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Senha *',
            suffixIcon: IconButton(
              tooltip: _mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
              icon: Icon(
                _mostrarSenha
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _mostrarSenha = !_mostrarSenha),
            ),
          ),
          validator: validarObrigatorio,
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(infraestruturaRepositorioProvider)
            .gravarCredencial(
              widget.pc.id!,
              usuario: _usuario.text.trim(),
              senha: _senha.text,
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Manutenção — registrar, encerrar; e reativar o PC desativado
// ---------------------------------------------------------------------------

class FormularioManutencao extends ConsumerStatefulWidget {
  const FormularioManutencao({super.key, required this.pc});

  final Pc pc;

  @override
  ConsumerState<FormularioManutencao> createState() =>
      _FormularioManutencaoState();
}

class _FormularioManutencaoState extends ConsumerState<FormularioManutencao> {
  final _chave = GlobalKey<FormState>();
  String _tipo = 'CORRETIVA';
  final _inicio = TextEditingController(text: formatarData(DateTime.now()));
  final _fim = TextEditingController();
  final _descricao = TextEditingController();
  String? _substitutoId;

  @override
  void dispose() {
    _inicio.dispose();
    _fim.dispose();
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final pc = widget.pc;
    final substitutos = [
      for (final p in ref.watch(pcsProvider).value ?? const <Pc>[])
        if (p.id != pc.id && p.operacional) p,
    ];

    return FormularioIm360(
      titulo: 'Registrar manutenção — ${pc.identificador}',
      chave: _chave,
      rotuloSalvar: 'Registrar',
      somenteLeitura: !permissoes.contains('salas.registrar_manutencao'),
      aviso: pc.status == 'MANUTENCAO' ? null : _avisoStatusSegue,
      campos: [
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(labelText: 'Tipo *'),
          items: [
            for (final tipo in tiposManutencao.entries)
              DropdownMenuItem(value: tipo.key, child: Text(tipo.value)),
          ],
          onChanged: (valor) => setState(() => _tipo = valor!),
        ),
        TextFormField(
          controller: _inicio,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Início *',
            hintText: 'dd/mm/aaaa',
          ),
          validator: validarData,
        ),
        TextFormField(
          controller: _fim,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Previsão de fim',
            hintText: 'dd/mm/aaaa',
            helperText:
                'Opcional. É o dia em que o PC volta a operar; até lá a '
                'manutenção conta como aberta.',
            helperMaxLines: 3,
          ),
          validator: (valor) => validarData(valor, obrigatorio: false),
        ),
        DropdownButtonFormField<String>(
          initialValue: _substitutoId ?? '',
          decoration: const InputDecoration(
            labelText: 'PC substituto',
            helperText:
                'Sem substituto, a manutenção derruba a capacidade da sala.',
            helperMaxLines: 3,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Nenhum')),
            for (final p in substitutos)
              DropdownMenuItem(value: p.id, child: Text(p.identificador)),
          ],
          onChanged: (valor) => setState(
            () =>
                _substitutoId = (valor == null || valor.isEmpty) ? null : valor,
          ),
        ),
        TextFormField(
          controller: _descricao,
          style: Tipografia.corpo,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Descrição'),
        ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(infraestruturaRepositorioProvider);
        await repositorio.salvarManutencao(
          PcManutencao(
            pcId: pc.id!,
            tipo: _tipo,
            dataInicio: lerData(_inicio.text)!,
            dataFim: _fim.text.trim().isEmpty ? null : lerData(_fim.text),
            descricao: _descricao.text,
            pcSubstitutoId: _substitutoId,
          ),
        );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

class FormularioEncerrarManutencao extends ConsumerStatefulWidget {
  const FormularioEncerrarManutencao({
    super.key,
    required this.pc,
    required this.manutencao,
  });

  final Pc pc;
  final PcManutencao manutencao;

  @override
  ConsumerState<FormularioEncerrarManutencao> createState() =>
      _FormularioEncerrarManutencaoState();
}

class _FormularioEncerrarManutencaoState
    extends ConsumerState<FormularioEncerrarManutencao> {
  final _chave = GlobalKey<FormState>();
  final _fim = TextEditingController(text: formatarData(DateTime.now()));

  @override
  void dispose() {
    _fim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final pc = widget.pc;
    final manutencao = widget.manutencao;

    return FormularioIm360(
      titulo: 'Encerrar manutenção — ${pc.identificador}',
      chave: _chave,
      rotuloSalvar: 'Encerrar',
      somenteLeitura: !permissoes.contains('salas.registrar_manutencao'),
      aviso: pc.status == 'MANUTENCAO' ? _avisoStatusVolta : null,
      campos: [
        Text(
          '${rotuloTipoManutencao(manutencao.tipo)} desde '
          '${formatarData(manutencao.dataInicio)}'
          '${manutencao.descricao == null ? '' : ' · ${manutencao.descricao}'}',
          style: Tipografia.corpo,
        ),
        TextFormField(
          controller: _fim,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: TextInputType.datetime,
          decoration: const InputDecoration(
            labelText: 'Fim *',
            hintText: 'dd/mm/aaaa',
          ),
          validator: validarData,
        ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(infraestruturaRepositorioProvider);
        await repositorio.salvarManutencao(
          manutencao.copiar(dataFim: lerData(_fim.text)),
        );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

/// Reativar é uma mudança de status com confirmação — o formulário sem campos
/// dá o banner de erro e o botão travado de graça.
class FormularioReativarPc extends ConsumerStatefulWidget {
  const FormularioReativarPc({super.key, required this.pc});

  final Pc pc;

  @override
  ConsumerState<FormularioReativarPc> createState() =>
      _FormularioReativarPcState();
}

class _FormularioReativarPcState extends ConsumerState<FormularioReativarPc> {
  final _chave = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) => FormularioIm360(
    titulo: 'Reativar computador',
    chave: _chave,
    rotuloSalvar: 'Reativar',
    legendaObrigatorio: false,
    somenteLeitura: !ref.watch(permissoesProvider).contains('salas.editar'),
    campos: [
      Text(
        '${widget.pc.identificador} volta a "Operacional" e a contar na '
        'capacidade da sala.',
        style: Tipografia.corpo,
      ),
    ],
    aoSalvar: () async {
      await ref
          .read(infraestruturaRepositorioProvider)
          .salvarPc(widget.pc.copiar(status: 'OPERACIONAL'));
      _recarregar(ref);
      return 'salvo';
    },
  );
}

// ---------------------------------------------------------------------------
// Professor — nome e ativo; não se exclui
// ---------------------------------------------------------------------------

class FormularioProfessor extends ConsumerStatefulWidget {
  const FormularioProfessor({super.key, this.professor});

  final Professor? professor;

  @override
  ConsumerState<FormularioProfessor> createState() =>
      _FormularioProfessorState();
}

class _FormularioProfessorState extends ConsumerState<FormularioProfessor> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.professor?.nome ?? '');
  late bool _ativo = widget.professor?.ativo ?? true;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final professor = widget.professor;
    final editando = professor != null;
    final somenteLeitura = editando
        ? !permissoes.contains('professores.editar')
        : !permissoes.contains('professores.criar');

    return FormularioIm360(
      titulo: editando ? 'Professor' : 'Novo professor',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      campos: [
        TextFormField(
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'Nome *',
            helperText: 'Único na unidade.',
            helperMaxLines: 3,
          ),
          validator: validarObrigatorio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          subtitle: const Text(
            'Inativo sai da grade de turmas; o histórico das aulas fica. '
            'Professor não se exclui.',
            style: Tipografia.apoio,
          ),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(infraestruturaRepositorioProvider)
            .salvarProfessor(
              Professor(
                id: professor?.id,
                nome: _nome.text.trim(),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}
