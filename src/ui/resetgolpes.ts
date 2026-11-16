// Centro Pokémon: resetar os golpes de um Pokémon por dinheiro. O servidor valida lugar, preço e golpes.
import { supabase } from "../supabase";
import { el } from "./dom";
import { carregarReferencias, golpe, imagemPokemon, meuTime, nomePokemon, NOME_TIPO, type PokemonRow } from "./dados";

type Modal = { abrir: (titulo: string, ...nos: Node[]) => void; fechar: () => void; voltarPara?: (r: (() => void) | null) => void };
type Aviso = (t: string, ms?: number, erro?: boolean) => void;
interface Info { preco: number; padrao: number[]; pool: number[] }
const CAT: Record<string, string> = { status: "Status", physical: "Físico", special: "Especial" };

export async function abrirResetGolpes(modal: Modal, uid: string, dinheiro: number, aviso: Aviso, aoMudar: () => void): Promise<void> {
  await carregarReferencias();
  let saldo = dinheiro;
  const lista = async (): Promise<void> => {
    const time = await meuTime(uid);
    const grade = el("div", { class: "grade-loja" });
    for (const p of time) {
      const b = el("button", { type: "button", class: "item-cartao loja" }, imagemPokemon("frente", p.especie_id, "mini", p.brilhante),
        el("div", { class: "item-txt" }, el("strong", {}, nomePokemon(p)), el("small", {}, `Nv ${p.nivel} · ${(p.golpes ?? []).map((g) => golpe(g.id).nome).join(", ") || "sem golpes"}`)));
      b.addEventListener("click", () => void escolher(p));
      grade.appendChild(b);
    }
    modal.abrir("Resetar golpes", el("p", { class: "sub" }, `Seu dinheiro: ₽ ${saldo}`), el("p", { class: "sub" }, "Escolha o Pokémon. Você pode voltar ao conjunto padrão do nível ou montar de novo o seu, com os golpes que ele já aprendeu."), grade);
  };
  const escolher = async (p: PokemonRow): Promise<void> => {
    const { data, error } = await supabase.rpc("golpes_reset_info", { p_pokemon: p.id });
    if (error) return void aviso(error.message, 4500, true);
    const info = data as Info;
    const sel: number[] = [...info.padrao];
    const msg = el("p", { class: "msg" });
    const cartoes = new Map<number, HTMLElement>();
    const pintar = (): void => { for (const [id, c] of cartoes) c.classList.toggle("sel", sel.includes(id)); conf.disabled = sel.length === 0; conf.textContent = `Confirmar (${sel.length}/4) · ₽ ${info.preco}`; };
    const grade = el("div", { class: "mg-golpes" });
    for (const id of info.pool) {
      const g = golpe(id);
      const c = el("button", { type: "button", class: "mt-golpe" }, el("strong", {}, g.nome),
        el("small", {}, `${NOME_TIPO[g.tipo] ?? g.tipo} · ${CAT[g.categoria] ?? g.categoria} · Poder ${g.poder ?? "—"} · Prec. ${g.precisao ? `${g.precisao}%` : "—"} · PP ${g.pp}`),
        el("small", { class: "mt-desc" }, g.descricao ?? ""));
      c.addEventListener("click", () => {
        const i = sel.indexOf(id);
        if (i >= 0) sel.splice(i, 1); else if (sel.length < 4) sel.push(id); else { msg.className = "msg erro"; msg.textContent = "Máximo de 4 golpes: desmarque um antes."; return; }
        msg.textContent = ""; pintar();
      });
      cartoes.set(id, c); grade.appendChild(c);
    }
    const conf = el("button", { type: "button" }, "Confirmar");
    const padrao = el("button", { type: "button", class: "sec" }, "Usar o conjunto padrão do nível");
    const enviar = async (golpes: number[] | null): Promise<void> => {
      conf.disabled = true; padrao.disabled = true;
      const { data: r, error: e } = await supabase.rpc("golpes_resetar", { p_pokemon: p.id, p_golpes: golpes });
      if (e) { conf.disabled = false; padrao.disabled = false; msg.className = "msg erro"; msg.textContent = e.message; return; }
      saldo = (r as { dinheiro: number }).dinheiro;
      aviso(`Golpes de ${nomePokemon(p)} reiniciados!`, 3500);
      aoMudar();
      await lista();
    };
    conf.addEventListener("click", () => void enviar(sel));
    padrao.addEventListener("click", () => void enviar(null));
    modal.abrir(`Golpes de ${nomePokemon(p)}`, el("p", { class: "sub" }, `Nv ${p.nivel} · Escolha até 4 golpes. Custa ₽ ${info.preco}. O PP volta cheio. Seu dinheiro: ₽ ${saldo}`), grade, el("div", { class: "mg-linha" }, conf, padrao), msg);
    pintar();
  };
  await lista();
}
