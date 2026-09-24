#!/usr/bin/env node
// =============================================================================
// Ponta a ponta: o arquivo do EXTRATOR passando pelo IMPORTADOR — card 9.2,67
//
// O ACHADO (24/09/2026): o extrator (`extracao/`, card 9.2) e o importador
// (`fn_importacao_registrar/aplicar`, card 9.1) nunca se encontravam num teste.
// `supabase/tests/100_importacao.sql` usa JSON escrito à mão, e a suíte do
// extrator declara que cobre "a outra metade". Os dois só se conheciam pelo
// contrato de `docs/importacao.md` §3 — e a primeira vez que um arquivo real do
// extrator passaria pelo importador seria no dry-run do 9.4, com a planilha e
// as pessoas na sala.
//
// E a primeira execução deste teste achou DUAS vezes o que ele existe para
// achar, com a PRÓPRIA fixture do extrator:
//
//   • o importador REPROVA o arquivo (V10, SALDO_NEGATIVO em INTERATIVO/2 — um
//     ajuste −1 e uma saída −1 sem entrada nenhuma, o histórico que começa
//     depois do estoque inicial), e o extrator não dizia nada;
//   • resolvido o saldo, a APLICAÇÃO falha inteira com BLOCO_LOTADO "0 de 0
//     vagas": o arquivo traz a sala do laboratório com capacidade nominal 10 e
//     nenhum PC, e no sistema a vaga é contada pelos PCs operacionais. A
//     validação passava — o susto seria no botão "Aplicar" do dry-run.
//
// Desde o 9.2,67 o extrator anuncia os dois (SALDO_NEGATIVO e SALA_SEM_PC).
//
// Por isso DOIS cenários, e o contrato que cada um prova:
//
//   A. a fixture como está — o importador reprova, e TODO erro que ele acha
//      já estava no relatório do extrator, com o mesmo código e a mesma chave.
//      Nenhuma surpresa no dry-run: é essa a propriedade;
//   B. a fixture com a entrada de abertura, e os PCs da sala cadastrados ANTES
//      (pelo próprio importador, numa pré-carga só de `sala` + `pc` — o caminho
//      que o teste presume para a virada, a confirmar no 9.3) — o CLI de verdade
//      escreve o JSON no disco, o importador o recebe VALIDADA sem ERRO nenhum,
//      aplica, o sistema fica com o que o arquivo trouxe (entidade por
//      entidade), e o MESMO arquivo, registrado e aplicado de novo, não duplica.
//
// Onde: na unidade MATRIZ, a real da configuração (migração do card 3.6) — é
// nela que a virada do 9.7 vai importar, com os métodos, perfis e parâmetros de
// produção, e no stack local ela não tem dado de negócio nenhum. A escola-
// fixture (ESCOLA_A/B) fica de fora: os totais "no sistema" dela misturariam o
// que já existe com o que chegou. Cada cenário roda numa transação com
// ROLLBACK: nada daqui sobrevive.
//
// Roda a partir da RAIZ do repositório, contra o stack local (`supabase
// start` + `db reset`):   node supabase/tests_ponta_a_ponta/extrator_importador.mjs
// Sai 0 verde; qualquer outro código reprova o job `banco` do testes.yml.
// =============================================================================

import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { principal } from '../../extracao/extrair.mjs';
import { SALA_LABORATORIO_CAPACIDADE, SALA_LABORATORIO_PADRAO } from '../../extracao/layout.mjs';
import { comoXlsx } from '../../extracao/test/construir-xlsx.mjs';
import { SNAPSHOT, planilha } from '../../extracao/test/fixture.mjs';

const DB_URL = process.env.SUPABASE_DB_URL ?? 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const EMAIL = 'direcao-ponta-a-ponta@matriz.test';

/** A entrada de abertura que fecha o saldo de INTERATIVO/2 na fixture. */
const ABERTURA = [['2026-02-01', 2, 5]];

