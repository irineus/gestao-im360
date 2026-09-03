# Critério objetivo da virada REP: pontual → contínuo

**Card 2.5 — Fase 2 (Planejamento e Design).** Última atualização: 01/09/2026.

Fecha a pendência técnica nº 1 das Decisões vigentes, aberta em 31/08/2026 pelo card 1.7. A decisão
de negócio já estava tomada — *"reposição repõe aulas perdidas para manter os encontros previstos no
mês; enquanto o aluno consegue repor tudo no prazo são lançamentos pontuais com data, e quando não
consegue ele passa a REP contínuo na alocação"* — mas sem um critério computável ela não vira código.
Este documento dá o critério, as funções que o aplicam e o que o DDL precisa receber para suportá-lo.

É design, não implementação: nenhum arquivo de `supabase/migrations/` é criado aqui. A implementação
sai nos cards 5.1, 5.3 e 5.5 (mapa em §9).

> **Conferido contra o DDL e contra a especificação de funções.** Todo nome de tabela, coluna e
> função usado abaixo foi verificado em `docs/modelagem-dados-ddl.md` (card 2.1) e
> `docs/regras-negocio-funcoes.md` (card 2.2). O que exige alteração está isolado em §8 — nada é
> alterado por conta própria.

---

## 1. Decisões desta tarefa

| # | Decisão | Quem decidiu |
|---|---|---|
| 1 | A virada é **sugerida**, nunca automática: o banco abre a pendência `REP_VIRADA` e uma pessoa executa a conversão | Irineu, 01/09/2026 |
| 2 | O prazo de reposição é **30 dias corridos contados da aula perdida**, no parâmetro `rep_prazo_dias` | Irineu, 01/09/2026 |
| 3 | O critério de inviabilidade é **aritmético** (débito × capacidade semanal × semanas restantes), não um número fixo de reposições | este card |
| 4 | Faltar às próprias reposições é gatilho independente do débito (`rep_faltas_max`) | este card |
| 5 | A volta contínuo → pontual também é sugerida, com carência de `rep_janela_volta_dias` | este card |

**Por que sugerida e não automática.** Virar contínuo cria uma alocação permanente em
`bloco_aluno`, que consome vaga *toda semana* — não só nas datas das reposições. Uma virada
automática escolheria o bloco sozinha, poderia lotar um bloco de madrugada e, no caso pior,
esbarraria em `BLOCO_LOTADO` dentro da rotina `pg_cron`, falhando em silêncio para o usuário. O
card 2.2 já tinha previsto a pendência `REP_VIRADA` com resolução humana; esta decisão confirma
aquele desenho em vez de contrariá-lo.

---

## 2. O que o sistema sabe (e o que não sabe)

**Frequência/chamada por aula está fora do escopo** (plano, §2 — "Fora do escopo"). O sistema não
tem lista de presença: ele só fica sabendo de uma aula perdida quando alguém registra a reposição
dela em `bloco_aluno_reposicao`.

Consequência, assumida conscientemente: **o critério mede o que foi lançado, não o que aconteceu.**
Um aluno que falta e nunca tem reposição lançada não acumula débito e nunca é sugerido para REP
contínuo. Isso não é um defeito do critério — é o limite do escopo. O caminho para a falta entrar no
sistema é a secretaria lançar a reposição (`fn_reposicao_agendar`) ou marcar a falta na reposição já
agendada (`fn_reposicao_registrar(..., p_compareceu => false)`).

Dados disponíveis para o critério, todos já no DDL do card 2.1:

| Fonte | O que dá |
|---|---|
| `bloco_aluno_reposicao.status` | `PREVISTA` (agendada), `REALIZADA` (reposta), `FALTOU` (faltou à reposição — §8, ajuste 1 do card 2.2), `CANCELADA` |
| `bloco_aluno_reposicao.bloco_origem_id`, `.data_origem` | qual aula foi perdida — a identidade do débito |
| `bloco_aluno_reposicao.data` | quando a reposição foi/será feita |
| `bloco_aluno.tipo = 'REP'` + `ativo` | o aluno já está em REP contínuo |
| `bloco_aluno.tipo_desde` | desde quando (§8, ajuste 1 deste card) |

---

## 3. Definições computáveis

### 3.1 Aula perdida

Uma **aula perdida** é identificada pelo par `(bloco_origem_id, data_origem)`. Duas reposições da
mesma aula (a primeira cancelada, a segunda reagendada) são **um** débito, não dois — é por isso que
a contagem é por aula de origem e não por linha.

Reposição sem origem informada (`bloco_origem_id` ou `data_origem` nulos) é tratada como uma aula
perdida própria, identificada pelo `id` da linha:

