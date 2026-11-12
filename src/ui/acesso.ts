// Presença (batimento a cada 4 s), manutenção e "derrubar todos". Tudo é decidido no servidor (função ping); aqui só se reage.
import { supabase } from "../supabase";

export interface PingEstado {
  agora: string; manutencao: boolean; mensagem: string; derrubar_em: string | null;
  mestre: boolean; personagem: boolean; classe: string | null; em_batalha: boolean;
}
export type ResultadoAcesso = "ok" | "bloqueado";

const A_CADA_MS = 4000;
let timer = 0;
let entrou = 0;
let tela: HTMLElement | null = null;
let faixa: HTMLElement | null = null;
let saindo = false;
const ouvintes = new Set<(e: PingEstado) => void>();

/** Chama o servidor: registra que estou online e devolve o estado do acesso. */
export async function consultar(): Promise<PingEstado | null> {
  const { data, error } = await supabase.rpc("ping");
  if (error || !data) return null;
  return data as PingEstado;
}

export function aoEstado(fn: (e: PingEstado) => void): () => void {
  ouvintes.add(fn);
  return () => ouvintes.delete(fn);
}

function criar(classe: string, ...filhos: (Node | string)[]): HTMLElement {
  const d = document.createElement("div");
  d.className = classe;
  d.append(...filhos);
  return d;
}

function mostrarTela(titulo: string, texto: string, sair = true): void {
  tela?.remove();
  const h = document.createElement("h1");
  h.textContent = titulo;
  const p = document.createElement("p");
  p.textContent = texto;
  const filhos: Node[] = [h, p];
  if (sair) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "sec";
    b.textContent = "Sair";
    b.addEventListener("click", () => void supabase.auth.signOut());
    filhos.push(b);
  }
  tela = criar("manut-tela", criar("painel manut-caixa", ...filhos));
  tela.setAttribute("role", "alertdialog");
  document.body.append(tela);
}

function mostrarFaixa(texto: string): void {
  if (!faixa) { faixa = criar("manut-faixa"); faixa.setAttribute("role", "status"); document.body.append(faixa); }
  faixa.textContent = texto;
}
function esconderFaixa(): void { faixa?.remove(); faixa = null; }

function tratar(d: PingEstado): ResultadoAcesso {
  if (!d.mestre && d.derrubar_em && Date.parse(d.derrubar_em) > entrou && !saindo) {
    saindo = true;
    mostrarTela("Sessão encerrada", "O Mestre encerrou as sessões para fazer ajustes. Você será desconectado...", false);
    window.setTimeout(() => void supabase.auth.signOut().then(() => location.reload()), 2500);
    return "bloqueado";
  }
  const bloqueado = d.manutencao && !d.mestre && !d.em_batalha;
  if (bloqueado) {
    mostrarTela("🔧 Em manutenção", d.mensagem || "Estamos em manutenção. Voltamos já!");
    esconderFaixa();
    return "bloqueado";
  }
  if (tela && !saindo) { location.reload(); return "ok"; }   // a manutenção acabou: recarrega o jogo limpo
  if (d.manutencao && d.mestre) mostrarFaixa("🔧 Manutenção LIGADA: só você (Mestre) consegue jogar agora.");
  else if (d.manutencao) mostrarFaixa(`🔧 ${d.mensagem || "Manutenção"}: termine a batalha para continuar.`);
  else esconderFaixa();
  ouvintes.forEach((f) => f(d));
  return "ok";
}

async function bater(): Promise<void> {
  const d = await consultar();
  if (d) tratar(d);
}

/** Começa a vigiar (após o login). Devolve "bloqueado" se o jogador não pode entrar agora. */
export async function iniciarAcesso(): Promise<ResultadoAcesso> {
  pararAcesso();
  const d = await consultar();
  if (!d) return "ok"; // sem resposta: não trava o jogo por falha de rede
  entrou = Date.parse(d.agora) || Date.now();
  saindo = false;
  const r = tratar(d);
  timer = window.setInterval(() => void bater(), A_CADA_MS);
  document.addEventListener("visibilitychange", aoVisivel);
  return r;
}

function aoVisivel(): void { if (document.visibilityState === "visible") void bater(); }

export function pararAcesso(): void {
  window.clearInterval(timer);
  timer = 0;
  document.removeEventListener("visibilitychange", aoVisivel);
  tela?.remove(); tela = null;
  esconderFaixa();
}

/** Para a tela de login: há manutenção em andamento? (função liberada também para quem ainda não entrou) */
export async function avisoManutencao(): Promise<string | null> {
  const { data } = await supabase.rpc("estado_acesso");
  const d = data as { manutencao?: boolean; mensagem?: string } | null;
  return d?.manutencao ? (d.mensagem || "Estamos em manutenção.") : null;
}
