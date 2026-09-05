import 'package:gestao_im360/certificados/certificados.dart';
import 'package:gestao_im360/certificados/certificados_repositorio.dart';

/// Repositório em memória — o teste injeta **dados**, não um cliente HTTP falso
/// (card 2.8 §9.3).
///
/// ⚠️ **A fila e o checklist são a MESMA fonte aqui dentro.** É a propriedade
/// que a tela 9 depende: marcar o financeiro no painel tem de mudar a marca na
/// linha da fila, e marcá-lo na lista tem de mudar o painel. Duas listas
/// escritas à mão ficariam livres para divergir dentro do próprio teste, e o
/// teste passaria a medir o contrário do que existe para medir — foi por isso
/// que a `VersaoCertificados` é uma só para as duas leituras.
///
/// A forma dos dados é a de `v_certificado_fila` sobre a fixture do banco
/// (`supabase/seed.sql`, medida em 06/09/2026), com os três casos que a tela
/// precisa distinguir:
///
///   • **último livro, sem checklist** — o aluno com um item pendente; é o caso
///     em que as cinco colunas vêm NULAS e a tela oferece abrir o checklist;
///   • **fim do curso, checklist começado** — pedagógico marcado, financeiro
///     não, certificado `NAO_PEDIDO`. É a linha da jornada nº 2 do monitor;
///   • **fim do curso, checklist completo** — os três itens e `ENTREGUE`, que é
///     a condição de `tg_certificado_sugere_formado` e o aviso que muda.
class CertificadosFalso implements CertificadosRepositorio {
  CertificadosFalso({
    required List<LinhaFilaCertificado> fila,
    required Map<String, ChecklistCertificado> checklists,
  }) : fila_ = List.of(fila),
       checklists_ = Map.of(checklists);

  factory CertificadosFalso.vazio() =>
      CertificadosFalso(fila: const [], checklists: const {});

  factory CertificadosFalso.fixture() {
    final checklists = <String, ChecklistCertificado>{
      'aluno-2': ChecklistCertificado(
        id: 'cc-2',
        alunoId: 'aluno-2',
        dataFimCurso: DateTime(2026, 8, 18),
        pedagogicoOk: true,
        financeiroOk: false,
        formatura: false,
        certificadoStatus: 'NAO_PEDIDO',
        autorias: {
          ItemChecklist.pedagogico: AutoriaItem(
            nome: 'Paula',
            quando: DateTime(2026, 8, 20),
          ),
          ItemChecklist.financeiro: const AutoriaItem(),
          ItemChecklist.formatura: const AutoriaItem(),
        },
      ),
      'aluno-3': ChecklistCertificado(
        id: 'cc-3',
        alunoId: 'aluno-3',
        dataFimCurso: DateTime(2026, 7, 2),
        pedagogicoOk: true,
        financeiroOk: true,
        formatura: true,
        certificadoStatus: 'ENTREGUE',
        autorias: {
          ItemChecklist.pedagogico: AutoriaItem(
            nome: 'Paula',
            quando: DateTime(2026, 7, 4),
          ),
          // Sem nome, com data: é a linha que a política de `usuario` esconde
          // de quem não tem `admin.ler` — a tela mostra só a data.
          ItemChecklist.financeiro: AutoriaItem(quando: DateTime(2026, 7, 5)),
          ItemChecklist.formatura: AutoriaItem(
            nome: 'Paula',
            quando: DateTime(2026, 7, 6),
          ),
        },
        autoriaStatus: AutoriaItem(nome: 'Caio', quando: DateTime(2026, 7, 8)),
      ),
    };

    return CertificadosFalso(
      fila: [
        const LinhaFilaCertificado(
          alunoId: 'aluno-1',
          alunoNome: 'Ana Paula Ribeiro',
          codigoSgf: '4433',
          alunoStatus: 'ATIVO',
          metodoId: 'm-int',
          metodoNome: 'Interativo',
          situacao: situacaoUltimoLivro,
          itensPendentes: 1,
        ),
        LinhaFilaCertificado(
          alunoId: 'aluno-2',
          alunoNome: 'Bianca Moraes',
          codigoSgf: '4501',
          alunoStatus: 'ATIVO',
          metodoId: 'm-int',
          metodoNome: 'Interativo',
          situacao: situacaoFim,
          itensPendentes: 0,
          checklistId: 'cc-2',
          dataFimCurso: DateTime(2026, 8, 18),
          pedagogicoOk: true,
          financeiroOk: false,
          formatura: false,
          certificadoStatus: 'NAO_PEDIDO',
        ),
        LinhaFilaCertificado(
          alunoId: 'aluno-3',
          alunoNome: 'Caio Prado',
          codigoSgf: '4102',
          alunoStatus: 'ACELERAR',
          metodoId: 'm-ing',
          metodoNome: 'Inglês',
          situacao: situacaoFim,
          itensPendentes: 0,
          checklistId: 'cc-3',
          dataFimCurso: DateTime(2026, 7, 2),
          pedagogicoOk: true,
          financeiroOk: true,
          formatura: true,
          certificadoStatus: 'ENTREGUE',
        ),
      ],
      checklists: checklists,
    );
  }

