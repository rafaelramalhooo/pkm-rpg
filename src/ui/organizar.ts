import { supabase } from "../supabase";
import { el } from "./dom";
import { imagemPokemon, nomePokemon, carregarReferencias, type PokemonRow } from "./dados";
import { abrirCaixas } from "./caixa";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

/** Organizar o time (ordem, time/caixa) e escolher o Pokémon que segue o treinador. */
export async function abrirOrganizar(modal: Modal, uid: string, aviso: (t: string) => void, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  const { data, error } = await supabase.from("pokemons").select("*").eq("dono", uid).order("posicao", { nullsFirst: false }).order("criado_em");
  if (error) { aviso(error.message); return; }
  const todos = (data ?? []) as PokemonRow[];
  const { data: seg } = await supabase.rpc("meu_seguidor");
  let seguidor: string | null = (seg as { id: string } | null)?.id ?? null;
  const time = todos.filter((p) => p.posicao !== null).sort((a, b) => (a.posicao ?? 0) - (b.posicao ?? 0));
  const caixa = todos.filter((p) => p.posicao === null);
  let sujo = false;
  const msg = el("p", { class: "msg" }, "");
  const corpo = el("div", { class: "org-corpo" });

  const linha = (p: PokemonRow, noTime: boolean, i: number) => {
    const b = (t: string, fn: () => void, dis = false, titulo = "") => { const x = el("button", { type: "button", class: "sec", title: titulo }, t); if (dis) x.setAttribute("disabled", ""); x.addEventListener("click", fn); return x; };
    const mover = (d: number) => { const j = i + d; [time[i], time[j]] = [time[j], time[i]]; sujo = true; desenhar(); };
    const botoes = noTime
      ? [b("↑", () => mover(-1), i === 0, "Subir"), b("↓", () => mover(1), i === time.length - 1, "Descer"),
        ]
      : [];
    const sg = b(seguidor === p.id ? "★ Seguindo" : "Seguir", async () => {
      const novo = seguidor === p.id ? null : p.id;
      const { error: e } = await supabase.rpc("definir_seguidor", { p_pokemon: novo });
      if (e) { aviso(e.message); return; }
      seguidor = novo; aoMudar(); desenhar();
    }, false, "Anda ao seu lado fora da Pokébola");
    if (seguidor === p.id) sg.classList.add("ativo");
    return el("div", { class: `org-linha${p.hp_atual <= 0 ? " caido" : ""}` }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
      el("div", { class: "org-info" }, el("strong", {}, nomePokemon(p)), el("span", {}, `Nv ${p.nivel} · ${p.hp_atual}/${p.hp_max} HP`)),
      el("div", { class: "org-btns" }, sg, ...botoes));
  };

  const verCaixas = el("button", { type: "button", class: "sec" }, "Ver Caixas (guardar e trocar só no Centro Pokémon ou no Laboratório)");
  verCaixas.addEventListener("click", () => void abrirCaixas(modal, uid, aviso as (t: string, ms?: number, erro?: boolean) => void, aoMudar));

  function desenhar(): void {
    corpo.replaceChildren(
      el("label", {}, `Time (${time.length}/6) — o primeiro entra na batalha`),
      ...time.map((p, i) => linha(p, true, i)),
      el("label", {}, `Caixas: ${caixa.length} Pokémon guardado(s)`),
      verCaixas,
    );
  }
  const salvar = el("button", { type: "button" }, "Salvar ordem do time");
  salvar.addEventListener("click", async () => {
    const { error: e } = await supabase.rpc("organizar_time", { p_ordem: time.map((p) => p.id) });
    if (e) { msg.textContent = e.message; msg.className = "msg erro"; return; }
    sujo = false; msg.textContent = "Time salvo!"; msg.className = "msg ok"; aoMudar();
  });
  desenhar();
  void sujo;
  modal.abrir("Organizar time", corpo, salvar, msg);
}
