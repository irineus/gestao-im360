import 'package:gestao_im360/administracao/administracao.dart';
import 'package:gestao_im360/administracao/administracao_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP
/// falso (card 2.8 §9.3). A forma dos dados é a da camada `acesso` da
/// escola-fixture (card 3.4.5, `supabase/seed.sql`): os quatro perfis do seed
/// mais `ARQUIVADO` (desativado), um usuário por perfil, um sem perfil e um
/// desativado; um recorte do catálogo de 50 códigos, suficiente para os 12
/// domínios não serem todos iguais; os parâmetros que a tela exercita; e o
/// histórico do card 4.7.5 com uma concessão do seed e uma remoção de gente.
class AdministracaoFalso implements AdministracaoRepositorio {
  AdministracaoFalso({
    List<UsuarioAdmin>? usuarios,
    List<Perfil>? perfis,
    List<Permissao>? permissoes,
    Map<String, Set<String>>? matriz,
    List<Parametro>? parametros,
    List<LinhaHistoricoMatriz>? historico,
  }) : usuarios_ = List.of(usuarios ?? const []),
       perfis_ = List.of(perfis ?? const []),
       permissoes_ = List.of(permissoes ?? const []),
       matriz_ = {
         for (final e in (matriz ?? const {}).entries) e.key: Set.of(e.value),
       },
       parametros_ = List.of(parametros ?? const []),
       historico_ = List.of(historico ?? const []);