  List<LinhaFilaCertificado> fila_;
  final Map<String, ChecklistCertificado> checklists_;

  /// Erro a levantar na próxima leitura da fila — para exercitar o quarto
  /// estado (design-system §5.6).
  Object? erroDaFila;

  /// Erro a levantar na próxima escrita — é como o teste vê `SEM_PERMISSAO`
  /// chegar à tela sem inventar um cliente HTTP.
  Object? erroDaEscrita;

  /// O que a tela mandou, na ordem — a asserção de "chegou ao repositório com o
  /// item e o valor certos".
  final escritas = <String>[];

  @override
  Future<List<LinhaFilaCertificado>> fila() async {
    final erro = erroDaFila;
    if (erro != null) throw erro;
    return List.of(fila_);
  }

  @override
  Future<ChecklistCertificado?> checklist(String alunoId) async =>
      checklists_[alunoId];

  @override
  Future<void> abrirChecklist(String alunoId) async {
    _conferirErro();
    escritas.add('abrir:$alunoId');
    checklists_[alunoId] = ChecklistCertificado(
      id: 'cc-$alunoId',
      alunoId: alunoId,
      dataFimCurso: DateTime(2026, 9, 6),
      pedagogicoOk: false,
      financeiroOk: false,
      formatura: false,
      certificadoStatus: 'NAO_PEDIDO',
    );
    _sincronizarFila(alunoId);
  }

  @override
  Future<void> marcarItem(
    String alunoId, {
    required String item,
    required bool valor,
  }) async {
    _conferirErro();
    escritas.add('marcar:$alunoId:$item:$valor');
    final atual = checklists_[alunoId];
    if (atual == null) return;
    checklists_[alunoId] = ChecklistCertificado(
      id: atual.id,
      alunoId: atual.alunoId,
      dataFimCurso: atual.dataFimCurso,
      pedagogicoOk: item == ItemChecklist.pedagogico.codigo
          ? valor
          : atual.pedagogicoOk,
      financeiroOk: item == ItemChecklist.financeiro.codigo
          ? valor
          : atual.financeiroOk,
      formatura: item == ItemChecklist.formatura.codigo
          ? valor
          : atual.formatura,
      certificadoStatus: atual.certificadoStatus,
      autorias: atual.autorias,
      autoriaStatus: atual.autoriaStatus,
    );
    _sincronizarFila(alunoId);
  }

  @override
  Future<void> alterarStatus(String alunoId, {required String status}) async {
    _conferirErro();
    escritas.add('status:$alunoId:$status');
    final atual = checklists_[alunoId];
    if (atual == null) return;
    checklists_[alunoId] = ChecklistCertificado(
      id: atual.id,
      alunoId: atual.alunoId,
      dataFimCurso: atual.dataFimCurso,
      pedagogicoOk: atual.pedagogicoOk,
      financeiroOk: atual.financeiroOk,
      formatura: atual.formatura,
      certificadoStatus: status,
      autorias: atual.autorias,
      autoriaStatus: atual.autoriaStatus,
    );
    _sincronizarFila(alunoId);
  }

  void _conferirErro() {
    final erro = erroDaEscrita;
    if (erro != null) throw erro;
  }

  /// A fila reflete o checklist — é o que a view faz com o `left join`, e é o
  /// que faz a marca da lista e a do painel nunca discordarem.
  void _sincronizarFila(String alunoId) {
    final checklist = checklists_[alunoId];
    if (checklist == null) return;
    fila_ = [
      for (final l in fila_)
        if (l.alunoId != alunoId)
          l
        else
          LinhaFilaCertificado(
            alunoId: l.alunoId,
            alunoNome: l.alunoNome,
            codigoSgf: l.codigoSgf,
            alunoStatus: l.alunoStatus,
            metodoId: l.metodoId,
            metodoNome: l.metodoNome,
            situacao: l.situacao,
            itensPendentes: l.itensPendentes,
            checklistId: checklist.id,
            dataFimCurso: checklist.dataFimCurso,
            pedagogicoOk: checklist.pedagogicoOk,
            financeiroOk: checklist.financeiroOk,
            formatura: checklist.formatura,
            certificadoStatus: checklist.certificadoStatus,
          ),
    ];
  }
}
