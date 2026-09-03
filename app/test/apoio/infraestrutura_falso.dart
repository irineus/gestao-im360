import 'package:gestao_im360/infraestrutura/infraestrutura.dart';
import 'package:gestao_im360/infraestrutura/infraestrutura_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP
/// falso (card 2.8 §9.3). A forma dos dados é a da camada `infra_fisica` da
/// escola-fixture (card 4.3, `supabase/seed.sql`): dez PCs operacionais no
/// Laboratório 1, seis no Laboratório 2 com um em manutenção e um desativado,
/// uma manutenção aberta sem substituto e uma fechada, três professores com
/// um inativo — e **nenhuma credencial**.
class InfraestruturaFalso implements InfraestruturaRepositorio {
  InfraestruturaFalso({
    List<Sala>? salas,
    List<Pc>? pcs,
    List<PcManutencao>? manutencoes,
    List<Professor>? professores,
  }) : salas_ = List.of(salas ?? const []),
       pcs_ = List.of(pcs ?? const []),
       manutencoes_ = List.of(manutencoes ?? const []),
       professores_ = List.of(professores ?? const []);

  factory InfraestruturaFalso.fixture() {
    final hoje = soData(DateTime.now());
    String dois(int n) => n.toString().padLeft(2, '0');
    return InfraestruturaFalso(
      salas: const [
        Sala(
          id: 's-lab1',
          nome: 'Laboratório 1',
          tipo: 'LABORATORIO',
          capacidadeNominal: 10,
        ),
        Sala(
          id: 's-lab2',
          nome: 'Laboratório 2',
          tipo: 'LABORATORIO',
          capacidadeNominal: 6,
        ),
        Sala(
          id: 's-ele',
          nome: 'Sala Eletricista',
          tipo: 'SALA_MODULAR',
          capacidadeNominal: 15,
        ),
      ],
      pcs: [
        for (var i = 1; i <= 10; i++)
          Pc(
            id: 'pc-lab1-${dois(i)}',
            salaId: 's-lab1',
            identificador: 'LAB1-${dois(i)}',
          ),
        for (var i = 1; i <= 4; i++)
          Pc(
            id: 'pc-lab2-${dois(i)}',
            salaId: 's-lab2',
            identificador: 'LAB2-${dois(i)}',
          ),
        const Pc(
          id: 'pc-lab2-05',
          salaId: 's-lab2',
          identificador: 'LAB2-05',
          status: 'MANUTENCAO',
        ),
        const Pc(
          id: 'pc-lab2-06',
          salaId: 's-lab2',
          identificador: 'LAB2-06',
          status: 'DESATIVADO',
        ),
      ],
      manutencoes: [
        PcManutencao(
          id: 'm-aberta',
          pcId: 'pc-lab2-05',
          tipo: 'CORRETIVA',
          dataInicio: hoje.subtract(const Duration(days: 3)),
          descricao: 'fonte queimada',
        ),
        PcManutencao(
          id: 'm-fechada',
          pcId: 'pc-lab1-01',
          tipo: 'PREVENTIVA',
          dataInicio: hoje.subtract(const Duration(days: 60)),
          dataFim: hoje.subtract(const Duration(days: 59)),
          descricao: 'limpeza e atualização',
        ),
      ],
      professores: const [
        Professor(id: 'prof-1', nome: 'Marcos Vieira'),
        Professor(id: 'prof-2', nome: 'Renata Alves'),
        Professor(id: 'prof-3', nome: 'Otávio Pacheco', ativo: false),
      ],
    );
  }

  final List<Sala> salas_;
  final List<Pc> pcs_;
  final List<PcManutencao> manutencoes_;
  final List<Professor> professores_;

  /// O "Vault" do falso: `pc_id` → par. Só o que o teste gravou.
  final credenciais = <String, CredencialPc>{};

  /// Se definido, toda **escrita** lança isto.
  Object? falhaAoGravar;

