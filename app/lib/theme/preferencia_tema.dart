import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tema claro/escuro segue o sistema, com fixação local
/// (docs/design-system.md §11, decisão 9): preferência de exibição não é dado
/// de negócio e não vai para o banco.
final preferenciaTemaProvider = NotifierProvider<PreferenciaTema, ThemeMode>(
  PreferenciaTema.new,
);

class PreferenciaTema extends Notifier<ThemeMode> {
  static const _chave = 'tema';

  @override
  ThemeMode build() {
    _restaurar();
    return ThemeMode.system;
  }

  Future<void> _restaurar() async {
    // Sem plugin (widget test, plataforma sem suporte) a preferência degrada
    // para "segue o sistema": tema é exibição, não pode derrubar a tela.
    final String? salvo;
    try {
      salvo = (await SharedPreferences.getInstance()).getString(_chave);
    } catch (_) {
      return;
    }
    final modo = switch (salvo) {
      'claro' => ThemeMode.light,
      'escuro' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (ref.mounted) state = modo;
  }

  /// Alterna claro ⇄ escuro. Partindo de `system`, vai para o oposto do que
  /// está na tela — alternar tem de mudar alguma coisa.
  Future<void> alternar() async {
    final brilhoAtual = state == ThemeMode.system
        ? WidgetsBinding.instance.platformDispatcher.platformBrightness
        : (state == ThemeMode.dark ? Brightness.dark : Brightness.light);
    final novo = brilhoAtual == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    state = novo;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _chave,
        novo == ThemeMode.dark ? 'escuro' : 'claro',
      );
    } catch (_) {
      // Não fixa entre sessões; a troca desta sessão vale mesmo assim.
    }
  }
}