  factory AdministracaoFalso.fixture() {
    const perfis = [
      Perfil(id: 'p-direcao', codigo: 'DIRECAO', nome: 'Direção'),
      Perfil(id: 'p-pedagogico', codigo: 'PEDAGOGICO', nome: 'Pedagógico'),
      Perfil(id: 'p-secretaria', codigo: 'SECRETARIA', nome: 'Secretaria'),
      Perfil(id: 'p-monitor', codigo: 'MONITOR', nome: 'Monitor'),
      Perfil(
        id: 'p-arquivado',
        codigo: 'ARQUIVADO',
        nome: 'Perfil desativado',
        ativo: false,
      ),
    ];
    const permissoes = [
      Permissao(
        id: 'pm-admin-ler',
        codigo: 'admin.ler',
        descricao: 'Ler usuário, perfil, permissão, matriz e atribuições',
        dominio: 'admin',
      ),
      Permissao(
        id: 'pm-admin-usuarios',
        codigo: 'admin.gerir_usuarios',
        descricao: 'Criar/editar usuário; atribuir e remover perfis',
        dominio: 'admin',
      ),
      Permissao(
        id: 'pm-alunos-ler',
        codigo: 'alunos.ler',
        descricao: 'Ler aluno, histórico de status e trilha',
        dominio: 'alunos',
      ),
      Permissao(
        id: 'pm-alunos-reverter',
        codigo: 'alunos.reverter_status',
        descricao: 'Sair de FORMADO/CANCELADO (status terminal), com motivo',
        dominio: 'alunos',
      ),
      Permissao(
        id: 'pm-estoque-ajustar',
        codigo: 'estoque.ajustar',
        descricao: 'Ajustar o saldo com motivo obrigatório',
        dominio: 'estoque',
      ),
      Permissao(
        id: 'pm-compras-ler',
        codigo: 'compras.ler',
        descricao: 'Ler pedidos de compra e seus itens',
        dominio: 'compras',
      ),
      Permissao(
        id: 'pm-parametros-gerir',
        codigo: 'parametros.gerir',
        descricao: 'Criar/editar parâmetros da escola',
        dominio: 'parametros',
      ),
    ];
    final matriz = <String, Set<String>>{
      'p-direcao': {for (final p in permissoes) p.id},
      'p-pedagogico': {'pm-alunos-ler'},
      'p-secretaria': {'pm-alunos-ler', 'pm-estoque-ajustar', 'pm-compras-ler'},
      'p-monitor': {'pm-alunos-ler'},
      'p-arquivado': {'pm-alunos-ler'},
    };
    const usuarios = [
      UsuarioAdmin(
        id: 'u-direcao',
        nome: 'Direção A',
        email: 'direcao@escola-a.test',
        perfisIds: {'p-direcao'},
      ),
      UsuarioAdmin(
        id: 'u-secretaria',
        nome: 'Débora Lima',
        email: 'secretaria@escola-a.test',
        perfisIds: {'p-secretaria'},
      ),
      UsuarioAdmin(
        id: 'u-monitor',
        nome: 'Caio Prado',
        email: 'monitor@escola-a.test',
        perfisIds: {'p-monitor'},
      ),
      UsuarioAdmin(
        id: 'u-semperfil',
        nome: 'semperfil',
        email: 'semperfil@escola-a.test',
      ),
      // Convidada e ainda sem abrir o link — o único estado em que "Reenviar
      // convite" aparece (card 4.7,7). Com perfil, de propósito: convite
      // pendente e falta de perfil são coisas diferentes e a tela não pode
      // confundir as duas.
      UsuarioAdmin(
        id: 'u-convidada',
        nome: 'Marta Convidada',
        email: 'convidada@escola-a.test',
        perfisIds: {'p-pedagogico'},
        convitePendente: true,
      ),
      UsuarioAdmin(
        id: 'u-desativado',
        nome: 'Antigo Diretor',
        email: 'desativado@escola-a.test',
        ativo: false,
        perfisIds: {'p-direcao'},
      ),
    ];
    const parametros = [
      Parametro(
        id: 'pa-horizonte',
        chave: 'projecao_horizonte_dias',
        valor: '60',
        descricao: 'Horizonte da projeção de demanda, em dias',
      ),
      Parametro(
        id: 'pa-standby',
        chave: 'standby_alerta_dias',
        valor: '30',
        descricao: 'Dias em STANDBY até gerar pendência',
      ),
      Parametro(
        id: 'pa-email',
        chave: 'direcao_inicial_email',
        valor: 'irineus@gmail.com',
        tipo: 'TEXTO',
        descricao: 'E-mail que recebe o perfil DIRECAO no primeiro acesso',
      ),
    ];
    final historico = [
      LinhaHistoricoMatriz(
        perfilCodigo: 'SECRETARIA',
        permissaoCodigo: 'compras.receber',
        acao: 'REMOVIDA',
        em: DateTime(2026, 9, 3, 10, 15),
        porNome: 'Direção A',
      ),
      LinhaHistoricoMatriz(
        perfilCodigo: 'SECRETARIA',
        permissaoCodigo: 'compras.receber',
        acao: 'CONCEDIDA',
        em: DateTime(2026, 9, 1, 20, 0),
      ),
    ];
    return AdministracaoFalso(
      usuarios: usuarios,
      perfis: perfis,
      permissoes: permissoes,
      matriz: matriz,
      parametros: parametros,
      historico: historico,
    );
  }

  final List<UsuarioAdmin> usuarios_;
  final List<Perfil> perfis_;
  final List<Permissao> permissoes_;
  final Map<String, Set<String>> matriz_;
  final List<Parametro> parametros_;
  final List<LinhaHistoricoMatriz> historico_;

  /// Os convites que a "Edge Function" recebeu: (email, nome, destino).
  final convites = <(String, String, String)>[];

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  /// Se definido, só o convite lança isto (a Edge Function recusou).
  Object? falhaAoConvidar;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Registro do que foi chamado, na ordem.
  final chamadas = <String>[];

  int _contador = 0;
  String _novoId(String prefixo) => '$prefixo-novo-${++_contador}';

  Future<T> _ler<T>(String nome, T valor) async {
    chamadas.add(nome);
    final falha = falhaAoLer;
    if (falha != null) throw falha;
    return valor;
  }

