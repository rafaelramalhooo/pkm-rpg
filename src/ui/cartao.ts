// Bloco de insígnias do Painel do Treinador (cinza até conquistar).
import { supabase } from "../supabase";
import { el } from "./dom";
import { INSIGNIAS, urlInsignia } from "./insignias";

export async function blocoInsignias(uid: string): Promise<HTMLElement> {
  const { data } = await supabase.from("jogadores").select("insignias, campeao").eq("id", uid).maybeSingle();
  const j = (data ?? { insignias: [], campeao: false }) as { insignias: string[] | null; campeao: boolean };
  const tem = new Set(j.insignias ?? []);
  const grade = el("div", { class: "ct-insignias" }, ...INSIGNIAS.map((i) => {
    const ok = tem.has(i.slug);
    const img = el("img", { src: urlInsignia(i.slug), alt: i.nome, class: ok ? "ganha" : "falta", draggable: "false" });
    return el("div", { class: `ct-ins ${ok ? "ganha" : "falta"}`, title: ok ? `Insígnia ${i.nome} — Ginásio de ${i.cidade}` : `Ginásio de ${i.cidade}` }, img, el("span", {}, i.nome), el("small", {}, i.cidade));
  }));
  const n = [...tem].filter((s) => INSIGNIAS.some((i) => i.slug === s)).length;
  return el("div", { class: "dash-ins" }, el("label", {}, `Insígnias (${n}/8)${j.campeao ? " · 🏆 Campeão da Liga" : ""}`), grade);
}