/**
 * Os PCs do laboratório, cadastrados ANTES do arquivo do extrator — que não os
 * traz (a aba PCS não está mapeada). A sala tem o MESMO nome da que o extrator
 * presume, e é reconhecida por ele na importação seguinte.
 */
const PRE_CARGA = JSON.stringify({
  sala: [{ nome: SALA_LABORATORIO_PADRAO, tipo: 'LABORATORIO', capacidade_nominal: SALA_LABORATORIO_CAPACIDADE }],
  pc: Array.from({ length: SALA_LABORATORIO_CAPACIDADE }, (_, i) => ({
    sala: SALA_LABORATORIO_PADRAO,
    identificador: `PC-${String(i + 1).padStart(2, '0')}`,
  })),
});

/**
 * Os ERROs que a fixture do extrator planta DE PROPÓSITO e que não impedem o
 * arquivo de entrar: as quatro abas ainda sem mapa de colunas (ficam FORA do
 * arquivo, que é o comportamento certo) e a aluna de INGLÊS num bloco de
 * INTERATIVO (a alocação é descartada ANTES do arquivo, justamente para o
 * trigger de admissão não derrubar a transação inteira) — e SALA_SEM_PC, que o
 * cenário B resolve com a pré-carga dos PCs. Qualquer ERRO de outro código
 * reprova.
 */
const ERROS_PLANTADOS = new Set(['ABA_NAO_MAPEADA', 'METODO_DIVERGENTE', 'SALA_SEM_PC']);

/**
 * Entidades cujo total no sistema passa do que o arquivo trouxe, e por quê.
 * `aluno_material`: o aluno entra com combo e `tg_aluno_trilha_inicial` (card
 * 6.2) gera a trilha no mesmo insert — o importador não a reimplementa (100 §5).
 * A conta que vale para ela é "o sistema tem PELO MENOS o que o arquivo trouxe".
 */
const GERADAS_POR_TRIGGER = new Set(['aluno_material']);

const falhas = [];
function conferir(condicao, mensagem) {
  if (!condicao) falhas.push(mensagem);
  return condicao;
}

