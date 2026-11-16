import { supabase } from "../supabase";
import { el } from "./dom";

interface Evento { id: string; tipo: string; valor: number; alvo?: string | null; mensagem: string | null; inicio?: string; fim: string }
type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

type Alvo = "tipo" | "clima" | "mapa" | "presente";
const NOME_ALVO: Record<string, string> = { rain: "Chuva", sun: "Sol forte", sand: "Tempestade de areia", snow: "Neve", dinheiro: "₽" };
const TIPOS_POKE = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"];
const TIPOS: Record<string, { nome: string; icone: string; valores: number[]; texto: (v: number, a?: string | null) => string; alvo?: Alvo }> = {
  xp: { nome: "XP em dobro (ou mais)", icone: "⭐", valores: [2, 3, 5], texto: (v) => `XP x${v}` },
  brilhante: { nome: "Chance de brilhante", icone: "✨", valores: [5, 10, 25, 50], texto: (v) => `Chance de Pokémon brilhante x${v}` },
  dinheiro: { nome: "Prêmios em dinheiro", icone: "₽", valores: [2, 3], texto: (v) => `Prêmios em dinheiro x${v}` },
  encontro: { nome: "Mais Pokémon selvagens", icone: "🌿", valores: [1.5, 2, 3], texto: (v) => `Mais Pokémon selvagens (x${v})` },
  pa_gratis: { nome: "Buscas grátis (sem gastar PA)", icone: "🎁", valores: [1], texto: () => "Buscas de Pokémon sem gastar PA" },
  loja_desconto: { nome: "Desconto nas lojas (%)", icone: "🏷️", valores: [20], texto: (v) => `Lojas com ${v}% de desconto` },
  pa_extra: { nome: "PA extra para todos (agora)", icone: "⚡", valores: [10], texto: (v) => `+${v} PA para todos os treinadores` },
  captura: { nome: "Captura facilitada (x chance)", icone: "🎯", valores: [1.5, 2, 3], texto: (v) => `Captura facilitada: chance x${v}` },
  pesca: { nome: "Pesca em dobro (x chance)", icone: "🎣", valores: [1.5, 2], texto: (v) => `Pesca rende mais (x${v})` },
  tipo_destaque: { nome: "Pokémon de um tipo em destaque", icone: "🔥", valores: [2, 3, 5], texto: (v, a) => `Pokémon do tipo ${a ?? "?"} aparecem mais (x${v})`, alvo: "tipo" },
  presente: { nome: "Chuva de presentes (agora)", icone: "🎁", valores: [500], texto: (v, a) => (a === "dinheiro" ? `Chuva de presentes: ₽ ${v} para todos` : `Chuva de presentes: ${v}× ${a ?? "item"} para todos`), alvo: "presente" },
  clima: { nome: "Clima (chuva, sol, areia, neve)", icone: "🌦️", valores: [1], texto: (_v, a) => `Clima: ${NOME_ALVO[a ?? ""] ?? a} (batalhas e Pokémon do tipo combinando)`, alvo: "clima" },
  duelo_dobro: { nome: "Duelos contra treinadores com bônus", icone: "⚔️", valores: [2, 3], texto: (v) => `Prêmios dos treinadores x${v}` },
  torneio: { nome: "Torneio: duelos valendo pagam ₽", icone: "🏆", valores: [200, 500], texto: (v) => `Torneio: cada vitória em duelo valendo rende +₽ ${v}` },
  mapa_destaque: { nome: "Mapa em destaque (mais encontros)", icone: "📍", valores: [2, 3], texto: (v, a) => `Mais Pokémon em ${a ?? "um mapa"} (x${v})`, alvo: "mapa" },
  xp_treino: { nome: "XP de treinador em dobro", icone: "🎓", valores: [2, 3], texto: (v) => `XP de treinador x${v}` },
};
const DURACOES: [string, number][] = [["15 min", 15], ["30 min", 30], ["1 hora", 60], ["2 horas", 120], ["6 horas", 360], ["24 horas", 1440], ["3 dias", 4320]];

const hora = (iso: string) => new Date(iso).toLocaleString("pt-BR", { hour: "2-digit", minute: "2-digit", ...(Date.now() + 18 * 3600e3 < new Date(iso).getTime() ? { day: "2-digit", month: "2-digit" } : {}) });
const resumo = (e: Evento) => e.mensagem ?? (TIPOS[e.tipo]?.texto(Number(e.valor), e.alvo ?? null) ?? e.tipo);

