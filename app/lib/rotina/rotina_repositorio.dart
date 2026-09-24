import 'package:supabase_flutter/supabase_flutter.dart';

import 'rotina.dart';

/// A execução sob demanda da rotina diária (card 9.2,65). Interface para o
/// teste injetar o **resultado**, nunca um cliente HTTP falso (card 2.8 §9.3).
abstract interface class RotinaRepositorio {
  /// `fn_rotina_diaria_executar()` — a rotina da unidade de quem chama.
  Future<ResultadoRotina> executarAgora();
}

class RotinaRepositorioSupabase implements RotinaRepositorio {
  RotinaRepositorioSupabase(this._cliente);

  final SupabaseClient _cliente;

  @override
  Future<ResultadoRotina> executarAgora() async =>
      ResultadoRotina.deTexto(await _cliente.rpc('fn_rotina_diaria_executar'));
}