/** O extrator de verdade: .xlsx em disco → CLI → JSON e CSV em disco. */
function extrairDoDisco(fonte) {
  const dir = mkdtempSync(join(tmpdir(), 'ponta-a-ponta-'));
  try {
    writeFileSync(
      join(dir, 'planilha.xlsx'),
      comoXlsx(Object.fromEntries(fonte.abas().map((aba) => [aba, fonte.linhas(aba)]))),
    );
    // Sai 1 por causa das abas não mapeadas (ver extracao/extrair.mjs) — é o
    // comportamento esperado com a fixture, e o relatório é conferido aqui.
    principal([join(dir, 'planilha.xlsx'), '--snapshot', SNAPSHOT, '--saida', dir], () => {});
    const texto = readFileSync(join(dir, `importacao-${SNAPSHOT}.json`), 'utf8');
    const erros = readFileSync(join(dir, `inconsistencias-${SNAPSHOT}.csv`), 'utf8')
      .split(/\r?\n/)
      .filter((linha) => linha.startsWith('ERRO;'))
      .map((linha) => {
        const [, codigo, , chave] = linha.split(';');
        return { codigo, chave };
      });
    return { texto, arquivo: JSON.parse(texto), erros };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function psql(entrada) {
  const argumentos = ['-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-f', '-'];
  const local = spawnSync('psql', [DB_URL, ...argumentos], { input: entrada, encoding: 'utf8' });
  if (!local.error) return local;
  // Sem psql no PATH (é o caso do Windows): o do container do stack local, como
  // os scripts de supabase/tests_concorrencia/.
  const config = readFileSync('supabase/config.toml', 'utf8');
  const projeto = /^project_id\s*=\s*"(.*)"/m.exec(config)?.[1];
  return spawnSync(
    'docker',
    ['exec', '-i', `supabase_db_${projeto}`, 'psql',
     'postgresql://postgres:postgres@127.0.0.1:5432/postgres', ...argumentos],
    { input: entrada, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 },
  );
}

/**
 * O importador de verdade, na pele da direção da MATRIZ: registra e aplica cada
 * texto da lista, em ordem (`lote1`, `lote2`…), e devolve o que cada etapa disse.
 */
function importar(textos) {
  if (textos.some((t) => t.includes('$arq$'))) {
    throw new Error('o JSON contém o delimitador $arq$ — trocar o delimitador do SQL');
  }
  const nome = `importacao-${SNAPSHOT}.json`;
  const lote = (n) => `(select (r #>> '{}')::uuid from t_saida where etapa = 'lote${n}')`;
  const rodada = (n, texto) => `
insert into t_saida
  select 'lote${n}', to_jsonb(public.fn_importacao_registrar('${nome}', '${SNAPSHOT}'::date, $arq$${texto}$arq$::jsonb));
insert into t_saida
  select 'ocorrencias${n}', coalesce(jsonb_agg(jsonb_build_object(
           'severidade', o.severidade, 'codigo', o.codigo, 'entidade', o.entidade,
           'valor', o.valor, 'mensagem', o.mensagem) order by o.severidade, o.codigo), '[]'::jsonb)
    from public.importacao_ocorrencia o
   where o.importacao_id = ${lote(n)};
insert into t_saida
  select 'status${n}', to_jsonb(i.status) from public.importacao i where i.id = ${lote(n)};
insert into t_saida
  select 'aplicar${n}', public.fn_importacao_aplicar(${lote(n)}, false)
   where (select r #>> '{}' from t_saida where etapa = 'status${n}') = 'VALIDADA';
`;

  const sql = `
begin;
create temporary table t_saida (etapa text primary key, r jsonb);
grant all on t_saida to authenticated;

select tests.criar_usuario('${EMAIL}', 'DIRECAO', (select id from public.unidade where codigo = 'MATRIZ'));
select set_config('request.jwt.claims',
  json_build_object('sub', (select id::text from public.usuario where email = '${EMAIL}'),
                    'role', 'authenticated')::text, true);
set local role authenticated;
${textos.map((texto, i) => rodada(i + 1, texto)).join('\n')}
reset role;
select etapa || chr(9) || r::text from t_saida order by etapa;
rollback;
`;

  const saida = psql(sql);
  if (saida.status !== 0) {
    throw new Error(`o SQL do importador falhou:\n${saida.stderr || saida.error}`);
  }
  return Object.fromEntries(
    saida.stdout
      .split(/\r?\n/)
      .filter((l) => l.includes('\t'))
      .map((l) => [l.slice(0, l.indexOf('\t')), JSON.parse(l.slice(l.indexOf('\t') + 1))]),
  );
}

// ---------------------------------------------------------------------------
// A. A fixture como está: reprovada, mas nenhuma surpresa
// ---------------------------------------------------------------------------
{
  const { texto, erros } = extrairDoDisco(planilha());
  const etapas = importar([texto]);
  const errosDoImportador = (etapas.ocorrencias1 ?? []).filter((o) => o.severidade === 'ERRO');

  conferir(etapas.status1 === 'REPROVADA',
    `A: a fixture tem saldo negativo e o lote ficou ${etapas.status1}, e não REPROVADA`);
  conferir(errosDoImportador.length > 0, 'A: o importador não achou erro nenhum na fixture com saldo negativo');
  for (const o of errosDoImportador) {
    conferir(
      erros.some((e) => e.codigo === o.codigo && e.chave === o.valor),
      `A: o importador achou ${o.codigo} em ${o.valor} ("${o.mensagem}") e o relatório do extrator não disse nada`,
    );
  }
  console.log(`A. fixture como está: importador ${etapas.status1}, com `
    + `${errosDoImportador.map((o) => `${o.codigo} ${o.valor}`).join(', ')} — anunciado pelo extrator`);
}

// ---------------------------------------------------------------------------
// B. Com a entrada de abertura: entra inteiro, e a segunda vez não duplica
// ---------------------------------------------------------------------------
{
  const { texto, arquivo, erros } = extrairDoDisco(planilha([], ABERTURA));
  const inesperados = erros.filter((e) => !ERROS_PLANTADOS.has(e.codigo));
  conferir(inesperados.length === 0,
    `B: o relatório do extrator tem ERRO fora dos plantados: ${inesperados.map((e) => `${e.codigo} ${e.chave}`).join(', ')}`);

  const entidades = Object.keys(arquivo).filter((k) => Array.isArray(arquivo[k]));
  conferir(entidades.length > 0, 'B: o extrator escreveu um arquivo sem entidade nenhuma');

  // lote1 = a pré-carga dos PCs; lote2 e lote3 = o MESMO arquivo do extrator.
  const etapas = importar([PRE_CARGA, texto, texto]);
  conferir(etapas.aplicar1?.status === 'APLICADA',
    `B: a pré-carga dos PCs não entrou: ${JSON.stringify(etapas.aplicar1 ?? etapas.ocorrencias1)?.slice(0, 300)}`);
  for (const n of [2, 3]) {
    const errosImp = (etapas[`ocorrencias${n}`] ?? []).filter((o) => o.severidade === 'ERRO');
    conferir(errosImp.length === 0,
      `B, rodada ${n}: o importador achou ERRO no arquivo do extrator: `
      + errosImp.map((o) => `${o.entidade}/${o.codigo} ${o.valor ?? ''}: ${o.mensagem}`).join(' | '));
    conferir(etapas[`status${n}`] === 'VALIDADA', `B, rodada ${n}: o lote ficou ${etapas[`status${n}`]}, e não VALIDADA`);
    conferir(etapas[`aplicar${n}`]?.status === 'APLICADA',
      `B, rodada ${n}: a aplicação devolveu ${JSON.stringify(etapas[`aplicar${n}`])?.slice(0, 300)}`);
  }

  const primeira = etapas.aplicar2?.totais?.no_sistema ?? {};
  const segunda = etapas.aplicar3?.totais?.no_sistema ?? {};

  // O sistema ficou com o que o arquivo trouxe — entidade por entidade.
  for (const entidade of entidades) {
    const noArquivo = arquivo[entidade].length;
    const noSistema = primeira[entidade];
    if (GERADAS_POR_TRIGGER.has(entidade)) {
      conferir(noSistema >= noArquivo, `B: ${entidade} tem ${noSistema} no sistema, menos que os ${noArquivo} do arquivo`);
    } else {
      conferir(noSistema === noArquivo, `B: ${entidade} tem ${noSistema} no sistema e ${noArquivo} no arquivo`);
    }
  }

  // A reexecução não duplica nada.
  conferir(JSON.stringify(segunda) === JSON.stringify(primeira),
    `B: a segunda importação do mesmo arquivo mudou os totais: ${JSON.stringify(primeira)} → ${JSON.stringify(segunda)}`);

  console.log(`B. com a abertura — arquivo: ${entidades.map((e) => `${e} ${arquivo[e].length}`).join(', ')}`);
  console.log(`   no sistema depois da 1ª: ${JSON.stringify(primeira)}`);
  console.log(`   no sistema depois da 2ª: ${JSON.stringify(segunda)}`);
}

if (falhas.length) {
  console.error('\nREPROVADO:');
  for (const f of falhas) console.error(`  • ${f}`);
  process.exitCode = 1;
} else {
  console.log('\nOK: o importador não achou nada que o extrator não tivesse dito; com a abertura, '
    + 'o arquivo entrou inteiro e a segunda importação não duplicou nada.');
}
