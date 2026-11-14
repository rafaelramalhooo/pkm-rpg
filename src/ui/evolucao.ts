// Distribuição livre dos pontos que a evolução dá. O servidor confere tudo (soma exata e regra do 2x).
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias, especie, imagemPokemon } from "./dados";

const STATS = [["atk", "Ataque"], ["def", "Defesa"], ["spa", "Ataque Esp."], ["spd", "Defesa Esp."], ["spe", "Velocidade"]] as const;
type K = (typeof STATS)[number][0];
interface Pend { id: string; especie_id: number; apelido: string | null; nivel: number; atk: number; def: number; spa: number; spd: number; spe: number; evo_pend: { gain: Record<K, number>; pool: number } }

let aberto = false;

/** Abre, um por vez, os Pokémon com pontos de evolução ainda por distribuir. */
export async function distribuirPendentes(): Promise<void> {
  if (aberto) return;
  aberto = true;
  try {
    await carregarReferencias();
    for (let guarda = 0; guarda < 12; guarda++) {
      const { data } = await supabase.from("pokemons").select("id, especie_id, apelido, nivel, atk, def, spa, spd, spe, evo_pend").not("evo_pend", "is", null).limit(1);
      const p = ((data ?? []) as Pend[])[0];
      if (!p) return;
      const feito = await telaDistribuir(p);
      if (feito !== "ok") return;
    }
  } finally { aberto = false; }
}

function telaDistribuir(p: Pend): Promise<"ok" | "depois"> {
  return new Promise((resolver) => {
    const ganho = p.evo_pend.gain, pool = p.evo_pend.pool;
    const base = Object.fromEntries(STATS.map(([k]) => [k, p[k] - ganho[k]])) as Record<K, number>;
    const aloc = Object.fromEntries(STATS.map(([k]) => [k, ganho[k]])) as Record<K, number>;
    const autoVals = STATS.map(([k]) => p[k]);
    const razaoAuto = Math.max(...autoVals) / Math.max(1, Math.min(...autoVals));
    const msg = el("p", { class: "msg" });
    const resta = el("strong", {}, String(0));
    const linhas = new Map<K, { final: HTMLElement; mais: HTMLButtonElement; menos: HTMLButtonElement; pts: HTMLElement }>();
    const ok = el("button", { type: "button" }, "Confirmar distribuição") as HTMLButtonElement;
    const auto = el("button", { type: "button", class: "sec" }, "Usar a distribuição automática") as HTMLButtonElement;
    const depois = el("button", { type: "button", class: "sec" }, "Decidir depois") as HTMLButtonElement;
    const usado = (): number => STATS.reduce((a, [k]) => a + aloc[k], 0);
    const finais = (): number[] => STATS.map(([k]) => base[k] + aloc[k]);
    const regraOk = (): boolean => { const f = finais(); return Math.max(...f) <= Math.max(2, razaoAuto) * Math.max(1, Math.min(...f)); };
    const pintar = (): void => {
      const sobra = pool - usado();
      resta.textContent = String(sobra);
      for (const [k] of STATS) {
        const l = linhas.get(k)!;
        l.pts.textContent = `+${aloc[k]}`;
        l.final.textContent = String(base[k] + aloc[k]);
        l.mais.disabled = sobra <= 0;
        l.menos.disabled = aloc[k] <= 0;
      }
      const f = finais();
      const rOk = regraOk();
      msg.className = rOk ? "msg" : "msg erro";
      msg.textContent = rOk ? `Maior atributo: ${Math.max(...f)} · menor: ${Math.min(...f)} (o maior não pode passar do dobro do menor).` : `O maior atributo (${Math.max(...f)}) passou do dobro do menor (${Math.min(...f)}). Ajuste os pontos.`;
      ok.disabled = sobra !== 0 || !rOk;
    };
    const lista = STATS.map(([k, nome]) => {
      const menos = el("button", { type: "button", class: "evo-pm" }, "−") as HTMLButtonElement;
      const mais = el("button", { type: "button", class: "evo-pm" }, "+") as HTMLButtonElement;
      const pts = el("span", { class: "evo-pts" }, "+0");
      const final = el("strong", { class: "evo-final" }, "0");
      linhas.set(k, { final, mais, menos, pts });
      menos.addEventListener("click", () => { if (aloc[k] > 0) { aloc[k]--; pintar(); } });
      mais.addEventListener("click", () => { if (usado() < pool) { aloc[k]++; pintar(); } });
      return el("div", { class: "evo-linha" }, el("span", { class: "evo-nome" }, nome), el("span", { class: "evo-base" }, String(base[k])), menos, pts, mais, final);
    });
    const fechar = (r: "ok" | "depois"): void => { cobertura.remove(); resolver(r); };
    const enviar = async (valores: Record<K, number>): Promise<void> => {
      ok.disabled = true; auto.disabled = true;
      const { error } = await supabase.rpc("distribuir_evolucao", { p_pokemon: p.id, p_aloc: valores });
      if (error) { msg.className = "msg erro"; msg.textContent = error.message; auto.disabled = false; pintar(); return; }
      fechar("ok");
    };
    ok.addEventListener("click", () => void enviar({ ...aloc }));
    auto.addEventListener("click", () => void enviar({ ...ganho }));
    depois.addEventListener("click", () => fechar("depois"));
    const nome = p.apelido ?? especie(p.especie_id).nome;
    const cartao = el("div", { class: "evo-dist" },
      el("div", { class: "evo-faixa" }, "PONTOS DE EVOLUÇÃO"),
      el("div", { class: "evo-dist-topo" }, imagemPokemon("frente", p.especie_id, "evo-dist-sprite"), el("div", {}, el("h3", {}, `${nome} evoluiu!`), el("p", { class: "sub" }, `Distribua livremente os ${pool} pontos que a evolução trouxe. Só estes pontos podem ser movidos; o restante da ficha fica como está. O maior atributo não pode passar do dobro do menor.`))),
      el("div", { class: "evo-linha cab" }, el("span", {}, "Atributo"), el("span", {}, "Antes"), el("span", {}), el("span", {}, "Pontos"), el("span", {}), el("span", {}, "Final")),
      ...lista,
      el("p", { class: "sub" }, "Pontos restantes: ", resta),
      msg, el("div", { class: "evo-dist-botoes" }, ok, auto, depois));
    const cobertura = el("div", { class: "evo-dist-fundo", role: "dialog" }, cartao);
    document.body.append(cobertura);
    pintar();
  });
}
