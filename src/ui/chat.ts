// Chat global e privado (só entre amigos), lista de amigos e cartão de jogador. Tudo validado no servidor (m70).
import { supabase } from "../supabase";
import { el } from "./dom";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; aoFechar: (fn: (() => void) | null) => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;
const BASE = import.meta.env.BASE_URL;

interface Msg { id: number; canal: "global" | "privado"; de: string; de_nome: string; para: string | null; texto: string; criado: string }
interface AmigoLinha { id: string; nome: string; aparencia: number; online: boolean; visto_em: string | null; mapa: string | null; ranking: { pos: number; pontos: number } | null }
interface ListaAmigos { amigos: AmigoLinha[]; recebidos: { id: string; de: string; nome: string }[]; enviados: { id: string; para: string; nome: string }[] }
interface PerfilPub {
  id: string; nome: string; aparencia: number; mestre: boolean; online: boolean; visto_em: string | null; mapa: string | null; ranking: { pos: number; pontos: number } | null;
  nivel: number; titulo: string | null; vistos: number; capturados: number; insignias: number; campeao: boolean; relacao: "eu" | "amigo" | "enviado" | "recebido" | "nenhuma"; amizade: string | null;
}

export interface ChatUi {
  botao: HTMLElement;
  abrir(): void;
  enviarGlobal(texto: string): Promise<void>;
  abrirCartao(id: string): void;
  abrirAmigos(): void;
  encerrar(): void;
}

const atras = (iso: string | null): string => {
  if (!iso) return "nunca entrou";
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 180) return "agora";
  if (s < 3600) return `há ${Math.round(s / 60)} min`;
  if (s < 86400) return `há ${Math.round(s / 3600)} h`;
  return `há ${Math.round(s / 86400)} d`;
};
const hora = (iso: string): string => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
const avatar = (ap: number, classe = "tc-emblema cj-avatar"): HTMLElement => {
  const a = el("span", { class: classe, "aria-hidden": "true" });
  a.style.backgroundImage = `url(${BASE}assets/personagens/p${ap ?? 0}.png)`;
  return a;
};

