import { supabase } from "../supabase";
import { el } from "./dom";
import { imagemPokemon, nomePokemon, carregarReferencias, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };

/** Caixas (Box): ver de qualquer lugar; guardar, retirar e trocar só no Centro Pokémon ou no Laboratório (o servidor confere). */
export async function abrirCaixas(modal: Modal, uid: string, aviso: (t: string, ms?: number, erro?: boolean) => void, aoMudar: () => void, caixaInicial = 1): Promise<void> {
  await carregarReferencias();
  const [{ data: pks, error }, { data: cfg }, { data: pode }] = await Promise.all([
    supabase.from("pokemons").select("*").eq("dono", uid),
    supabase.rpc("config_caixas"),
    supabase.rpc("posso_mexer_caixa"),
  ]);
  if (error) { aviso(error.message, 4000, true); return; }
  const todos = (pks ?? []) as PokemonRow[];
  const qtd = (cfg as { qtd: number; tam: number } | null)?.qtd ?? 2;
  const tam = (cfg as { qtd: number; tam: number } | null)?.tam ?? 15;
  const podeMexer = pode === true;
  const time = todos.filter((p) => p.posicao !== null).sort((a, b) => (a.posicao ?? 0) - (b.posicao ?? 0));
  let atual = Math.min(Math.max(1, caixaInicial), qtd);
  let sel: PokemonRow | null = null;
  const msg = el("p", { class: "msg" }, "");
  const corpo = el("div", { class: "cx-corpo" });

  const rodar = async (rpc: string, args: Record<string, unknown>, ok: string) => {
    const { error: e } = await supabase.rpc(rpc, args);
    if (e) { aviso(e.message, 4500, true); msg.textContent = e.message; msg.className = "msg erro"; return; }
    aoMudar();
    void abrirCaixas(modal, uid, aviso, aoMudar, atual).then(() => aviso(ok, 2000));
  };

  const mini = (p: PokemonRow) => el("div", { class: "cx-mini" }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante), el("span", {}, `Nv ${p.nivel}`));

  function desenhar(): void {
    const abas = el("div", { class: "cx-abas" }, ...Array.from({ length: qtd }, (_, i) => {
      const n = i + 1; const ocupados = todos.filter((p) => p.caixa === n).length;
      const b = el("button", { type: "button", class: `sec${n === atual ? " ativo" : ""}` }, `Caixa ${n} (${ocupados}/${tam})`);
      b.addEventListener("click", () => { atual = n; sel = null; desenhar(); });
      return b;
    }));
    const grade = el("div", { class: "cx-grade" }, ...Array.from({ length: tam }, (_, i) => {
      const slot = i + 1; const p = todos.find((x) => x.caixa === atual && x.slot_caixa === slot);
      const b = el("button", { type: "button", class: `cx-slot${p ? "" : " vazio"}${sel && p && sel.id === p.id ? " sel" : ""}`, "aria-label": p ? nomePokemon(p) : `Espaço ${slot} livre` }, p ? mini(p) : "");
      b.addEventListener("click", () => {
        if (p) { sel = p; desenhar(); return; }
        if (sel && sel.caixa !== null && sel.caixa !== undefined && podeMexer) void rodar("caixa_mover", { p_pokemon: sel.id, p_caixa: atual, p_slot: slot }, "Pokémon movido.");
      });
      return b;
    }));
    const detalhe = el("div", { class: "cx-detalhe" });
    if (sel) {
      detalhe.append(el("strong", {}, nomePokemon(sel)), el("span", {}, `Nv ${sel.nivel} · ${sel.hp_atual}/${sel.hp_max} HP`));
      if (podeMexer && sel.caixa != null) {
        const s = sel;
        const levar = el("button", { type: "button" }, "Levar ao time");
        if (time.length >= 6) levar.setAttribute("disabled", "");
        levar.addEventListener("click", () => void rodar("caixa_retirar", { p_pokemon: s.id }, `${nomePokemon(s)} entrou no time.`));
        detalhe.append(levar);
        if (time.length >= 6) detalhe.append(el("span", { class: "sub" }, "Time cheio: troque com um Pokémon do time abaixo."));
      }
    } else detalhe.append(el("span", { class: "sub" }, podeMexer ? "Toque em um Pokémon. Depois toque em outro espaço para mover." : "Toque em um Pokémon para ver os dados."));

    const equipe = el("div", { class: "cx-time" }, ...time.map((p) => {
      const b = el("div", { class: "cx-membro" }, mini(p), el("span", { class: "cx-nome" }, nomePokemon(p)));
      if (podeMexer) {
        if (sel && sel.caixa != null) {
          const s = sel; const t = el("button", { type: "button", class: "sec" }, "Trocar");
          t.addEventListener("click", () => void rodar("caixa_trocar", { p_time: p.id, p_caixa: s.id }, "Troca feita."));
          b.append(t);
        } else {
          const g = el("button", { type: "button", class: "sec" }, "Guardar");
          if (time.length <= 1) g.setAttribute("disabled", "");
          g.addEventListener("click", () => void rodar("caixa_guardar", { p_pokemon: p.id }, `${nomePokemon(p)} foi para a caixa.`));
          b.append(g);
        }
      }
      return b;
    }));
    corpo.replaceChildren(
      el("p", { class: `cx-aviso${podeMexer ? " ok" : ""}` }, podeMexer ? "Você está num lugar seguro: pode guardar, retirar e trocar Pokémon." : "Só dá para guardar, retirar e trocar Pokémon no Centro Pokémon ou no Laboratório do Prof. Carvalho. Aqui você só consulta."),
      abas, grade, detalhe,
      el("label", {}, `Seu time (${time.length}/6)`), equipe,
    );
  }
  desenhar();
  modal.abrir("Caixas", corpo, msg);
}