/** Aviso de eventos: uma Pokébola dourada com "Evento Acontecendo!"; ao clicar, mostra os eventos ativos. */
export function iniciarFaixaEventos(modal: Modal): HTMLElement {
  const faixa = el("div", { class: "faixa-evento", hidden: "", role: "status" });
  let timer = 0;
  let lista: Evento[] = [];
  const abrir = () => {
    modal.abrir("🎉 Eventos acontecendo",
      ...(lista.length ? lista.map((e) => el("div", { class: "ev-card" },
        el("span", { class: "ev-card-icone", "aria-hidden": "true" }, TIPOS[e.tipo]?.icone ?? "🎉"),
        el("div", {}, el("strong", {}, resumo(e)), el("span", { class: "sub" }, `Termina ${hora(e.fim)}`)))) : [el("p", { class: "sub" }, "Nenhum evento no momento.")]));
  };
  const atualizar = async () => {
    if (!faixa.isConnected && timer) { window.clearInterval(timer); return; }
    const { data } = await supabase.rpc("eventos_ativos");
    lista = (Array.isArray(data) ? data : []) as Evento[];
    const clima = lista.find((x) => x.tipo === "clima")?.alvo ?? "";
    document.body.dataset.clima = clima;
    if (!lista.length) { faixa.hidden = true; faixa.replaceChildren(); return; }
    if (faixa.hidden || !faixa.firstChild) {
      const b = el("button", { type: "button", class: "ev-bola-btn", "aria-label": "Evento acontecendo: ver detalhes" }, el("span", { class: "ev-bola", "aria-hidden": "true" }), el("span", { class: "ev-bola-txt" }, "Evento Acontecendo!"));
      b.addEventListener("click", abrir);
      faixa.replaceChildren(b);
    }
    faixa.hidden = false;
  };
  void atualizar();
  timer = window.setInterval(() => void atualizar(), 60_000);
  return faixa;
}

