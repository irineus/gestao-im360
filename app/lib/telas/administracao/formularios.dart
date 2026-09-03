import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../administracao/administracao.dart';
import '../../administracao/administracao_provider.dart';
import '../../config/ambiente.dart';
import '../../sessao/sessao_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';
import '../../widgets/formulario.dart';

/// Os formulários da tela de Administração (card 4.7). Todos devolvem um
/// texto não nulo ao fechar com sucesso, para a aba mostrar a confirmação
/// efêmera certa (design-system §5.8).
///
/// Nenhum deles verifica regra: submete e traduz o erro pelo código
/// (card 2.6 decisão 2). O que se valida aqui é formato — obrigatório,
/// e-mail, o valor de um parâmetro pelo tipo.

void _recarregar(WidgetRef ref) =>
    ref.read(versaoAdministracaoProvider.notifier).incrementar();

/// Textos de consequência (design-system §5.4 e §7.3; acesso-autenticacao §6).
const avisoConvite =
    'A pessoa recebe um e-mail com o link do convite e, ao abrir, define a '
    'senha. Sem perfil ela entra e não vê nada — marque ao menos um.';
const avisoDesativar =
    'Desativar nega tudo na hora, mas a sessão já aberta continua até o token '
    'expirar (1 h). Para cortar imediatamente, use "Ban user" no painel do '
    'Auth.';
const avisoEmailImutavel =
    'O e-mail é o endereço de acesso e só muda pelo próprio login da pessoa.';
const avisoPerfilInativo =
    'Perfil desativado não concede nada: quem só tem este perfil entra e não '
    'vê nada.';

const chaveCampoEmail = Key('campo_email');
const chaveCampoNome = Key('campo_nome');

// ---------------------------------------------------------------------------
// Convite
// ---------------------------------------------------------------------------

/// O botão "Convidar usuário" (docs/wireframes.md §15; acesso-autenticacao
/// §3.2). Chama a Edge Function e, com o id que ela devolve, já atribui os
/// perfis marcados — fechando no mesmo ato a janela "convidado sem perfil".
class FormularioConvite extends ConsumerStatefulWidget {
  const FormularioConvite({super.key});

  @override
  ConsumerState<FormularioConvite> createState() => _FormularioConviteState();
}

class _FormularioConviteState extends ConsumerState<FormularioConvite> {
  final _chave = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _nome = TextEditingController();
  final _perfis = <String>{};

