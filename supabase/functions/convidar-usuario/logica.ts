// Lógica pura da Edge Function `convidar-usuario` (card 4.7): tudo o que dá
// para decidir sem rede fica aqui, e é o que a suíte exercita com `node --test`
// (Node 24 lê `.ts` sem transpilar; o Deno da Edge Function lê o mesmo arquivo).
// `index.ts` só orquestra: lê o pedido, chama o banco e o Auth, devolve.
//
// Contrato (docs/acesso-autenticacao.md §3.2): a função verifica
// tem_permissao('admin.gerir_usuarios') com o token de quem chama, convida com
// a service key que só existe dentro dela, e devolve o erro do banco COMO VEIO
// — o `codigo` do DETAIL é o que a tela traduz (card 2.7 §7.1).

export type Pedido = {
  email: string;
  nome: string;
  redirecionarPara?: string;
};

export type Corpo = {
  codigo?: string;
  code?: string;
  mensagem: string;
  [chave: string]: unknown;
};

export type Resultado =
  | { ok: true; pedido: Pedido }
  | { ok: false; status: number; corpo: Corpo };

/** CORS: o app roda em outro domínio (Pages) e o navegador pergunta antes. */
export const cabecalhosCors: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const formatoEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor.trim() : "";
}

/**
 * Validação local, só de formato (design-system §5.4): e-mail com cara de
 * e-mail, nome preenchido, destino do link (quando vier) em http(s). Regra de
 * negócio — unidade, duplicidade, permissão — é do banco e do Auth.
 */
export function lerPedido(corpo: unknown): Resultado {
  if (corpo === null || typeof corpo !== "object") {
    return recusa(400, "CORPO_INVALIDO", "O pedido precisa ser um JSON com email e nome.");
  }
  const dados = corpo as Record<string, unknown>;
  const email = texto(dados.email).toLowerCase();
  const nome = texto(dados.nome);
  const destino = texto(dados.redirecionar_para);

  if (!formatoEmail.test(email)) {
    return recusa(400, "EMAIL_INVALIDO", "Informe um e-mail válido.");
  }
  if (nome === "") {
    return recusa(400, "NOME_OBRIGATORIO", "Informe o nome da pessoa.");
  }
  if (destino !== "" && !/^https?:\/\//.test(destino)) {
    return recusa(400, "DESTINO_INVALIDO", "O destino do link precisa ser uma URL http(s).");
  }

  return {
    ok: true,
    pedido: { email, nome, redirecionarPara: destino === "" ? undefined : destino },
  };
}

function recusa(status: number, codigo: string, mensagem: string): Resultado {
  return { ok: false, status, corpo: { codigo, mensagem } };
}

/**
 * Procura o `codigo` do DETAIL (card 2.2 §1.2) dentro do que o GoTrue devolveu.
 * A Admin API repassa o corpo do `raise` tal e qual (medido no card 3.5), mas
 * o lugar exato dentro do JSON de erro varia com a versão — por isso a busca é
 * textual, no erro inteiro serializado, e não num campo.
 */
export function extrairCodigo(erro: unknown): string | undefined {
  const partes: string[] = [];
  if (typeof erro === "string") partes.push(erro);
  if (erro && typeof erro === "object") {
    const e = erro as Record<string, unknown>;
    if (typeof e.message === "string") partes.push(e.message);
    try {
      partes.push(JSON.stringify(erro));
    } catch {
      // erro com referência circular: fica só com a mensagem
    }
  }
  for (const parte of partes) {
    const casa = /"codigo"\s*:\s*"([A-Z][A-Z0-9_]*)"/.exec(parte);
    if (casa) return casa[1];
  }
  return undefined;
}

/** O erro do Auth vira resposta: status, `codigo` (se o banco recusou) e o
 *  `code` do GoTrue (rate limit, e-mail já cadastrado…), para a tela traduzir
 *  o que souber e mostrar o resto como veio. */
export function respostaDeErroAuth(
  erro: { status?: number; code?: string | null; message?: string },
): { status: number; corpo: Corpo } {
  const codigo = extrairCodigo(erro);
  const status = typeof erro.status === "number" && erro.status >= 400 && erro.status <= 599
    ? erro.status
    : 500;
  const corpo: Corpo = {
    mensagem: erro.message ?? "O Auth recusou o convite.",
  };
  if (codigo) corpo.codigo = codigo;
  if (erro.code) corpo.code = erro.code;
  return { status, corpo };
}

export function resposta(status: number, corpo: Corpo | Record<string, unknown>): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...cabecalhosCors, "Content-Type": "application/json; charset=utf-8" },
  });
}