  /// Se definido, toda **leitura** lança isto.
  Object? falhaAoLer;

  /// Atraso de cada leitura (ver `CatalogoFalso`).
  Duration atrasoLeitura = Duration.zero;

  /// Registro do que foi chamado, na ordem.
  final chamadas = <String>[];

  int _contador = 0;
  String _novoId(String prefixo) => '$prefixo-novo-${++_contador}';

  Future<T> _ler<T>(String nome, T valor) async {
    chamadas.add(nome);
    if (atrasoLeitura > Duration.zero) await Future.delayed(atrasoLeitura);
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
  Future<List<Sala>> salas() => _ler('salas', List.of(salas_));

  @override
  Future<Sala> salvarSala(Sala sala) => _gravar('salvarSala', () {
    if (sala.id == null) {
      final nova = Sala(
        id: _novoId('s'),
        nome: sala.nome,
        tipo: sala.tipo,
        capacidadeNominal: sala.capacidadeNominal,
        ativo: sala.ativo,
      );
      salas_.add(nova);
      return nova;
    }
    salas_[salas_.indexWhere((s) => s.id == sala.id)] = sala;
    return sala;
  });

  @override
  Future<void> excluirSala(String id) =>
      _gravar('excluirSala', () => salas_.removeWhere((s) => s.id == id));

  @override
  Future<List<Pc>> pcs() => _ler('pcs', List.of(pcs_));

  @override
  Future<Pc> salvarPc(Pc pc) => _gravar('salvarPc', () {
    if (pc.id == null) {
      final novo = Pc(
        id: _novoId('pc'),
        salaId: pc.salaId,
        identificador: pc.identificador,
        status: pc.status,
        observacao: pc.observacao,
      );
      pcs_.add(novo);
      return novo;
    }
    pcs_[pcs_.indexWhere((p) => p.id == pc.id)] = pc;
    return pc;
  });

  @override
  Future<void> excluirPc(String id) =>
      _gravar('excluirPc', () => pcs_.removeWhere((p) => p.id == id));

  @override
  Future<List<PcManutencao>> manutencoes() =>
      _ler('manutencoes', List.of(manutencoes_));

  @override
  Future<PcManutencao> salvarManutencao(PcManutencao manutencao) =>
      _gravar('salvarManutencao', () {
        if (manutencao.id == null) {
          final nova = PcManutencao(
            id: _novoId('m'),
            pcId: manutencao.pcId,
            tipo: manutencao.tipo,
            dataInicio: manutencao.dataInicio,
            dataFim: manutencao.dataFim,
            descricao: manutencao.descricao,
            pcSubstitutoId: manutencao.pcSubstitutoId,
          );
          manutencoes_.add(nova);
          return nova;
        }
        manutencoes_[manutencoes_.indexWhere((m) => m.id == manutencao.id)] =
            manutencao;
        return manutencao;
      });

  @override
  Future<List<Professor>> professores() =>
      _ler('professores', List.of(professores_));

  @override
  Future<Professor> salvarProfessor(Professor professor) =>
      _gravar('salvarProfessor', () {
        if (professor.id == null) {
          final novo = Professor(
            id: _novoId('prof'),
            nome: professor.nome,
            ativo: professor.ativo,
          );
          professores_.add(novo);
          return novo;
        }
        professores_[professores_.indexWhere((p) => p.id == professor.id)] =
            professor;
        return professor;
      });

  @override
  Future<CredencialPc?> lerCredencial(String pcId) =>
      _ler('lerCredencial', credenciais[pcId]);

  @override
  Future<void> gravarCredencial(
    String pcId, {
    required String usuario,
    required String senha,
  }) => _gravar('gravarCredencial', () {
    credenciais[pcId] = CredencialPc(usuario: usuario, senha: senha);
    final i = pcs_.indexWhere((p) => p.id == pcId);
    pcs_[i] = pcs_[i].copiar(credencialEm: DateTime.now());
  });
}