  @override
  void dispose() {
    _email.dispose();
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perfis = ref.watch(perfisProvider).value ?? const <Perfil>[];

    return FormularioIm360(
      titulo: 'Convidar usuário',
      chave: _chave,
      rotuloSalvar: 'Enviar convite',
      aviso: avisoConvite,
      campos: [
        TextFormField(
          key: chaveCampoEmail,
          controller: _email,
          style: Tipografia.corpo,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'E-mail *'),
          validator: (v) => (v == null || !v.contains('@'))
              ? 'Informe um e-mail válido.'
              : null,
        ),
        TextFormField(
          key: chaveCampoNome,
          controller: _nome,
          style: Tipografia.corpo,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Nome *',
            helperText: 'Como aparece no sistema; a pessoa não edita.',
          ),
          validator: validarObrigatorio,
        ),
        _SecaoPerfis(
          perfis: perfis,
          marcados: _perfis,
          aoMudar: (id, marcado) =>
              setState(() => marcado ? _perfis.add(id) : _perfis.remove(id)),
        ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(administracaoRepositorioProvider);
        final id = await repositorio.convidar(
          email: _email.text,
          nome: _nome.text,
          // O link volta para a tela de definir senha; o `type=invite` que o
          // Auth acrescenta é o que a tela usa para dizer "conclua o cadastro"
          // (lib/config/link_inicial.dart).
          redirecionarPara: Ambiente.urlRedefinicaoSenha,
        );
        // Convidar de novo quem ainda não aceitou REENVIA o e-mail e devolve o
        // mesmo usuário (medido contra o GoTrue local): só entra o perfil que
        // ele ainda não tem, senão o insert repetido em usuario_perfil
        // devolveria 23505 depois de o convite já ter saído.
        final existentes =
            ref
                .read(usuariosAdminProvider)
                .value
                ?.where((u) => u.id == id)
                .firstOrNull
                ?.perfisIds ??
            const <String>{};
        final plano = PlanoPerfis(
          inserir: _perfis.difference(existentes),
          remover: const {},
        );
        if (!plano.vazio) await repositorio.definirPerfis(id, plano);
        _recarregar(ref);
        return 'convidado';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Usuário
// ---------------------------------------------------------------------------

class FormularioUsuario extends ConsumerStatefulWidget {
  const FormularioUsuario({super.key, required this.usuario});

  final UsuarioAdmin usuario;

  @override
  ConsumerState<FormularioUsuario> createState() => _FormularioUsuarioState();
}

class _FormularioUsuarioState extends ConsumerState<FormularioUsuario> {
  final _chave = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.usuario.nome);
  late bool _ativo = widget.usuario.ativo;
  late final Set<String> _perfis = Set.of(widget.usuario.perfisIds);

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final somenteLeitura = !permissoes.contains('admin.gerir_usuarios');
    final perfis = ref.watch(perfisProvider).value ?? const <Perfil>[];
    final usuario = widget.usuario;
    final desativando = usuario.ativo && !_ativo;

    return FormularioIm360(
      titulo: 'Usuário',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: desativando ? avisoDesativar : null,
      campos: [
        TextFormField(
          initialValue: usuario.email,
          readOnly: true,
          style: Tipografia.corpo,
          decoration: const InputDecoration(
            labelText: 'E-mail',
            helperText: avisoEmailImutavel,
            helperMaxLines: 3,
          ),
        ),
        TextFormField(
          key: chaveCampoNome,
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          subtitle: const Text(
            'Desativado não entra; o histórico do que fez fica.',
            style: Tipografia.apoio,
          ),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
        _SecaoPerfis(
          perfis: perfis,
          marcados: _perfis,
          somenteLeitura: somenteLeitura,
          aoMudar: (id, marcado) =>
              setState(() => marcado ? _perfis.add(id) : _perfis.remove(id)),
        ),
      ],
      aoSalvar: () async {
        final repositorio = ref.read(administracaoRepositorioProvider);
        final nome = _nome.text.trim();
        if (nome != usuario.nome || _ativo != usuario.ativo) {
          await repositorio.salvarUsuario(
            usuario.copiar(nome: nome, ativo: _ativo),
          );
        }
        final plano = planejarPerfis(usuario.perfisIds, _perfis);
        if (!plano.vazio) await repositorio.definirPerfis(usuario.id, plano);
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}

/// As caixas de perfil, compartilhadas pelo convite e pela edição. Perfil
/// desativado só aparece se a pessoa já o tem — para poder tirá-lo.
class _SecaoPerfis extends StatelessWidget {
  const _SecaoPerfis({
    required this.perfis,
    required this.marcados,
    required this.aoMudar,
    this.somenteLeitura = false,
  });

  final List<Perfil> perfis;
  final Set<String> marcados;
  final void Function(String id, bool marcado) aoMudar;
  final bool somenteLeitura;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final visiveis = [
      for (final p in perfis)
        if (p.id != null && (p.ativo || marcados.contains(p.id))) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Perfis', style: Tipografia.rotulo),
        Text(
          'A pessoa pode o que a união dos perfis marcados permite.',
          style: Tipografia.apoio.copyWith(color: cores.onSurfaceVariant),
        ),
        if (visiveis.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Dim.e8),
            child: Text(
              'Nenhum perfil ativo cadastrado.',
              style: Tipografia.apoio.copyWith(color: cores.error),
            ),
          ),
        for (final p in visiveis)
          CheckboxListTile(
            key: ValueKey('perfil-${p.codigo}'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            title: Text(
              p.ativo ? '${p.codigo} — ${p.nome}' : '${p.codigo} (desativado)',
              style: Tipografia.corpo,
            ),
            value: marcados.contains(p.id),
            onChanged: somenteLeitura
                ? null
                : (valor) => aoMudar(p.id!, valor == true),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Perfil
// ---------------------------------------------------------------------------

class FormularioPerfil extends ConsumerStatefulWidget {
  const FormularioPerfil({super.key, this.perfil});

  /// Nulo = novo perfil.
  final Perfil? perfil;

  @override
  ConsumerState<FormularioPerfil> createState() => _FormularioPerfilState();
}

class _FormularioPerfilState extends ConsumerState<FormularioPerfil> {
  final _chave = GlobalKey<FormState>();
  late final _codigo = TextEditingController(text: widget.perfil?.codigo ?? '');
  late final _nome = TextEditingController(text: widget.perfil?.nome ?? '');
  late bool _ativo = widget.perfil?.ativo ?? true;

  @override
  void dispose() {
    _codigo.dispose();
    _nome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final somenteLeitura = !permissoes.contains('admin.gerir_perfis');
    final perfil = widget.perfil;
    final editando = perfil != null;

    return FormularioIm360(
      titulo: editando ? 'Perfil' : 'Novo perfil',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: _ativo ? null : avisoPerfilInativo,
      campos: [
        TextFormField(
          controller: _codigo,
          readOnly: editando || somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Código *',
            helperText: editando
                ? 'Chave do perfil: não muda depois de criado — é o que o '
                      'histórico da matriz grava.'
                : 'Letras maiúsculas, dígitos e _ (ex.: COORDENACAO).',
            helperMaxLines: 3,
          ),
          validator: validarCodigoPerfil,
        ),
        TextFormField(
          key: chaveCampoNome,
          controller: _nome,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          decoration: const InputDecoration(labelText: 'Nome *'),
          validator: validarObrigatorio,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ativo', style: Tipografia.corpo),
          subtitle: const Text(
            'Desativado não concede nada, mesmo com a matriz intacta.',
            style: Tipografia.apoio,
          ),
          value: _ativo,
          onChanged: somenteLeitura
              ? null
              : (valor) => setState(() => _ativo = valor),
        ),
      ],
      aoSalvar: () async {
        final gravado = await ref
            .read(administracaoRepositorioProvider)
            .salvarPerfil(
              Perfil(
                id: perfil?.id,
                codigo: _codigo.text.trim().toUpperCase(),
                nome: _nome.text.trim(),
                ativo: _ativo,
              ),
            );
        _recarregar(ref);
        return gravado.id ?? 'salvo';
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Parâmetro
// ---------------------------------------------------------------------------

class FormularioParametro extends ConsumerStatefulWidget {
  const FormularioParametro({super.key, this.parametro});

  /// Nulo = novo parâmetro.
  final Parametro? parametro;

  @override
  ConsumerState<FormularioParametro> createState() =>
      _FormularioParametroState();
}

class _FormularioParametroState extends ConsumerState<FormularioParametro> {
  final _chave = GlobalKey<FormState>();
  late final _chaveParametro = TextEditingController(
    text: widget.parametro?.chave ?? '',
  );
  late final _valor = TextEditingController(
    text: widget.parametro == null
        ? ''
        : exibirValorParametro(widget.parametro!),
  );
  late final _descricao = TextEditingController(
    text: widget.parametro?.descricao ?? '',
  );
  late String _tipo = widget.parametro?.tipo ?? 'INTEIRO';

  @override
  void dispose() {
    _chaveParametro.dispose();
    _valor.dispose();
    _descricao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final permissoes = ref.watch(permissoesProvider);
    final somenteLeitura = !permissoes.contains('parametros.gerir');
    final parametro = widget.parametro;
    final editando = parametro != null;

    return FormularioIm360(
      titulo: editando ? 'Parâmetro' : 'Novo parâmetro',
      chave: _chave,
      somenteLeitura: somenteLeitura,
      aviso: avisoParametro(_chaveParametro.text.trim()),
      campos: [
        TextFormField(
          controller: _chaveParametro,
          readOnly: editando || somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: 'Chave *',
            helperText: editando
                ? 'É por ela que a regra lê o valor; não muda.'
                : 'snake_case, como as do seed (ex.: standby_alerta_dias).',
            helperMaxLines: 3,
          ),
          validator: validarChaveParametro,
          onChanged: (_) => setState(() {}),
        ),
        DropdownButtonFormField<String>(
          initialValue: _tipo,
          decoration: const InputDecoration(labelText: 'Tipo *'),
          items: [
            for (final tipo in tiposParametro.entries)
              DropdownMenuItem(value: tipo.key, child: Text(tipo.value)),
          ],
          onChanged: (editando || somenteLeitura)
              ? null
              : (valor) => setState(() => _tipo = valor ?? _tipo),
        ),
        TextFormField(
          key: const Key('campo_valor'),
          controller: _valor,
          readOnly: somenteLeitura,
          style: Tipografia.numero(Tipografia.corpo),
          keyboardType: _tipo == 'INTEIRO' || _tipo == 'DECIMAL'
              ? TextInputType.number
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: 'Valor *',
            helperText: switch (_tipo) {
              'DATA' => 'dd/mm/aaaa',
              'BOOLEANO' => 'true ou false',
              _ => null,
            },
          ),
          validator: (v) => validarValorParametro(_tipo, v),
        ),
        TextFormField(
          controller: _descricao,
          readOnly: somenteLeitura,
          style: Tipografia.corpo,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Descrição',
            helperText:
                'O que este valor decide — para quem for editar depois.',
          ),
        ),
      ],
      aoSalvar: () async {
        await ref
            .read(administracaoRepositorioProvider)
            .salvarParametro(
              Parametro(
                id: parametro?.id,
                chave: _chaveParametro.text.trim(),
                valor: normalizarValorParametro(_tipo, _valor.text),
                tipo: _tipo,
                descricao: _descricao.text,
              ),
            );
        _recarregar(ref);
        return 'salvo';
      },
    );
  }
}