export function iniciarChat(modal: Modal, uid: string, meuNome: string, aviso: Aviso, tela: HTMLElement, ehMestre: boolean): ChatUi {
  let global: Msg[] = [];
  const priv = new Map<string, Msg[]>();
  const nomes = new Map<string, string>();
  const naoLidas = new Map<string, number>();
  let abas: string[] = ["global"];          // "global", "amigos" ou id do amigo (conversa privada)
  let atual = "global";
  let painelAberto = false;
  let desenhar: (() => void) | null = null;
  let pedidosAntes = -1;
  let encerrada = false;

  const mini = el("div", { class: "chat-mini", "aria-live": "polite" });
  tela.append(mini);
  const badge = el("span", { class: "ch-badge", hidden: "" }, "0");
  const botao = el("button", { type: "button", class: "sec botao-menu botao-chat", "aria-label": "Chat e amigos" }, "💬", badge);
  const total = (): number => [...naoLidas.values()].reduce((a, b) => a + b, 0);
  const marcar = (): void => { const n = total(); badge.textContent = String(n); badge.hidden = n === 0; };

  const linhaMini = (m: Msg): void => {
    const l = el("div", { class: `chm${m.canal === "privado" ? " priv" : ""}` }, el("b", {}, m.canal === "privado" ? `✉ ${m.de_nome}` : m.de_nome), ` ${m.texto}`);
    mini.append(l);
    while (mini.children.length > 5) mini.firstElementChild?.remove();
    window.setTimeout(() => l.classList.add("some"), 14000);
    window.setTimeout(() => l.remove(), 15500);
  };
  mini.addEventListener("click", () => abrir());

  const guardar = (m: Msg, aoVivo: boolean): void => {
    nomes.set(m.de, m.de_nome);
    if (m.canal === "global") {
      if (global.some((x) => x.id === m.id)) return;
      global.push(m); if (global.length > 150) global.shift();
      if (aoVivo) { linhaMini(m); if (!(painelAberto && atual === "global")) { naoLidas.set("global", (naoLidas.get("global") ?? 0) + (m.de === uid ? 0 : 1)); } }
    } else {
      const outro = m.de === uid ? (m.para as string) : m.de;
      const lista = priv.get(outro) ?? [];
      if (lista.some((x) => x.id === m.id)) return;
      lista.push(m); if (lista.length > 150) lista.shift();
      priv.set(outro, lista);
      if (!abas.includes(outro)) abas.push(outro);
      if (aoVivo && m.de !== uid) {
        linhaMini(m);
        if (!(painelAberto && atual === outro)) { naoLidas.set(outro, (naoLidas.get(outro) ?? 0) + 1); aviso(`✉ ${m.de_nome}: ${m.texto}`, 4500); }
      }
    }
    marcar();
    if (painelAberto) desenhar?.();
  };

  // tempo real: o RLS garante que só chegam o global e as minhas conversas privadas
  const canal = supabase.channel(`chat:${uid}`)
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "mensagens_chat" }, (p) => guardar(p.new as Msg, true))
    .on("postgres_changes", { event: "DELETE", schema: "public", table: "mensagens_chat" }, (p) => {
      const id = (p.old as { id?: number }).id;
      if (id == null) return;
      global = global.filter((m) => m.id !== id);
      for (const [k, v] of priv) priv.set(k, v.filter((m) => m.id !== id));
      if (painelAberto) desenhar?.();
    })
    .subscribe();

  void supabase.rpc("chat_historico", { p_canal: "global", p_com: null, p_limite: 50 }).then(({ data }) => {
    global = ((data ?? []) as Msg[]);
    global.forEach((m) => nomes.set(m.de, m.de_nome));
    if (painelAberto) desenhar?.();
  });

  const ping = (): void => { void supabase.rpc("ping_online"); };
  const sondarAmigos = async (): Promise<void> => {
    const { data } = await supabase.rpc("amigo_lista");
    const l = data as ListaAmigos | null;
    if (!l) return;
    if (pedidosAntes >= 0 && l.recebidos.length > pedidosAntes) aviso(`👥 ${l.recebidos[l.recebidos.length - 1].nome} quer ser seu amigo! Abra Amigos.`, 5000);
    pedidosAntes = l.recebidos.length;
    naoLidas.set("amigos", l.recebidos.length);
    marcar();
  };
  ping(); void sondarAmigos();
  const tempo = window.setInterval(() => { ping(); void sondarAmigos(); }, 60000);

  const enviar = async (canalMsg: "global" | "privado", para: string | null, texto: string): Promise<boolean> => {
    const { data, error } = await supabase.rpc("chat_enviar", { p_canal: canalMsg, p_para: para, p_texto: texto });
    if (error) { aviso(error.message, 4000, true); return false; }
    const id = (data as { id: number }).id;
    guardar({ id, canal: canalMsg, de: uid, de_nome: meuNome, para, texto: texto.trim().slice(0, 200), criado: new Date().toISOString() }, false);
    return true;
  };

  async function abrirPrivado(amigo: string, nome: string): Promise<void> {
    nomes.set(amigo, nome);
    if (!abas.includes(amigo)) abas.push(amigo);
    const { data } = await supabase.rpc("chat_historico", { p_canal: "privado", p_com: amigo, p_limite: 50 });
    priv.set(amigo, ((data ?? []) as Msg[]));
    atual = amigo;
    naoLidas.delete(amigo); marcar();
    abrir();
  }

  function cartao(id: string): void {
    void (async () => {
      const { data } = await supabase.rpc("jogador_perfil_publico", { p_jogador: id });
      const p = data as PerfilPub | null;
      if (!p) return void aviso("Jogador não encontrado.", 3000, true);
      nomes.set(p.id, p.nome);
      const linhas: [string, string][] = [
        ["🏆 Ranking", p.mestre ? "Mestre do jogo" : p.ranking ? `#${p.ranking.pos} · ${p.ranking.pontos} pontos` : "Ainda sem pontos"],
        ["⭐ Nível de treinador", String(p.nivel)],
        ["📍 Local", p.mapa ?? "—"],
        ["📖 Pokédex", `${p.vistos} vistos · ${p.capturados} capturados`],
        ["🎖 Insígnias", `${p.insignias}${p.campeao ? " · 👑 Campeão da Liga" : ""}`],
      ];
      const status = el("span", { class: `cj-status ${p.online ? "on" : "off"}` }, p.online ? "● Online agora" : `○ Visto ${atras(p.visto_em)}`);
      const nos: Node[] = [el("div", { class: "cj-topo" }, avatar(p.aparencia), el("div", {}, el("strong", { class: "cj-nome" }, p.nome), p.titulo ? el("small", { class: "cj-titulo" }, p.titulo.replace(/_/g, " ")) : "", status)),
        el("div", { class: "cj-linhas" }, ...linhas.map(([k, v]) => el("div", { class: "cj-linha" }, el("span", {}, k), el("b", {}, v))))];
      const acoes = el("div", { class: "cj-acoes" });
      const b = (rot: string, fn: () => void, sec = false): HTMLButtonElement => { const x = el("button", { type: "button", class: sec ? "sec" : "" }, rot); x.addEventListener("click", fn); return x; };
      if (p.relacao === "nenhuma" || p.relacao === "recebido") {
        acoes.append(b(p.relacao === "recebido" ? "✅ Aceitar pedido de amizade" : "➕ Adicionar amigo", async () => {
          const { data: r, error } = await supabase.rpc("amigo_pedir", { p_jogador: p.id });
          if (error) return void aviso(error.message, 4000, true);
          aviso((r as { estado: string }).estado === "aceita" ? `Você e ${p.nome} agora são amigos!` : `Pedido enviado para ${p.nome}.`, 3500);
          cartao(id);
        }));
      } else if (p.relacao === "enviado") {
        const x = b("⏳ Pedido enviado", () => undefined, true); x.disabled = true; acoes.append(x);
      } else if (p.relacao === "amigo") {
        acoes.append(b("💬 Enviar mensagem", () => void abrirPrivado(p.id, p.nome)));
        let conf = false;
        const rem = b("Remover amigo", async () => {
          if (!conf) { conf = true; rem.textContent = "Confirmar remoção"; return; }
          await supabase.rpc("amigo_remover", { p_jogador: p.id });
          aviso(`${p.nome} foi removido dos amigos.`, 3000); cartao(id);
        }, true);
        acoes.append(rem);
      }
      if (ehMestre && p.relacao !== "eu") {
        acoes.append(b("🔇 Silenciar 10 min (Mestre)", async () => { await supabase.rpc("mestre_chat_silenciar", { p_jogador: p.id, p_minutos: 10 }); aviso(`${p.nome} silenciado por 10 min.`, 3000); }, true));
      }
      nos.push(acoes);
      modal.abrir(`Jogador — ${p.nome}`, ...nos);
    })();
  }

  function amigos(): void {
    void (async () => {
      const [{ data }, { data: on }] = await Promise.all([supabase.rpc("amigo_lista"), supabase.rpc("jogadores_online")]);
      const l = (data as ListaAmigos | null) ?? { amigos: [], recebidos: [], enviados: [] };
      pedidosAntes = l.recebidos.length; naoLidas.delete("amigos"); marcar();
      const online = (on ?? []) as { id: string; nome: string; aparencia: number }[];
      const nos: Node[] = [el("p", { class: "sub" }, "Toque em um jogador para ver o cartão. Para adicionar alguém, toque no personagem dele no mapa ou escolha na lista de online.")];
      if (l.recebidos.length) {
        nos.push(el("h3", { class: "amg-tit" }, `Pedidos recebidos (${l.recebidos.length})`));
        for (const r of l.recebidos) {
          const ok = el("button", { type: "button" }, "Aceitar"); const no = el("button", { type: "button", class: "sec" }, "Recusar");
          ok.addEventListener("click", async () => { await supabase.rpc("amigo_responder", { p_id: r.id, p_aceitar: true }); amigos(); });
          no.addEventListener("click", async () => { await supabase.rpc("amigo_responder", { p_id: r.id, p_aceitar: false }); amigos(); });
          nos.push(el("div", { class: "amg-linha" }, el("strong", {}, r.nome), el("div", { class: "amg-btns" }, ok, no)));
        }
      }
      nos.push(el("h3", { class: "amg-tit" }, `Meus amigos (${l.amigos.length})`));
      if (!l.amigos.length) nos.push(el("p", { class: "sub" }, "Você ainda não tem amigos. Toque em um jogador no mapa para adicionar."));
      for (const a of l.amigos) {
        const ver = el("button", { type: "button", class: "sec" }, "Cartão"); const msg = el("button", { type: "button" }, "💬");
        ver.addEventListener("click", () => cartao(a.id)); msg.addEventListener("click", () => void abrirPrivado(a.id, a.nome));
        nos.push(el("div", { class: "amg-linha" }, avatar(a.aparencia, "tc-emblema amg-av"),
          el("div", { class: "amg-info" }, el("strong", {}, `${a.online ? "🟢" : "⚪"} ${a.nome}`), el("small", {}, `${a.online ? "Online" : `Visto ${atras(a.visto_em)}`} · ${a.ranking ? `#${a.ranking.pos} no ranking` : "sem ranking"}${a.mapa ? ` · ${a.mapa}` : ""}`)),
          el("div", { class: "amg-btns" }, ver, msg)));
      }
      if (l.enviados.length) nos.push(el("p", { class: "sub" }, `Pedidos enviados: ${l.enviados.map((e) => e.nome).join(", ")}.`));
      nos.push(el("h3", { class: "amg-tit" }, `Jogadores online (${online.length})`));
      if (!online.length) nos.push(el("p", { class: "sub" }, "Ninguém mais online agora."));
      for (const o of online) {
        const ver = el("button", { type: "button", class: "sec" }, "Ver cartão");
        ver.addEventListener("click", () => cartao(o.id));
        nos.push(el("div", { class: "amg-linha" }, avatar(o.aparencia, "tc-emblema amg-av"), el("div", { class: "amg-info" }, el("strong", {}, `🟢 ${o.nome}`)), el("div", { class: "amg-btns" }, ver)));
      }
      modal.abrir("Amigos", ...nos);
    })();
  }

  function abrir(): void {
    painelAberto = true;
    const tabs = el("div", { class: "ch-tabs" });
    const log = el("div", { class: "ch-log" });
    const entrada = el("input", { type: "text", maxlength: "200", placeholder: "Escreva uma mensagem…", autocomplete: "off", "aria-label": "Mensagem" }) as HTMLInputElement;
    const form = el("form", { class: "ch-form" }, entrada, el("button", { type: "submit" }, "Enviar"));
    const rotulo = (a: string): string => a === "global" ? "🌐 Global" : `✉ ${nomes.get(a) ?? "Amigo"}`;
    const pintar = (): void => {
      tabs.replaceChildren();
      for (const a of abas) {
        const n = naoLidas.get(a) ?? 0;
        const t = el("button", { type: "button", class: `ch-tab${a === atual ? " ativa" : ""}` }, rotulo(a), n && a !== atual ? el("span", { class: "ch-badge" }, String(n)) : "");
        t.addEventListener("click", () => { atual = a; naoLidas.delete(a); marcar(); pintar(); });
        tabs.append(t);
      }
      const am = el("button", { type: "button", class: "ch-tab amg" }, "👥 Amigos", (naoLidas.get("amigos") ?? 0) ? el("span", { class: "ch-badge" }, String(naoLidas.get("amigos"))) : "");
      am.addEventListener("click", () => amigos());
      tabs.append(am);
      const lista = atual === "global" ? global : (priv.get(atual) ?? []);
      log.replaceChildren(...(lista.length ? lista.map((m) => {
        const l = el("div", { class: `ch-msg${m.de === uid ? " eu" : ""}` }, el("small", {}, hora(m.criado)), " ", el("b", {}, m.de_nome), ": ", m.texto);
        const nome = l.querySelector("b");
        if (nome && m.de !== uid) { nome.classList.add("clic"); nome.addEventListener("click", () => cartao(m.de)); }
        if (ehMestre && m.canal === "global") {
          const x = el("button", { type: "button", class: "ch-del", title: "Apagar (Mestre)" }, "🗑");
          x.addEventListener("click", async () => { await supabase.rpc("mestre_chat_apagar", { p_id: m.id }); global = global.filter((g) => g.id !== m.id); pintar(); });
          l.append(x);
        }
        return l;
      }) : [el("p", { class: "sub" }, atual === "global" ? "Nenhuma mensagem ainda. Diga olá!" : "Comece a conversa.")]));
      log.scrollTop = log.scrollHeight;
      entrada.placeholder = atual === "global" ? "Mensagem para todos…" : `Mensagem privada para ${nomes.get(atual) ?? "amigo"}…`;
    };
    desenhar = pintar;
    form.addEventListener("submit", async (ev) => {
      ev.preventDefault();
      const t = entrada.value.trim();
      if (!t) return;
      entrada.value = "";
      if (!(await enviar(atual === "global" ? "global" : "privado", atual === "global" ? null : atual, t))) entrada.value = t;
      entrada.focus();
    });
    naoLidas.delete(atual); marcar();
    modal.abrir("Chat", el("div", { class: "ch-painel" }, tabs, log, form));
    modal.aoFechar(() => { painelAberto = false; desenhar = null; });
    pintar();
    window.setTimeout(() => entrada.focus(), 50);
  }
  botao.addEventListener("click", () => abrir());

  return {
    botao, abrir, abrirCartao: cartao, abrirAmigos: amigos,
    enviarGlobal: async (texto: string) => { await enviar("global", null, texto); },
    encerrar: () => { if (encerrada) return; encerrada = true; window.clearInterval(tempo); void supabase.removeChannel(canal); mini.remove(); },
  };
}
