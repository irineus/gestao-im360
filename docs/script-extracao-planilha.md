# Script de extração da planilha (protótipo para a migração)

Código Python usado na análise de 29–30/08/2026 para ler `Gestão Interativo.xlsx`. Serve de ponto de partida para a ferramenta de importação da Fase 6. Requer `openpyxl` (`pip install openpyxl`). O arquivo está no projeto como upload; em uma sessão Claude, obtenha o caminho local com `Projects.project_read("Gestão Interativo.xlsx")`.

Observações importantes para quem for evoluir o script:
- Carregar o workbook duas vezes: `load_workbook(path)` devolve fórmulas (as colunas de nome de livro são `ArrayFormula`, acesse `.text`); `load_workbook(path, data_only=True)` devolve os valores calculados.
- Nomes de abas com acento/espaço: `'Gerência'`, `'Ger. Apost'`, `'Ger. Inglês'`, `'Apost. Inglês'`, `'Ger. Modular'`, `'Apost. Modular'`, `'Terça'`, `'Sábado'`, `'Chef+Panificação'`, `'Combo Beleza'`, `'Corte e Costura'`, `'Depilação'`, `'Violão'`.
- Ver `claude/analise-planilha-entendimento.md`, Apêndice A, para o mapa de colunas.

```python
import openpyxl, collections, datetime, unicodedata
from openpyxl.worksheet.formula import ArrayFormula

PATH = 'gestao.xlsx'
wb  = openpyxl.load_workbook(PATH)                  # fórmulas
wbv = openpyxl.load_workbook(PATH, data_only=True)  # valores

def norm(s):
    return unicodedata.normalize('NFKD', str(s)).encode('ascii', 'ignore').decode().strip().lower()

# ---------- Catálogo de apostilas (por método) ----------
def catalogo(aba, metodo):
    ws = wbv[aba]; out = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        cod, nome, est, dem, ped = r[2], r[3], r[4], r[5], r[6]
        if cod is None or not nome: continue
        if str(nome).strip().upper() in ('FIM', 'NÃO RECEBEU'): continue
        if metodo == 'INTERATIVO' and str(nome).strip().endswith('MSE'): continue   # catálogo encerrado 31/08/2026
        out.append(dict(metodo=metodo, codigo=int(cod), nome=str(nome).strip(),
                        estoque=est, demanda=dem, pedido=ped))
    return out

# ---------- Movimentos de estoque ----------
def movimentos(aba, metodo):
    ws = wbv[aba]; saidas, entradas = [], []
    for r in ws.iter_rows(min_row=3, values_only=True):
        if r[8] is not None:   # SAÍDAS: I=quando J=cod L=qtd M=aluno
            saidas.append(dict(metodo=metodo, data=r[8], codigo=r[9], qtd=r[11], aluno=r[12]))
        if r[15] is not None:  # ENTRADAS: P=quando Q=cod S=qtd
            entradas.append(dict(metodo=metodo, data=r[15], codigo=r[16], qtd=r[18]))
    return saidas, entradas

# ---------- Alunos + trilha ----------
TECNICOS = {'MACRO', 'BALANÇO', 'FAKE 02'}

def alunos_interativo():
    ws = wbv['Gerência']; out = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        cod, nome = r[1], r[2]
        if cod is None or not nome or str(nome).strip().upper() in TECNICOS or str(cod).upper() in TECNICOS:
            continue
        trilha = []
        for i in range(9, 60, 3):            # J.. blocos de 3: código, nome(lookup), entregue
            if r[i] is not None:
                trilha.append(dict(ordem=len(trilha) + 1, codigo=int(r[i]), entregue=(r[i + 2] == 'SIM')))
        out.append(dict(metodo='INTERATIVO', codigo_sgf=cod, nome=str(nome).strip(),
                        prev_conclusao=r[3], status=r[4], livro_atual=r[5], proximo_livro=r[7],
                        conferido=(r[0] == 'SIM'), trilha=trilha))
    return out

def alunos_ingles():
    ws = wbv['Ger. Inglês']; out = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        cod, nome = r[1], r[2]
        if cod is None or not nome: continue
        trilha = [dict(ordem=k + 1, codigo=int(r[i]), entregue=(r[i + 2] == 'SIM'))
                  for k, i in enumerate((10, 13, 16, 19)) if r[i] is not None]
        out.append(dict(metodo='INGLES', codigo_sgf=cod, nome=str(nome).strip(), prev_conclusao=r[3],
                        status=r[4], livro_atual=r[5], prev_livro_atual=r[7], proximo_livro=r[8], trilha=trilha))
    return out

def alunos_modular():
    ws = wbv['Ger. Modular']; out = []
    for r in ws.iter_rows(min_row=3, values_only=True):
        cod, nome = r[1], r[2]
        if cod is None or not nome: continue
        out.append(dict(metodo='MODULAR', codigo_sgf=cod, nome=str(nome).strip(), prev_conclusao=r[3],
                        curso=r[4], status=r[5], livro_atual=r[6], modulo_atual=r[8],
                        prev_modulo=r[9], proximo_livro=r[10]))
    return out

# ---------- Turmas por horário ----------
DIAS = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado']
BLOCOS = [(1, 3, 12, 2), (1, 3, 12, 6), (1, 3, 12, 10), (14, 16, 25, 2), (14, 16, 25, 6), (14, 16, 25, 10)]
# (linha do cabeçalho, primeira linha, última linha, coluna do código)
INGLES = {('Quinta', None), ('Sexta', '20H'), ('Sábado', '8H'), ('Sábado', '10H')}  # regra do Dashboard

def turmas():
    out = []
    for dia in DIAS:
        ws = wbv[dia]
        for hdr_row, r0, r1, c in BLOCOS:
            cab = ws.cell(hdr_row, c).value            # ex.: "8H - CLAUDIR"
            if not cab or not str(cab).strip(): continue
            partes = [p.strip() for p in str(cab).split('-')]
            horario, professor = partes[0], (partes[1] if len(partes) > 1 else None)
            metodo = 'INGLES' if (dia == 'Quinta' or (dia, horario.upper().replace(' ', '')) in
                                  {(d, h) for d, h in INGLES if h}) else 'INTERATIVO'
            for r in range(r0, r1 + 1):
                cod = ws.cell(r, c).value
                if cod is None: continue
                tipo = ws.cell(r, c + 3).value
                if tipo == 'R': tipo = 'REP'                  # lançamento incorreto validado com o usuário
                out.append(dict(dia=dia, horario=horario, professor=professor, metodo=metodo,
                                codigo_sgf=cod, nome=ws.cell(r, c + 1).value,
                                prev_conclusao=ws.cell(r, c + 2).value, tipo=tipo))
    return out

# ---------- Relatório de inconsistências ----------
def inconsistencias():
    ger = {a['codigo_sgf']: a for a in alunos_interativo()}
    ing = {a['codigo_sgf']: a for a in alunos_ingles()}
    t = turmas()
    em_turma = collections.Counter(x['codigo_sgf'] for x in t)
    nomes_turma = {}
    for x in t: nomes_turma.setdefault(norm(x['nome']), set()).add(x['codigo_sgf'])
    rel = []
    for cod, a in {**ger, **ing}.items():
        if a['status'] in ('ATIVO', 'ACELERAR') and cod not in em_turma:
            outros = nomes_turma.get(norm(a['nome']), set())
            rel.append(('ALUNO_SEM_TURMA', cod, a['nome'], f"mesmo nome em turma com código {outros}" if outros else ''))
        if isinstance(a['prev_conclusao'], datetime.datetime) and \
           (a['prev_conclusao'].year > 2035 or a['prev_conclusao'] < datetime.datetime.now()) and a['status'] in ('ATIVO', 'ACELERAR'):
            rel.append(('PREVISAO_ATIPICA', cod, a['nome'], a['prev_conclusao'].date()))
    for cod in em_turma:
        if cod not in ger and cod not in ing:
            rel.append(('TURMA_SEM_CADASTRO', cod, '', ''))
    for cod, n in em_turma.items():
        if n > 1: rel.append(('MULTI_BLOCO', cod, '', f'{n} blocos (aceleração?)'))
    return rel

if __name__ == '__main__':
    for linha in inconsistencias(): print(linha)
```

Conferência esperada (snapshot de 29/08/2026): 161 linhas em Gerência (117 ATIVO, 41 ACELERAR, 1 TRANCADO), 71 em Ger. Inglês, 33 em Ger. Modular, 181 códigos distintos nas turmas, 37 em mais de um bloco, 23 ativos do Interativo sem turma, 234 saídas e 110 entradas em Ger. Apost.