```sql
coalesce(bloco_origem_id::text || '@' || data_origem::text, 'AVULSA@' || id::text)
```

Isso evita tornar `bloco_origem_id`/`data_origem` obrigatórios no DDL — a escola nem sempre sabe
qual encontro foi perdido, e exigir o dado produziria preenchimento inventado. O preço é que uma
reposição avulsa só se quita a si mesma: ela nunca é reagendada, é recriada.

### 3.2 Débito

Uma aula perdida está **quitada** quando existe alguma reposição dela com `status = 'REALIZADA'`.
Está **em aberto** em qualquer outro caso — `PREVISTA` (ainda vai acontecer), `FALTOU` (o aluno não
apareceu) ou `CANCELADA` (a reposição foi desmarcada e ninguém remarcou).

```
debito(aluno) = nº de aulas perdidas em aberto, com data posterior a rep_desde(aluno)
```

`rep_desde(aluno)` é o `tipo_desde` da alocação ativa de tipo `REP` do aluno, ou `-infinity` se ele
não estiver em REP contínuo. **A virada zera o relógio**: quem passa a comparecer toda semana está
repondo em regime, e o débito que motivou a virada não pode continuar pesando contra ele para
sempre — sem esse corte, um aluno que virou contínuo nunca mais poderia voltar a pontual.

A data de uma aula perdida é `data_origem`; para a reposição avulsa, é a própria `data`.

### 3.3 Viabilidade

O prazo de cada aula perdida é `data_origem + rep_prazo_dias`. O aluno consegue fazer, além dos
seus encontros regulares, no máximo `rep_capacidade_semanal` reposições por semana. A conta é feita
sobre a **aula mais antiga em aberto**, que é a que vence primeiro:

```
prazo_final   = data_da_aula_mais_antiga + rep_prazo_dias
semanas_uteis = greatest(ceil((prazo_final - current_date) / 7), 0)
inviavel      = debito > rep_capacidade_semanal * semanas_uteis
```

`ceil` e não `floor`: uma janela de 3 dias ainda pode conter o dia do bloco do aluno. O
arredondamento é deliberadamente **a favor do aluno** — a sugestão erra para o lado de não
incomodar ninguém à toa. Quando o prazo vence (`prazo_final <= current_date`), `semanas_uteis` é 0 e
qualquer débito passa a inviável, que é exatamente a leitura literal de "não conseguiu repor no
prazo".

Com os padrões (`rep_prazo_dias = 30`, `rep_capacidade_semanal = 1`):

| Situação | Débito | Dias até o prazo | Semanas | Veredito |
|---|---|---|---|---|
| Uma falta, lançada hoje | 1 | 30 | 5 | viável |
| Uma falta, 24 dias sem repor | 1 | 6 | 1 | viável |
| Uma falta, prazo vencido | 1 | 0 | 0 | **inviável** |
| Três faltas no mesmo mês, 18 dias depois | 3 | 12 | 2 | **inviável** |
| Seis faltas lançadas de uma vez | 6 | 30 | 5 | **inviável** |

### 3.4 Reincidência

Independente da aritmética: `rep_faltas_max` reposições com `status = 'FALTOU'` e `data` dentro dos
últimos `rep_prazo_dias` já bastam. Quem falta à própria reposição não está repondo pontualmente,
mesmo que o saldo ainda caiba no prazo — e é justamente a diferença entre `FALTOU` e `CANCELADA`
que torna esse gatilho possível (por isso o valor `FALTOU` é bloqueante, §8).

### 3.5 Volta: contínuo → pontual

O aluno em REP contínuo volta a ser pontual quando as três valem:

1. `debito = 0` (nenhuma aula perdida em aberto depois de `rep_desde`);
2. nenhuma reposição `FALTOU` nos últimos `rep_janela_volta_dias`;
3. `rep_desde <= current_date - rep_janela_volta_dias`.

A condição 3 é carência, e existe por um motivo concreto: a virada para contínuo cancela as
reposições `PREVISTA` do aluno e corta o relógio do débito, então **no instante seguinte à virada as
condições 1 e 2 já estariam satisfeitas** e a rotina sugeriria desfazer o que acabou de ser feito.
Sem a carência, o par de sugestões vira pingue-pongue diário.

---

## 4. Parâmetros

Seed do card 3.6, tabela `parametro`, todos ajustáveis na tela de Administração (card 4.7) e lidos
com `fn_param_int` (§2.3 do card 2.2 — parâmetro ausente é erro `PARAMETRO_AUSENTE`, nunca um
`default` escondido no código).

