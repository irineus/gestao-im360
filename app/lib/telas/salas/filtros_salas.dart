import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infraestrutura/infraestrutura.dart';
import '../../infraestrutura/infraestrutura_provider.dart';
import '../../theme/dimensoes.dart';
import '../../theme/tipografia.dart';

/// Barra de filtros da aba de salas (design-system §5.3): busca, tipo e o chip
/// "Só ativas". O estado mora no provider, não aqui.
class FiltrosSalas extends ConsumerStatefulWidget {
  const FiltrosSalas({super.key});

  @override
  ConsumerState<FiltrosSalas> createState() => _FiltrosSalasState();
}

class _FiltrosSalasState extends ConsumerState<FiltrosSalas> {
  late final _busca = TextEditingController(
    text: ref.read(filtroSalasProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Limpar filtros" vem de fora (estado vazio): o campo acompanha.
    ref.listen(filtroSalasProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroSalasProvider);
    final controlador = ref.read(filtroSalasProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Nome da sala',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        DropdownMenu<String>(
          // A chave força o menu a acompanhar o "Limpar filtros".
          key: ValueKey('tipo-${filtro.tipo}'),
          width: 180,
          label: const Text('Tipo'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.tipo ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final tipo in tiposSala.entries)
              DropdownMenuEntry(value: tipo.key, label: tipo.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              tipo: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        FilterChip(
          label: const Text('Só ativas'),
          selected: filtro.soAtivas,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soAtivas: valor)),
        ),
      ],
    );
  }
}

/// Barra de filtros da aba de professores: busca e "Só ativos".
class FiltrosProfessores extends ConsumerStatefulWidget {
  const FiltrosProfessores({super.key});

  @override
  ConsumerState<FiltrosProfessores> createState() => _FiltrosProfessoresState();
}

class _FiltrosProfessoresState extends ConsumerState<FiltrosProfessores> {
  late final _busca = TextEditingController(
    text: ref.read(filtroProfessoresProvider).busca,
  );

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroProfessoresProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
    });
    final filtro = ref.watch(filtroProfessoresProvider);
    final controlador = ref.read(filtroProfessoresProvider.notifier);

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'Nome do professor',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
        FilterChip(
          label: const Text('Só ativos'),
          selected: filtro.soAtivos,
          onSelected: (valor) =>
              controlador.definir(filtro.copiar(soAtivos: valor)),
        ),
      ],
    );
  }
}

/// Barra de filtros da aba de manutenções (card 9.2,78): os cinco que o monitor
/// pediu — máquina, tipo, data, quem registrou e o que foi feito. As opções de
/// máquina vêm dos PCs da unidade; as de "Registrada por", do próprio
/// histórico.
class FiltrosManutencoes extends ConsumerStatefulWidget {
  const FiltrosManutencoes({super.key});

  @override
  ConsumerState<FiltrosManutencoes> createState() => _FiltrosManutencoesState();
}

class _FiltrosManutencoesState extends ConsumerState<FiltrosManutencoes> {
  // No `initState`, e não `late final` preguiçoso: dentro da folha do celular
  // o preguiçoso nascia no `dispose`, com `ref.read` em widget desmontado
  // (armadilha do card 9.2,64, design-system §11 item 54).
  late final TextEditingController _busca;
  late final TextEditingController _de;
  late final TextEditingController _ate;

  @override
  void initState() {
    super.initState();
    final filtro = ref.read(filtroManutencoesProvider);
    _busca = TextEditingController(text: filtro.busca);
    _de = TextEditingController(text: _textoData(filtro.de));
    _ate = TextEditingController(text: _textoData(filtro.ate));
  }

  @override
  void dispose() {
    _busca.dispose();
    _de.dispose();
    _ate.dispose();
    super.dispose();
  }

  static String _textoData(DateTime? data) =>
      data == null ? '' : formatarData(data);

  /// O campo acompanha o provider ("Limpar filtros" vem de fora) sem apagar o
  /// que a pessoa ainda está digitando: só reescreve quando o texto, lido como
  /// data, diz outra coisa que o filtro.
  static void _acompanhar(TextEditingController campo, DateTime? valor) {
    final lido = lerData(campo.text);
    // Nulo com texto incompleto no campo é a pessoa digitando: fica.
    if (valor == null ? lido != null : lido != valor) {
      campo.text = _textoData(valor);
    }
  }