/** Painel rápido do Mestre: escolher regra, valor, duração (e mensagem opcional) e iniciar. */
export async function abrirEventos(modal: Modal, aviso: (t: string) => void): Promise<void> {
  const msg = el("p", { class: "msg" }, "");
  const lista = el("div", { class: "ev-lista" });
  const carregar = async () => {
    const [{ data }, { data: ag }] = await Promise.all([supabase.rpc("eventos_ativos"), supabase.rpc("eventos_agendados")]);
    const evs = (Array.isArray(data) ? data : []) as Evento[];
    const agendados = (Array.isArray(ag) ? ag : []) as Evento[];
    const linha = (e: Evento, futuro: boolean): HTMLElement => {
      const b = el("button", { type: "button", class: "sec" }, futuro ? "Cancelar" : "Encerrar");
      b.addEventListener("click", async () => {
        const { error } = await supabase.rpc("encerrar_evento", { p_id: e.id });
        if (error) { aviso(error.message); return; }
        await carregar();
      });
      return el("div", { class: "ev-item" }, el("span", {}, `${TIPOS[e.tipo]?.icone ?? ""} ${resumo(e)} · ${futuro && e.inicio ? `começa ${hora(e.inicio)} · ` : ""}até ${hora(e.fim)}`), b);
    };
    lista.replaceChildren(
      ...(evs.length ? evs.map((e) => linha(e, false)) : [el("p", { class: "sub" }, "Nenhum evento em andamento.")]),
      el("label", {}, "Agendados"),
      ...(agendados.length ? agendados.map((e) => linha(e, true)) : [el("p", { class: "sub" }, "Nenhum evento agendado.")]));
  };

  const tipo = el("select", {}, ...Object.entries(TIPOS).map(([k, t]) => el("option", { value: k }, `${t.icone} ${t.nome}`)));
  const valor = el("input", { type: "number", step: "any", min: "0.1", max: "1000", inputmode: "decimal" });
  const dica = el("p", { class: "sub" }, "");
  const duracao = el("select", {}, ...DURACOES.map(([r, m]) => el("option", { value: String(m) }, r)), el("option", { value: "data" }, "Até uma data e hora…"));
  duracao.value = "60";
  const quando = el("input", { type: "datetime-local", hidden: "" });
  duracao.addEventListener("change", () => { quando.hidden = duracao.value !== "data"; if (!quando.hidden && !quando.value) { const d = new Date(Date.now() + 3600e3); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); quando.value = d.toISOString().slice(0, 16); } });
  const inicio = el("select", {}, el("option", { value: "agora" }, "Agora"), el("option", { value: "data" }, "Em uma data e hora…"));
  const quandoIni = el("input", { type: "datetime-local", hidden: "" });
  inicio.addEventListener("change", () => {
    quandoIni.hidden = inicio.value !== "data";
    if (!quandoIni.hidden && !quandoIni.value) { const d = new Date(Date.now() + 3600e3); d.setMinutes(d.getMinutes() - d.getTimezoneOffset()); quandoIni.value = d.toISOString().slice(0, 16); }
    iniciar.textContent = inicio.value === "data" ? "Agendar evento" : "Iniciar evento agora";
  });
  const alvoRot = el("label", {}, "Alvo");
  const alvo = el("select", {});
  alvoRot.hidden = true; alvo.hidden = true;
  let mapasCache: { id: string; nome: string }[] | null = null;
  let itensCache: { slug: string; nome: string }[] | null = null;
  const montarAlvo = async () => {
    const k = TIPOS[tipo.value]?.alvo;
    alvoRot.hidden = alvo.hidden = !k;
    if (!k) return;
    const op = (v: string, t: string) => el("option", { value: v }, t);
    if (k === "tipo") alvo.replaceChildren(...TIPOS_POKE.map((t) => op(t, t)));
    else if (k === "clima") alvo.replaceChildren(op("rain", "Chuva (favorece Água)"), op("sun", "Sol forte (favorece Fogo)"), op("sand", "Areia (favorece Pedra)"), op("snow", "Neve (favorece Gelo)"));
    else if (k === "mapa") {
      if (!mapasCache) mapasCache = ((await supabase.from("mapas").select("id, nome").order("nome").limit(200)).data ?? []) as { id: string; nome: string }[];
      alvo.replaceChildren(...mapasCache.map((m) => op(m.id, m.nome)));
    } else {
      if (!itensCache) itensCache = ((await supabase.from("itens").select("slug, nome").order("nome").limit(500)).data ?? []) as { slug: string; nome: string }[];
      alvo.replaceChildren(op("dinheiro", "Dinheiro (₽)"), ...itensCache.map((i) => op(i.slug, `Item: ${i.nome}`)));
    }
  };
  const texto = el("input", { type: "text", maxlength: "90", placeholder: "Mensagem para os jogadores (opcional)" });
  const preencherValores = () => {
    const t = TIPOS[tipo.value];
    valor.value = String(t.valores[t.valores.length > 1 ? 0 : 0]);
    valor.disabled = tipo.value === "pa_gratis" || tipo.value === "clima";
    dica.textContent = tipo.value === "pa_gratis" ? "Sem intensidade: a busca simplesmente não gasta PA." : tipo.value === "loja_desconto" ? "Digite a porcentagem de desconto (1 a 90)." : tipo.value === "pa_extra" ? "Digite quantos PA dar a cada jogador (acontece agora)." : `Digite o multiplicador (ex.: ${t.valores.join(", ")}; aceita decimais como 1,5).`;
  };
  tipo.addEventListener("change", () => { preencherValores(); void montarAlvo(); });
  preencherValores();
  const iniciar = el("button", { type: "button" }, "Iniciar evento agora");
  iniciar.addEventListener("click", async () => {
    iniciar.disabled = true;
    const num = Number(String(valor.value).replace(",", "."));
    const porData = duracao.value === "data";
    const agendar = inicio.value === "data";
    if (agendar && !quandoIni.value) { iniciar.disabled = false; msg.textContent = "Escolha a data e a hora de início."; msg.className = "msg erro"; return; }
    if (porData && !quando.value) { iniciar.disabled = false; msg.textContent = "Escolha a data e a hora de término."; msg.className = "msg erro"; return; }
    const { error } = await supabase.rpc("criar_evento", { p_tipo: tipo.value, p_valor: num, p_minutos: porData ? null : Number(duracao.value), p_mensagem: texto.value.trim() || null, p_fim: porData ? new Date(quando.value).toISOString() : null, p_inicio: agendar ? new Date(quandoIni.value).toISOString() : null, p_alvo: TIPOS[tipo.value]?.alvo ? alvo.value : null });
    iniciar.disabled = false;
    if (error) { msg.textContent = error.message; msg.className = "msg erro"; return; }
    msg.textContent = agendar ? "Evento agendado! Ele começa sozinho na data marcada." : "Evento iniciado! A faixa aparece para os jogadores em até 1 minuto."; msg.className = "msg ok";
    texto.value = "";
    await carregar();
  });
  await carregar();
  modal.abrir("Eventos do Mestre",
    el("p", { class: "sub" }, "Vários eventos podem acontecer ao mesmo tempo. Se dois do mesmo tipo coincidirem, vale o criado por último."), el("label", {}, "Regra"), tipo, alvoRot, alvo, el("label", {}, "Intensidade"), valor, dica, el("label", {}, "Começa"), inicio, quandoIni, el("label", {}, "Duração"), duracao, quando, el("label", {}, "Mensagem"), texto, iniciar, msg,
    el("label", {}, "Em andamento"), lista);
}
