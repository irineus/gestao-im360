import 'package:flutter/material.dart';

/// Catálogo das rotas e o **conjunto mínimo** de permissões de cada uma.
///
/// Fonte: docs/permissoes-matriz.md §6. O conjunto é o que faz a tela mostrar
/// número certo, não a permissão óbvia — a RLS reduz linhas em silêncio, então
/// uma tela aberta com permissão parcial não dá erro, dá um número menor
/// (card 2.3 §3.4).
///
/// A guarda do app existe para não oferecer o que vai falhar; quem decide é o
/// banco (docs/wireframes.md §2.2).
class Rota {
  const Rota({
    required this.id,
    required this.caminho,
    required this.titulo,
    required this.exige,
    this.icone,
    this.grupo = GrupoMenu.nenhum,
    this.publica = false,
  });

  final String id;
  final String caminho;
  final String titulo;

  /// Conjunto mínimo de permissões. Vazio + [publica] = rota sem sessão.
  final Set<String> exige;

  final IconData? icone;
  final GrupoMenu grupo;
  final bool publica;

  /// Aparece no menu lateral / gaveta quando pertence a um grupo.
  bool get noMenu => grupo != GrupoMenu.nenhum;
}

/// Os três blocos do menu lateral, na ordem do wireframe (docs/wireframes.md
/// §3.1) — frequência de uso da operação diária, não a numeração do plano.
enum GrupoMenu { nenhum, operacao, material, administracao }

/// Rotas sem sessão.
const rotaLogin = Rota(
  id: 'login',
  caminho: '/entrar',
  titulo: 'Entrar',
  exige: {},
  publica: true,
);

const rotaRedefinirSenha = Rota(
  id: 'redefinir_senha',
  caminho: '/redefinir-senha',
  titulo: 'Redefinir senha',
  exige: {},
  publica: true,
);

/// Seleção de unidade — tela 1 do card 2.4 §6. Na v1 é pulada em silêncio
/// (uma unidade só, card 2.6 decisão (g)); existe no fluxo para a Fase 11 não
/// redesenhar o login.
const rotaSelecaoUnidade = Rota(
  id: 'selecao_unidade',
  caminho: '/unidade',
  titulo: 'Escolher unidade',
  exige: {'unidades.ler'},
);

/// As 13 telas do plano §7, na ordem do menu (docs/wireframes.md §3.1).
/// Os conjuntos são cópia literal da tabela de docs/permissoes-matriz.md §6.
const rotasAplicacao = <Rota>[
  Rota(
    id: 'dashboard',
    caminho: '/',
    titulo: 'Dashboard',
    icone: Icons.dashboard_outlined,
    grupo: GrupoMenu.operacao,
    exige: {
      'alunos.ler',
      'materiais.ler',
      'turmas.ler',
      'salas.ler',
      'pendencias.ler',
    },
  ),
  Rota(
    id: 'alunos',
    caminho: '/alunos',
    titulo: 'Alunos',
    icone: Icons.people_outline,
    grupo: GrupoMenu.operacao,
    exige: {'alunos.ler', 'materiais.ler'},
  ),
  // Tela 3b — a aba Trilha da ficha. Não é item de menu, mas é rota guardada:
  // sem `estoque.ler` o saldo lido é 0 para todo material e a entrega seria
  // recusada por falta de estoque que existe (card 2.4, §"duas permissões de
  // leitura que a matriz teve de abrir para todos").
  Rota(
    id: 'aluno_trilha',
    caminho: '/alunos/:id/trilha',
    titulo: 'Trilha do aluno',
    exige: {'alunos.ler', 'materiais.ler', 'estoque.ler'},
  ),
  Rota(
    id: 'turmas',
    caminho: '/turmas',
    titulo: 'Turmas',
    icone: Icons.grid_view_outlined,
    grupo: GrupoMenu.operacao,
    exige: {'turmas.ler', 'salas.ler', 'professores.ler', 'materiais.ler'},
  ),
  Rota(
    id: 'turmas_modular',
    caminho: '/turmas-modular',
    titulo: 'Turmas Modular',
    icone: Icons.view_module_outlined,
    grupo: GrupoMenu.operacao,
    exige: {'turmas.ler', 'salas.ler', 'materiais.ler'},
  ),
  Rota(
    id: 'pendencias',
    caminho: '/pendencias',
    titulo: 'Pendências',
    icone: Icons.flag_outlined,
    grupo: GrupoMenu.operacao,
    exige: {'pendencias.ler'},
  ),
  Rota(
    id: 'materiais',
    caminho: '/materiais',
    titulo: 'Materiais e estoque',
    icone: Icons.inventory_2_outlined,
    grupo: GrupoMenu.material,
    exige: {'materiais.ler', 'estoque.ler'},
  ),
  Rota(
    id: 'compras',
    caminho: '/compras',
    titulo: 'Compras',
    icone: Icons.shopping_cart_outlined,
    grupo: GrupoMenu.material,
    exige: {'materiais.ler', 'estoque.ler', 'alunos.ler', 'compras.ler'},
  ),
  Rota(
    id: 'projecao',
    caminho: '/projecao',
    titulo: 'Projeção',
    icone: Icons.timeline_outlined,
    grupo: GrupoMenu.material,
    exige: {'materiais.ler', 'estoque.ler', 'alunos.ler'},
  ),
  Rota(
    id: 'certificados',
    caminho: '/certificados',
    titulo: 'Certificados',
    icone: Icons.workspace_premium_outlined,
    grupo: GrupoMenu.material,
    exige: {'certificados.ler', 'alunos.ler'},
  ),
  Rota(
    id: 'salas',
    caminho: '/salas',
    titulo: 'Salas e PCs',
    icone: Icons.desktop_windows_outlined,
    grupo: GrupoMenu.material,
    exige: {'salas.ler', 'professores.ler'},
  ),
  Rota(
    id: 'administracao',
    caminho: '/administracao',
    titulo: 'Administração',
    icone: Icons.settings_outlined,
    grupo: GrupoMenu.administracao,
    exige: {'admin.ler'},
  ),
  // Tela 13 — "admin.ler + os domínios do que se importa". Os domínios entram
  // no card 9.1, quando existir o que importar; guardar hoje pelo que já se
  // sabe é melhor do que guardar por nada.
  Rota(
    id: 'importacao',
    caminho: '/importacao',
    titulo: 'Importação',
    icone: Icons.upload_file_outlined,
    grupo: GrupoMenu.administracao,
    exige: {'admin.ler'},
  ),
];