  Future<T> _gravar<T>(String nome, T Function() acao) async {
    chamadas.add(nome);
    final falha = falhaAoGravar;
    if (falha != null) throw falha;
    return acao();
  }

  @override
  Future<List<UsuarioAdmin>> usuarios() => _ler('usuarios', List.of(usuarios_));

  @override
  Future<UsuarioAdmin> salvarUsuario(UsuarioAdmin usuario) =>
      _gravar('salvarUsuario', () {
        final i = usuarios_.indexWhere((u) => u.id == usuario.id);
        usuarios_[i] = usuario;
        return usuario;
      });

  @override
  Future<void> definirPerfis(String usuarioId, PlanoPerfis plano) =>
      _gravar('definirPerfis', () {
        final i = usuarios_.indexWhere((u) => u.id == usuarioId);
        final atuais = Set.of(usuarios_[i].perfisIds)
          ..removeAll(plano.remover)
          ..addAll(plano.inserir);
        usuarios_[i] = usuarios_[i].copiar(perfisIds: atuais);
      });

  @override
  Future<String> convidar({
    required String email,
    required String nome,
    required String redirecionarPara,
  }) async {
    chamadas.add('convidar');
    final falha = falhaAoConvidar ?? falhaAoGravar;
    if (falha != null) throw falha;
    convites.add((email, nome, redirecionarPara));
    // Como o GoTrue: convidar de novo quem já existe reenvia o e-mail e
    // devolve o mesmo usuário (medido contra o stack local no card 4.7).
    final existente = usuarios_.where(
      (u) => u.email.toLowerCase() == email.toLowerCase(),
    );
    if (existente.isNotEmpty) return existente.first.id;
    // O espelho do card 3.5: a linha de `usuario` nasce com o convite.
    final id = _novoId('u');
    usuarios_.add(
      UsuarioAdmin(id: id, nome: nome, email: email, convitePendente: true),
    );
    return id;
  }

  @override
  Future<List<Perfil>> perfis() => _ler('perfis', List.of(perfis_));

  @override
  Future<Perfil> salvarPerfil(Perfil perfil) => _gravar('salvarPerfil', () {
    if (perfil.id == null) {
      final novo = Perfil(
        id: _novoId('p'),
        codigo: perfil.codigo,
        nome: perfil.nome,
        ativo: perfil.ativo,
      );
      perfis_.add(novo);
      return novo;
    }
    perfis_[perfis_.indexWhere((p) => p.id == perfil.id)] = perfil;
    return perfil;
  });

  @override
  Future<List<Permissao>> permissoes() =>
      _ler('permissoes', List.of(permissoes_));

  @override
  Future<Map<String, Set<String>>> matriz() =>
      _ler('matriz', {for (final e in matriz_.entries) e.key: Set.of(e.value)});

  @override
  Future<void> marcar(String perfilId, String permissaoId) =>
      _gravar('marcar', () {
        matriz_.putIfAbsent(perfilId, () => {}).add(permissaoId);
      });

  @override
  Future<void> desmarcar(String perfilId, String permissaoId) =>
      _gravar('desmarcar', () {
        matriz_[perfilId]?.remove(permissaoId);
      });

  @override
  Future<List<Parametro>> parametros() =>
      _ler('parametros', List.of(parametros_));

  @override
  Future<Parametro> salvarParametro(Parametro parametro) =>
      _gravar('salvarParametro', () {
        if (parametro.id == null) {
          final novo = Parametro(
            id: _novoId('pa'),
            chave: parametro.chave,
            valor: parametro.valor,
            tipo: parametro.tipo,
            descricao: parametro.descricao,
          );
          parametros_.add(novo);
          return novo;
        }
        parametros_[parametros_.indexWhere((p) => p.id == parametro.id)] =
            parametro;
        return parametro;
      });

  @override
  Future<List<LinhaHistoricoMatriz>> historico() =>
      _ler('historico', List.of(historico_));
}