| chave | valor | tipo | descrição |
|---|---|---|---|
| `rep_prazo_dias` | `30` | INTEIRO | Prazo, em dias corridos a partir da aula perdida, para repor sem virar REP contínuo |
| `rep_capacidade_semanal` | `1` | INTEIRO | Quantas reposições por semana o aluno consegue fazer além dos encontros regulares |
| `rep_faltas_max` | `2` | INTEIRO | Faltas a reposições agendadas, na janela do prazo, que sugerem a virada por si sós |
| `rep_janela_volta_dias` | `30` | INTEIRO | Carência sem débito e sem falta para sugerir a volta a pontual |

`rep_capacidade_semanal = 1` é a leitura conservadora do plano: dois encontros por semana já
caracterizam **aceleração**, e reposição não é aceleração. Uma escola que queira permitir duas
reposições semanais muda o parâmetro, não o código.

---

## 5. Funções

### 5.1 Situação e veredito

```sql
create type public.tp_rep_situacao as (
  debito            integer,
  aula_mais_antiga  date,
  prazo_final       date,
  semanas_uteis     integer,
  capacidade        integer,
  faltas_recentes   integer,
  rep_desde         date,
  veredito          text     -- MANTER | SUGERIR_CONTINUO | SUGERIR_VOLTA
);

fn_rep_situacao(p_aluno_id uuid) → tp_rep_situacao   -- stable, security invoker
fn_rep_avaliar_virada(p_aluno_id uuid) → text        -- stable; (fn_rep_situacao(p_aluno_id)).veredito
```

`fn_rep_avaliar_virada` mantém **exatamente** a assinatura que o card 2.2 reservou como ponto de
extensão (`text`, com os três valores `MANTER`/`SUGERIR_CONTINUO`/`SUGERIR_VOLTA`); só o corpo deixa
de ser `MANTER` fixo. Nada mais no sistema muda.

`fn_rep_situacao` existe porque a pendência e a tela precisam dizer **por quê**: "3 aulas em aberto,
a mais antiga de 12/09, prazo até 12/10, cabem 2" é acionável; "sugerido virar contínuo" não é.

Corpo do veredito:

```sql
-- aluno fora de ATIVO/ACELERAR nunca é avaliado: tg_aluno_status_desaloca já
-- cancelou as reposições futuras dele, e débito de aluno inativo não é acionável.
if v_status not in ('ATIVO','ACELERAR') then
  return 'MANTER';
end if;

if v_rep_desde is null then                      -- aluno pontual hoje
  if v_debito > 0 and (v_inviavel or v_reincidente) then
    return 'SUGERIR_CONTINUO';
  end if;
else                                             -- aluno já em REP contínuo
  if v_debito = 0
     and v_faltas_na_janela_volta = 0
     and v_rep_desde <= current_date - v_janela_volta then
    return 'SUGERIR_VOLTA';
  end if;
end if;

return 'MANTER';
```

O débito é apurado em uma consulta só:

```sql
with rep as (
  select r.id, r.status, r.data, r.data_origem,
         coalesce(r.bloco_origem_id::text || '@' || r.data_origem::text,
                  'AVULSA@' || r.id::text) as aula
    from public.bloco_aluno_reposicao r
   where r.aluno_id = p_aluno_id
),
aula as (
  select aula,
         min(coalesce(data_origem, data)) as data_aula,
         bool_or(status = 'REALIZADA')    as quitada
    from rep
   group by aula
)
select count(*), min(data_aula)
  into v_debito, v_aula_mais_antiga
  from aula
 where not quitada
   and data_aula > coalesce(v_rep_desde, date '-infinity');
```

Ambas são `stable` e `security invoker` — enxergam pela RLS de quem chama, e pelo contexto de
rotina (`app.rotina`, §2.2 do card 2.2) quando quem chama é a `rt_rep_avaliar`.

### 5.2 Executar a virada

```sql
fn_rep_virar_continuo(p_aluno_id uuid, p_bloco_id uuid, p_observacao text default null) → uuid
fn_rep_voltar_pontual(p_aluno_id uuid, p_motivo text) → void
```

`fn_rep_virar_continuo` exige `turmas.alocar` e:

1. levanta `PT409 / REP_JA_CONTINUO` se o aluno já tem alocação ativa de tipo `REP`;
2. chama `fn_bloco_admitir(p_bloco_id, p_aluno_id, 'REP')` — que já faz o `pg_advisory_xact_lock` do
   bloco, a checagem de método e a de capacidade (`BLOCO_LOTADO`). **Nenhuma checagem de vaga é
   reescrita aqui**: se o bloco de destino estiver cheio, a virada falha com o erro que a tela já
   sabe tratar, e a pessoa escolhe outro bloco;
