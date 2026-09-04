/// A política de `retry` do projeto, decidida uma vez e não tela a tela
/// (revisão da fase 05, item A7).
library;

/// ⚠️ **O Riverpod 3 repete sozinho o provider que falhou**, com espera
/// crescente, até dez vezes. O estado passa por `AsyncError` e volta a
/// `AsyncLoading`: um `.when(error:)` — que casa pela classe — mostra a
/// mensagem e some, e a tela termina piscando entre erro e esqueleto. Medido no
/// card 5.9, na região de pendências do dashboard, e presente em todas as telas
/// de 4.4 a 5.9.
///
/// Devolver `null` desliga a repetição, e é a escolha certa aqui por duas
/// razões. A primeira é que **toda tela deste sistema já tem "Tentar de novo"**
/// (o quarto estado do wireframe §2.3): repetir sozinho não acrescenta recurso
/// nenhum, só tira de quem usa a informação de que algo falhou. A segunda é que
/// a falha típica deste app **não é transitória** — RLS, permissão revogada em
/// sessão aberta, erro de regra —, e repetir dez vezes uma consulta que a
/// política recusa esconde o diagnóstico atrás de um esqueleto que não termina.
///
/// Consequência para toda tela nova: `.when(error:)` volta a ser seguro. Ver
/// docs/design-system.md §5.6.
///
/// O widget test que exercita estado de erro **precisa** passar isto ao
/// `ProviderScope`, senão mede um mundo em que o provider se repete e a
/// asserção de `EstadoErro` fica intermitente.
Duration? semRetryAutomatico(int tentativa, Object erro) => null;
