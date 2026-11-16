// Painel do Mestre: Mundo vivo (quantidades, raridade, nomes, interruptor e regeração).
import { supabase } from "../supabase";
import { el, mensagem } from "./dom";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;

interface Arq { id: string; nome: string; classe: string; categoria: string; raridade: string; peso: number; max_simultaneo: number; semanal: boolean; custo_pa: number; lote: number; ativo: boolean }
interface Dados {
  ativo: boolean; turno: number; periodo: string; cfg: Record<string, unknown>; arquetipos: Arq[]; nomes: string[];
  agora: { nome: string; arquetipo: string; mapa: string }[]; pokemon: { turno: number; especie_id: number; mapa: string }[]; desafiantes: number;
}

const botao = (texto: string, fn: () => void, classe = ""): HTMLButtonElement => {
  const b = el("button", { type: "button", class: classe }, texto);
  b.addEventListener("click", fn);
  return b;
};
const entrada = (valor: string | number, extra: Record<string, string> = {}): HTMLInputElement => el("input", { type: "number", class: "eg-in", value: String(valor), ...extra });
const campo = (rotulo: string, ...nos: Node[]): HTMLElement => el("label", { class: "eg-campo" }, el("span", { class: "eg-rot" }, rotulo), ...nos);

export async function abrirMestreMundo(modal: Modal, aviso: Aviso): Promise<void> {
  const { data, error } = await supabase.rpc("mestre_mundo_obter");
  if (error || !data) return aviso(error?.message ?? "Não foi possível abrir.", 4000, true);
  const d = data as Dados;
  const c = d.cfg as Record<string, number[] | number>;
  const par = (k: string, pad: number[]): [HTMLInputElement, HTMLInputElement] => {
    const v = (Array.isArray(c[k]) ? c[k] : pad) as number[];
    return [entrada(v[0] ?? pad[0], { min: "0", step: "1" }), entrada(v[1] ?? pad[1], { min: "0", step: "1" })];
  };
  const num = (k: string, pad: number, extra: Record<string, string> = {}): HTMLInputElement => entrada(typeof c[k] === "number" ? (c[k] as number) : pad, { min: "0", ...extra });
  const espCid = par("esp_cidade", [1, 2]); const espOut = par("esp_outro", [1, 3]); const desaf = par("desafiantes", [3, 6]); const rec = par("recompensa_desafiante", [60, 180]);
  const raro = num("raro_chance", 0.15, { step: "0.01", max: "1" }); const sem = num("semanal_chance", 0.35, { step: "0.01", max: "1" });
  const paDes = num("desafiante_pa", 2, { step: "1" }); const mult = num("brilhante_mult", 3, { step: "0.5" }); const apar = num("pokemon_dia_aparicoes", 4, { step: "1", max: "4" });
  const itemCh = num("chance_item_desafiante", 0.2, { step: "0.01", max: "1" });
  const ativo = el("input", { type: "checkbox" }) as HTMLInputElement; ativo.checked = d.ativo;
  const regerar = el("input", { type: "checkbox" }) as HTMLInputElement;
  const nomes = el("textarea", { class: "eg-in", rows: "6" }) as HTMLTextAreaElement; nomes.value = d.nomes.join("\n");
  const msg = el("p", { class: "msg", role: "status" });
  const arqs = d.arquetipos.map((a) => {
    const at = el("input", { type: "checkbox" }) as HTMLInputElement; at.checked = a.ativo;
    const rar = el("select", { class: "eg-in" }, ...["comum", "incomum", "raro"].map((r) => el("option", { value: r }, r))) as HTMLSelectElement; rar.value = a.raridade;
    return { a, at, rar, peso: entrada(a.peso, { min: "0" }), max: entrada(a.max_simultaneo, { min: "0" }), pa: entrada(a.custo_pa, { min: "0" }) };
  });
  const linhaPar = (rotulo: string, p: [HTMLInputElement, HTMLInputElement]): HTMLElement => campo(rotulo, el("span", { class: "eg-par" }, p[0], " a ", p[1]));
  const salvar = botao("Salvar", async () => {
    const pares = (p: [HTMLInputElement, HTMLInputElement]): number[] => [Math.floor(Number(p[0].value) || 0), Math.floor(Number(p[1].value) || 0)];
    const payload = {
      ativo: ativo.checked, regerar: regerar.checked,
      cfg: { esp_cidade: pares(espCid), esp_outro: pares(espOut), desafiantes: pares(desaf), recompensa_desafiante: pares(rec), raro_chance: Number(raro.value), semanal_chance: Number(sem.value),
        desafiante_pa: Math.floor(Number(paDes.value)), brilhante_mult: Number(mult.value), pokemon_dia_aparicoes: Math.floor(Number(apar.value)), chance_item_desafiante: Number(itemCh.value) },
      arquetipos: arqs.map((x) => ({ id: x.a.id, ativo: x.at.checked, raridade: x.rar.value, peso: Math.floor(Number(x.peso.value) || 0), max_simultaneo: Math.floor(Number(x.max.value) || 0), custo_pa: Math.floor(Number(x.pa.value) || 0) })),
      nomes: nomes.value.split("\n").map((s) => s.trim()).filter(Boolean),
    };
    const { error: er } = await supabase.rpc("mestre_mundo_salvar", { p: payload });
    if (er) return mensagem(msg, er.message);
    aviso(regerar.checked ? "Mundo vivo salvo e regerado!" : "Mundo vivo salvo!", 3500);
    void abrirMestreMundo(modal, aviso);
  });
  const lote = (n: number): string => (n === 1 ? "" : ` · lote ${n}`);
  modal.abrir("Mundo vivo",
    el("div", { class: "eg-ajuda" }, el("strong", {}, `Agora: ${d.periodo} (turno ${d.turno + 1}/4)`),
      el("p", {}, `${d.agora.length} NPCs especiais no mundo · ${d.desafiantes} desafiantes hoje nas rotas · Pokémon do dia: ${d.pokemon.map((p) => `#${p.especie_id} em ${p.mapa}`).join("; ") || "ainda não gerado"}.`)),
    el("label", { class: "eg-mod" }, ativo, " Mundo vivo ligado (desligar esconde tudo, sem apagar nada)"),
    el("div", { class: "eg-campos" },
      linhaPar("NPCs especiais por cidade", espCid), linhaPar("NPCs especiais por rota/local", espOut), linhaPar("Desafiantes por rota (por dia)", desaf), linhaPar("Recompensa dos desafiantes (₽)", rec),
      campo("Custo de PA do desafiante", paDes), campo("Chance de arquétipo raro", raro), campo("Chance semanal (domingo)", sem),
      campo("Chance de item do desafiante", itemCh), campo("Multiplicador de brilhante (Pokémon do dia)", mult), campo("Aparições do Pokémon do dia (1 a 4)", apar)),
    el("h3", { class: "eg-cat" }, "Arquétipos de NPC"),
    el("div", { class: "eg-campos" }, ...arqs.map((x) => el("div", { class: "eg-bloco" },
      el("strong", { class: "eg-bloco-tit" }, `${x.a.nome}${lote(x.a.lote)}`),
      el("label", { class: "eg-mod" }, x.at, " Ativo"), campo("Raridade", x.rar), campo("Peso", x.peso), campo("Máx. ao mesmo tempo", x.max), campo("Custo (PA)", x.pa)))),
    el("h3", { class: "eg-cat" }, "Nomes dos NPCs (um por linha)"), nomes,
    el("label", { class: "eg-mod" }, regerar, " Regerar o turno agora ao salvar (os NPCs de hoje mudam de lugar)"),
    el("div", { class: "eg-rodape" }, msg, el("div", { class: "eg-rodape-bt" }, salvar)));
}