/// A ficha do aluno (card 4.6) mora sob `/alunos`, guardada pelo mesmo
/// conjunto da lista — é a tela 3 do card 2.4 §6 ("lista e ficha"), não uma
/// rota nova; a aba Trilha é a 3b, acima.
const caminhoAlunos = '/alunos';
String caminhoFichaAluno(String id) => '$caminhoAlunos/$id';

/// Todas as rotas guardadas, incluindo a seleção de unidade — é a tabela que o
/// teste `guardas_rota_test.dart` percorre (card 2.8 §9.1).
const rotasGuardadas = <Rota>[rotaSelecaoUnidade, ...rotasAplicacao];

/// A rota abre se, e somente se, o usuário tem **todas** as permissões do
/// conjunto mínimo. Faltando qualquer uma, não abre.
bool podeAbrir(Rota rota, Set<String> permissoes) =>
    rota.publica || rota.exige.every(permissoes.contains);

/// O que falta para abrir — é o diagnóstico que a tela "Sem acesso" mostra
/// (docs/wireframes.md §2.3.4).
Set<String> permissoesFaltantes(Rota rota, Set<String> permissoes) =>
    rota.exige.difference(permissoes);

/// Primeira rota de aplicação que o usuário consegue abrir.
///
/// Existe porque o Dashboard exige cinco permissões: um perfil enxuto entra e
/// não abre a tela inicial. Cair no login de novo, ou numa tela de erro, seria
/// dizer que o acesso falhou quando ele funcionou.
Rota? primeiraRotaPermitida(Set<String> permissoes) {
  for (final rota in rotasAplicacao) {
    if (rota.noMenu && podeAbrir(rota, permissoes)) return rota;
  }
  return null;
}

/// Itens do menu para o usuário — item sem o conjunto mínimo não é renderizado
/// (docs/wireframes.md §2.2).
List<Rota> menuPara(Set<String> permissoes) => [
  for (final rota in rotasAplicacao)
    if (rota.noMenu && podeAbrir(rota, permissoes)) rota,
];

/// Os quatro itens da barra inferior do mobile (docs/wireframes.md §3.2):
/// Alunos · Turmas · Pendências · Mais. "Alunos" primeiro porque a jornada mais
/// frequente do monitor é aluno → ficha → Trilha → Registrar entrega.
const idsBarraInferior = <String>['alunos', 'turmas', 'pendencias'];