  /// Texto vazio desliga a ponta; data inválida também, e o campo diz por quê.
  static String? _erroData(String texto) =>
      texto.trim().isEmpty || lerData(texto) != null ? null : 'dd/mm/aaaa';

  @override
  Widget build(BuildContext context) {
    ref.listen(filtroManutencoesProvider, (_, novo) {
      if (_busca.text != novo.busca) _busca.text = novo.busca;
      _acompanhar(_de, novo.de);
      _acompanhar(_ate, novo.ate);
    });
    final filtro = ref.watch(filtroManutencoesProvider);
    final controlador = ref.read(filtroManutencoesProvider.notifier);
    final salas = {
      for (final s in ref.watch(salasProvider).value ?? const <Sala>[])
        s.id: s.nome,
    };
    final pcs = List.of(ref.watch(pcsProvider).value ?? const <Pc>[])
      ..sort((a, b) => a.identificador.compareTo(b.identificador));
    final autores = autoresDoHistorico(
      ref.watch(historicoManutencoesProvider).value ?? const [],
    );

    Widget campoData({
      required String rotulo,
      required TextEditingController campo,
      required FiltroManutencoes Function(DateTime? data) aplicar,
    }) => SizedBox(
      width: 150,
      child: TextField(
        controller: campo,
        style: Tipografia.numero(Tipografia.corpo),
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          labelText: rotulo,
          hintText: 'dd/mm/aaaa',
          errorText: _erroData(campo.text),
        ),
        onChanged: (texto) {
          // Redesenha para o `errorText` acompanhar a digitação.
          setState(() {});
          // Data incompleta DESLIGA a ponta: mantê-la com o último valor
          // válido filtraria por uma data que o campo não mostra mais.
          controlador.definir(aplicar(lerData(texto)));
        },
      ),
    );

    return Wrap(
      spacing: Dim.e8,
      runSpacing: Dim.e8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownMenu<String>(
          key: ValueKey('maquina-${filtro.pcId}-${pcs.length}'),
          width: 220,
          label: const Text('Máquina'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.pcId ?? '',
          enableFilter: true,
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todas'),
            for (final pc in pcs)
              DropdownMenuEntry(
                value: pc.id!,
                label: salas.length > 1 && salas[pc.salaId] != null
                    ? '${pc.identificador} · ${salas[pc.salaId]}'
                    : pc.identificador,
              ),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              pcId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        DropdownMenu<String>(
          key: ValueKey('tipo-${filtro.tipo}'),
          width: 180,
          label: const Text('Tipo'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.tipo ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final tipo in tiposManutencao.entries)
              DropdownMenuEntry(value: tipo.key, label: tipo.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              tipo: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        campoData(
          rotulo: 'De',
          campo: _de,
          aplicar: (data) =>
              ref.read(filtroManutencoesProvider).copiar(de: () => data),
        ),
        campoData(
          rotulo: 'Até',
          campo: _ate,
          aplicar: (data) =>
              ref.read(filtroManutencoesProvider).copiar(ate: () => data),
        ),
        DropdownMenu<String>(
          key: ValueKey('autor-${filtro.autorId}-${autores.length}'),
          width: 220,
          label: const Text('Registrada por'),
          textStyle: Tipografia.corpo,
          initialSelection: filtro.autorId ?? '',
          dropdownMenuEntries: [
            const DropdownMenuEntry(value: '', label: 'Todos'),
            for (final autor in autores.entries)
              DropdownMenuEntry(value: autor.key, label: autor.value),
          ],
          onSelected: (valor) => controlador.definir(
            filtro.copiar(
              autorId: () => (valor == null || valor.isEmpty) ? null : valor,
            ),
          ),
        ),
        SizedBox(
          width: 240,
          child: TextField(
            controller: _busca,
            style: Tipografia.corpo,
            decoration: InputDecoration(
              labelText: 'O que foi feito',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: filtro.busca.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          controlador.definir(filtro.copiar(busca: '')),
                    ),
            ),
            onChanged: (valor) =>
                controlador.definir(filtro.copiar(busca: valor)),
          ),
        ),
      ],
    );
  }
}