3. cancela as reposições `PREVISTA` do aluno em qualquer bloco, via `fn_reposicao_cancelar`, com
   observação padrão `Absorvida pela virada para REP contínuo` — liberando as vagas que elas
   ocupavam naquelas datas;
4. fecha a pendência `REP:<aluno_id>:CONTINUO` com `fn_pendencia_resolver`;
5. devolve o `id` da alocação criada.

Não exige que `fn_rep_avaliar_virada` tenha devolvido `SUGERIR_CONTINUO`: a sugestão é um alerta, não
uma autorização. A direção pode virar um aluno por decisão própria, e a pessoa que ignora a sugestão
usa `fn_pendencia_resolver_id(..., 'IGNORADA', justificativa)`.

`fn_rep_voltar_pontual` exige `turmas.alocar` e motivo (`PT422 / MOTIVO_OBRIGATORIO`), levanta
`PT409 / REP_NAO_CONTINUO` se não houver alocação `REP` ativa, e desativa a alocação chamando
`fn_bloco_remover(bloco_da_alocacao_rep, p_aluno_id, p_motivo)` — de novo sem lógica duplicada.

> Se a alocação `REP` for a **única** do aluno, a volta o deixa sem turma. Isso não é bloqueado: a
> `rt_pendencias_diaria` abre `ALUNO_SEM_TURMA` no dia seguinte, que é o comportamento correto e já
> especificado. Bloquear aqui esconderia o problema em vez de mostrá-lo.

### 5.3 Onde o critério é chamado

| Chamador | Faz |
|---|---|
| `rt_rep_avaliar()` (rotina diária, card 2.2 §11) | percorre os alunos ATIVO/ACELERAR com alguma reposição não `REALIZADA` **ou** com alocação `REP` ativa; abre e fecha as pendências |
| `fn_reposicao_registrar` | devolve o veredito à tela logo depois de marcar `REALIZADA`/`FALTOU`, para a secretaria ver na hora |

**Quem abre a pendência é a rotina, não a avaliação.** O card 2.2 registrou `REP_VIRADA` como
"aberta por `fn_rep_avaliar_virada`"; esta especificação corrige: a avaliação é `stable` e não
escreve, e quem abre **e fecha** é `rt_rep_avaliar`, no mesmo padrão de `rt_pendencias_diaria` —
reavaliada todo dia, some sozinha quando deixa de ser verdade, e a lista nunca acumula item que já
não vale. `fn_reposicao_registrar` passa a devolver `text` em vez de `void` pelo mesmo princípio de
§1.3 do card 2.2: informação que interessa à tela é status de retorno.

---

## 6. Pendências

| Tipo | `chave_dedup` | Severidade | Aberta por | Fechada por |
|---|---|---|---|---|
| `REP_VIRADA` | `REP:<aluno_id>:CONTINUO` | MEDIA | `rt_rep_avaliar` (veredito `SUGERIR_CONTINUO`) | `fn_rep_virar_continuo`, a própria rotina quando o veredito volta a `MANTER`, ou resolução humana |
| `REP_VIRADA` | `REP:<aluno_id>:VOLTA` | BAIXA | `rt_rep_avaliar` (veredito `SUGERIR_VOLTA`) | `fn_rep_voltar_pontual`, a própria rotina, ou resolução humana |

O **sufixo na chave é obrigatório**. O catálogo do card 2.2 previa `REP:<aluno_id>` para os dois
sentidos, e a deduplicação por índice único parcial (`pendencia_aberta_uk`) faria a sugestão de volta
ser silenciosamente descartada enquanto a sugestão de ida ainda estivesse aberta — os dois nunca
coexistem hoje, mas depender disso é frágil e o custo de separar é zero.

`descricao` é montada com os números de `fn_rep_situacao`, por exemplo:

> 3 aulas a repor em aberto; a mais antiga é de 12/09/2026 e vence em 12/10/2026; cabem 2 reposições
> até lá. Sugerido converter para REP contínuo.

---

## 7. Efeitos colaterais que precisam ficar registrados

1. **Alocação `REP` não conta como 2º bloco para aceleração.** "Dois blocos por semana = aceleração"
   é regra do plano, e a `rt_pendencias_diaria` fecha `ACELERAR_SEM_2O_BLOCO` contando blocos ativos.
   Um aluno ATIVO que vira REP contínuo passaria a ter dois blocos sem estar acelerando. A contagem
   de aceleração precisa filtrar `tipo <> 'REP'` (§8, ajuste 4).
