// Reserva Dourada (Zona do Safári): entrada paga, passos e Bolas Safári limitados, captura sem batalha.
// Tudo é decidido no servidor (reserva_entrar / reserva_encontro / reserva_acao / reserva_estado).
import { el } from "./dom";
import { supabase } from "../supabase";
import { imagemPokemon } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; aberto: () => boolean };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;
interface Cap { especie_id: number; nivel: number; nome: string }
interface Estado {
  ativa: boolean; visitou_hoje: boolean; preco: number; passos_max: number; bolas_max: number;
  passos?: number; bolas?: number; capturas?: Cap[]; fim?: Cap[] | null;
  enc?: { especie_id: number; nivel: number; nome: string; iscas: number; pedras: number } | null;
}
interface Resposta { msg?: string; capturou?: boolean; fugiu?: boolean; estado: Estado; fim?: unknown; chance_captura?: number; chance_fuga?: number }

export interface Reserva {
  faixa: HTMLElement;
  aoMapa: (mapaId: string) => void;
  abrir: () => Promise<void>;
  observar: () => Promise<void>;
}

export function criarReserva(modal: Modal, aviso: Aviso, aoMudar: () => void): Reserva {
  const faixa = el("button", { type: "button", class: "reserva-faixa", hidden: "" });
  let timer: number | undefined;
  let est: Estado | null = null;

  const rpc = async <T>(nome: string, args?: Record<string, unknown>): Promise<T | null> => {
    const { data, error } = await supabase.rpc(nome, args);
    if (error) { aviso(error.message, 5000, true); return null; }
    return data as T;
  };

  const listaCap = (l: Cap[]): HTMLElement => el("div", { class: "rec-lista" }, ...l.map((c) => el("span", {}, `${c.nome} Nv ${c.nivel}`)));

  const mostrarFim = (l: Cap[]): void => {
    aoMudar();
    const corpo: Node[] = [el("p", { class: "sub" }, l.length ? "Sua visita à Reserva terminou. Estes Pokémon foram entregues ao seu time (ou à caixa):" : "Sua visita à Reserva terminou. Desta vez nenhum Pokémon foi capturado.")];
    if (l.length) corpo.push(listaCap(l));
    const ok = el("button", { type: "button" }, "Continuar"); ok.addEventListener("click", () => modal.fechar());
    corpo.push(ok);
    if (modal.aberto()) aviso(l.length ? `Visita encerrada: ${l.length} Pokémon capturado(s) entregue(s)!` : "Visita à Reserva encerrada.", 6000);
    else modal.abrir("🦓 Reserva Dourada", ...corpo);
  };

  const pintar = (): void => {
    const s = est;
    if (!s) { faixa.hidden = true; return; }
    faixa.hidden = !s.ativa; // a faixa só aparece durante uma visita ativa
    faixa.classList.toggle("ativa", s.ativa);
    if (s.ativa) faixa.textContent = `🦓 Safári · ${s.passos} passos · ${s.bolas} bolas · ${s.capturas?.length ?? 0} capturado(s)`;
    else if (s.visitou_hoje) faixa.textContent = "🦓 Reserva Dourada · visita de hoje já feita";
    else faixa.textContent = `🦓 Reserva Dourada · Entrar (₽ ${s.preco})`;
  };

  const atualizar = async (): Promise<void> => {
    const s = await rpc<Estado>("reserva_estado");
    if (!s) return;
    est = s; pintar();
    if (s.fim) mostrarFim(s.fim);
    else if (s.ativa && s.enc && !modal.aberto()) desenharEncontro(null, s); // o servidor sorteia por passo: o encontro abre sozinho
  };

  const abrirEntrada = (): void => {
    const s = est;
    if (!s) return;
    if (s.ativa) {
      modal.abrir("🦓 Reserva Dourada — visita em andamento",
        el("p", { class: "sub" }, `Passos restantes: ${s.passos}/${s.passos_max} · Bolas Safári: ${s.bolas}/${s.bolas_max}.`),
        el("p", { class: "sub" }, "Ande pelo campo e pela estrada: a cada passo pode aparecer um Pokémon, e o encontro abre sozinho. Andar aqui não gasta PA."),
        ...(s.capturas?.length ? [el("p", { class: "sub" }, "Capturados até agora (chegam ao fim da visita):"), listaCap(s.capturas)] : []));
      return;
    }
    const msg = el("p", { class: "msg" });
    const entrar = el("button", { type: "button" }, `Pagar ₽ ${s.preco} e entrar`);
    if (s.visitou_hoje) entrar.setAttribute("disabled", "");
    entrar.addEventListener("click", async () => {
      entrar.setAttribute("disabled", "");
      const r = await rpc<Estado>("reserva_entrar");
      if (!r) { entrar.removeAttribute("disabled"); return; }
      est = r; pintar(); aoMudar(); modal.fechar();
      aviso(`Bem-vindo à Reserva! ${r.passos} passos e ${r.bolas} Bolas Safári. Boa caça!`, 5000);
    });
    modal.abrir("🦓 Reserva Dourada",
      el("p", { class: "sub" }, "Uma savana protegida onde os Pokémon vivem soltos: Tauros, Kangaskhan, Rhyhorn, Chansey, Scyther, Pinsir, Exeggcute, Doduo e outros."),
      el("p", { class: "sub" }, `Entrada: ₽ ${s.preco}. Você recebe ${s.bolas_max} Bolas Safári e ${s.passos_max} passos. Cada passo gasta 1 passo da visita (não gasta PA). Só uma visita por dia.`),
      el("p", { class: "sub" }, "Não há batalha: em cada encontro você escolhe entre Bola Safári, Isca (acalma, mas reduz a captura), Pedra (irrita: mais chance de captura, mas foge mais) ou Fugir. Os Pokémon capturados chegam ao seu time só no fim da visita, e suas Bolas Safári não saem da Reserva."),
      s.visitou_hoje ? el("p", { class: "msg" }, "Você já visitou a Reserva hoje. Volte amanhã (o dia vira às 6h).") : msg,
      entrar);
  };
  faixa.addEventListener("click", abrirEntrada);

  const desenharEncontro = (r: Resposta | null, s: Estado): void => {
    const enc = s.enc;
    const fecharBtn = (rot: string): HTMLElement => { const b = el("button", { type: "button" }, rot); b.addEventListener("click", () => { modal.fechar(); void atualizar(); }); return b; };
    if (!enc) {
      modal.abrir("🦓 Safári", ...(r?.msg ? [el("p", { class: "fala-npc" }, r.msg)] : []), el("p", { class: "sub" }, s.ativa ? `Restam ${s.passos} passos e ${s.bolas} bolas.` : "A visita terminou."), fecharBtn("Continuar"));
      if (s.fim) { est = s; pintar(); modal.fechar(); mostrarFim(s.fim); }
      return;
    }
    const humor = enc.pedras - enc.iscas;
    const aviso2 = humor > 0 ? "Está irritado (fica mais fácil capturar, mas ele foge mais)." : humor < 0 ? "Está calmo (foge menos, mas fica mais difícil capturar)." : "Está atento.";
    const log = el("p", { class: "fala-npc" }, r?.msg ?? `Um ${enc.nome} selvagem apareceu!`);
    const agir = async (acao: string): Promise<void> => {
      bts.forEach((b) => b.setAttribute("disabled", ""));
      const res = await rpc<Resposta>("reserva_acao", { p_acao: acao });
      if (!res) { bts.forEach((b) => b.removeAttribute("disabled")); return; }
      est = res.estado; pintar();
      if (res.capturou) aoMudar();
      desenharEncontro(res, res.estado);
    };
    const mk = (rot: string, acao: string, cls = ""): HTMLButtonElement => {
      const b = el("button", { type: "button", class: cls }, rot); b.addEventListener("click", () => void agir(acao)); return b;
    };
    const bola = mk(`🎯 Bola Safári (${s.bolas})`, "bola");
    if (!s.bolas) bola.setAttribute("disabled", "");
    const bts = [bola, mk("🍖 Isca", "isca", "sec"), mk("🪨 Pedra", "pedra", "sec"), mk("🏃 Fugir", "fugir", "sec")];
    const img = imagemPokemon("frente", enc.especie_id, "grande");
    modal.abrir(`🦓 ${enc.nome} · Nv ${enc.nivel}`, el("div", { class: "reserva-cena" }, img), log, el("p", { class: "sub" }, aviso2),
      el("p", { class: "sub" }, `Bolas: ${s.bolas} · Passos: ${s.passos}`), el("div", { class: "reserva-bts" }, ...bts));
  };

  const observar = async (): Promise<void> => {
    const s = await rpc<Estado>("reserva_encontro");
    if (!s) return;
    est = s; pintar();
    desenharEncontro(null, s);
  };

  let mapaAnterior = "";
  const abrirPortal = async (): Promise<void> => {
    await atualizar();
    abrirEntrada();
  };
  const aoMapa = (mapaId: string): void => {
    window.clearInterval(timer);
    const entrou = mapaId === "reserva" && mapaAnterior !== "reserva";
    mapaAnterior = mapaId;
    if (mapaId !== "reserva") { faixa.hidden = true; est = null; return; }
    void atualizar().then(() => {
      // Ao entrar no mapa: explica o que é a Reserva e oferece a visita (o servidor valida tudo)
      if (entrou && est && !est.ativa && !est.fim && !modal.aberto()) abrirEntrada();
    });
    let tick = 0;
    timer = window.setInterval(() => { tick += 1; if (!document.hidden && (est?.ativa || tick % 4 === 0)) void atualizar(); }, 1500);
  };

  return { faixa, aoMapa, abrir: abrirPortal, observar };
}
