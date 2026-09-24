/// A rotina diária sob demanda (card 9.2,65).
///
/// A rotina da madrugada (`rt_diaria`, 03:10 de São Paulo) calcula projeção,
/// pedido sugerido, capacidades, REP e pendências. Depois de uma importação —
/// no dry-run do 9.4 e na virada do 9.7 — esperar a madrugada deixava a direção
/// sem nada disso até o dia seguinte. `fn_rotina_diaria_executar()` roda a
/// rotina da unidade de quem chama, na hora, e só para quem tem
/// [permissaoRecalcular].
library;

/// A mesma permissão de mexer nos parâmetros que a rotina lê — hoje só da
/// direção. Nenhum código novo: o catálogo fica em 50 (critério 1 do marco 4.8).
const permissaoRecalcular = 'parametros.gerir';

/// O que `fn_rotina_diaria_executar()` devolve. Quem chega com a rotina da
/// unidade já rodando (o cron, ou outro clique) não espera nem recebe erro:
/// recebe [jaEmExecucao] na hora (`pg_try_advisory_xact_lock`).
enum ResultadoRotina {
  executada,
  jaEmExecucao;

  static ResultadoRotina deTexto(Object? texto) => switch (texto) {
    'EXECUTADA' => executada,
    'JA_EM_EXECUCAO' => jaEmExecucao,
    _ => throw FormatException('Resultado da rotina desconhecido: $texto'),
  };
}

const rotuloRecalcularAgora = 'Recalcular agora';
const rotuloRecalculando = 'Recalculando…';

/// Por que o botão fica desabilitado enquanto roda (design-system §5.7).
const motivoRecalculando = 'A rotina está rodando — espere ela terminar.';

const tituloRotinaExecutada = 'Recalculado agora';
const mensagemRotinaExecutada =
    'A rotina diária desta unidade rodou agora: projeção, pedido sugerido, '
    'capacidades e pendências já estão atualizados. A da madrugada continua '
    'rodando normalmente.';

const tituloRotinaEmExecucao = 'Já está recalculando';
const mensagemRotinaEmExecucao =
    'A rotina diária desta unidade já está em execução — a da madrugada ou '
    'outro clique. Espere um minuto e abra a tela de novo para ver o '
    'resultado.';

const tituloRotinaNaoExecutada = 'Não foi possível recalcular';

/// No resultado da Importação aplicada: o que a rotina da madrugada
/// calcularia, e que a direção pode pedir agora.
const textoRecalcularDepoisDeAplicar =
    'Projeção, pedido sugerido e pendências são calculados pela rotina da '
    'madrugada. Para vê-los já com os dados importados, recalcule agora.';