2. **Conta, sim, para `ALUNO_SEM_TURMA`.** O aluno está em um bloco de verdade, ocupando vaga de
   verdade. Nenhum ajuste.
3. **Capacidade.** Antes da virada o aluno ocupa vaga só nas datas das reposições `PREVISTA`; depois,
   toda semana. A conversão é feita por `fn_bloco_admitir`, então `fn_ocupacao_bloco` e
   `fn_vagas_livres` continuam corretas sem nenhuma alteração.
4. **Mudança de status.** `tg_aluno_status_desaloca` já desativa `bloco_aluno` e cancela reposições
   futuras quando o aluno sai de ATIVO/ACELERAR — inclusive a alocação `REP`. Nenhum ajuste.

---

## 8. Ajustes que este card exige

| # | Ajuste | Onde | Card | Bloqueante |
|---|---|---|---|---|
| 1 | `bloco_aluno.tipo_desde date not null default current_date` + trigger `tg_bloco_aluno_tipo_desde` que a atualiza quando `tipo` muda | `add column` + trigger | 5.1 | **sim** |
| 2 | `bloco_aluno_reposicao.status`: valor `FALTOU` — já é o ajuste 1 do §14 do card 2.2; o critério de reincidência (§3.4) **depende** dele | `drop`/`add constraint` | 5.1 | **sim** |
| 3 | `pendencia.tipo`: valor `REP_VIRADA` — já é o ajuste 2 do §14 do card 2.2 | idem | 5.5 | **sim** |
| 4 | `rt_pendencias_diaria`: a contagem de blocos para `ACELERAR_SEM_2O_BLOCO` filtra `tipo <> 'REP'` | corpo da rotina | 5.5 | não |
| 5 | `fn_reposicao_registrar` passa a devolver `text` (o veredito) em vez de `void` | assinatura | 5.1 | não |
| 6 | Tipo composto novo `tp_rep_situacao` (o card 2.2 declarava um só, `tp_entrega_resultado`) | `create type` | 5.3 | não |
| 7 | Erros novos no catálogo: `REP_JA_CONTINUO` (409) e `REP_NAO_CONTINUO` (409) | catálogo §12 do card 2.2 | 5.3 | não |
| 8 | Quatro parâmetros novos no seed (§4) | seed | 3.6 | **sim** |

O ajuste 1 é a única coluna nova. A alternativa — deduzir a data da virada de
`coalesce(atualizado_em, criado_em)` de `bloco_aluno` — foi descartada porque qualquer edição da
linha empurraria a data para frente e alteraria o débito sem que ninguém tivesse mudado nada. É o
mesmo raciocínio que levou o card 2.1 a criar `aluno.status_desde` em vez de varrer o histórico.

---

## 9. Mapa deste card → cards de implementação

| Objeto | Card |
|---|---|
| `bloco_aluno.tipo_desde`, `tg_bloco_aluno_tipo_desde`, `FALTOU`, assinatura de `fn_reposicao_registrar` | 5.1 |
| `tp_rep_situacao`, `fn_rep_situacao`, `fn_rep_avaliar_virada`, `fn_rep_virar_continuo`, `fn_rep_voltar_pontual`, erros novos | 5.3 ✅ (03/09/2026) |
| `REP_VIRADA` no `check`, `rt_rep_avaliar`, filtro de aceleração | 5.5 |
| Parâmetros `rep_*` no seed | 3.6 |
| Botões "Converter para REP contínuo" / "Voltar a pontual" na tela de alunos do bloco | 5.7 |
| Pendências `REP_VIRADA` na central de pendências | 5.8 |

---

## 10. O que este card deixa em aberto

1. **Calibração dos quatro parâmetros.** Os valores são a leitura conservadora do plano, não medição:
   não há histórico de reposições na planilha para calibrar. Revisar depois de 3 meses de uso, junto
   com a recalibração da projeção de demanda (card 11.2).
2. **Falta sem reposição lançada.** Enquanto frequência por aula estiver fora do escopo, o critério
   só enxerga o que a secretaria lançou (§2). Se a escola vier a querer o alerta antes disso, o
   caminho é registrar a falta — não afrouxar o critério.
3. **Pendência ignorada reabre no dia seguinte.** Vale para toda pendência aberta por rotina, não só
   para esta: `IGNORADA` fecha a linha, e a rotina reabre no dia seguinte porque a condição continua
   verdadeira. Tratar de forma geral no card 5.5 (por exemplo, uma carência por `chave_dedup`), não
   com uma exceção só para `REP_VIRADA`.
