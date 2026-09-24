import 'dart:async';

import 'package:gestao_im360/rotina/rotina.dart';
import 'package:gestao_im360/rotina/rotina_repositorio.dart';

/// A rotina sob demanda do card 9.2,65, sem banco: devolve [resultado], lança
/// [erro] ou fica esperando [pendente] — o terceiro é o que prova que o botão
/// trava enquanto a rotina roda.
class RotinaFalsa implements RotinaRepositorio {
  RotinaFalsa({
    this.resultado = ResultadoRotina.executada,
    this.erro,
    this.pendente,
  });

  final ResultadoRotina resultado;
  final Object? erro;
  final Completer<void>? pendente;
  int chamadas = 0;

  @override
  Future<ResultadoRotina> executarAgora() async {
    chamadas++;
    final espera = pendente;
    if (espera != null) await espera.future;
    final falha = erro;
    if (falha != null) throw falha;
    return resultado;
  }
}
