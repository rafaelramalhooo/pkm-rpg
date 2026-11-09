// Mundo andável: mapa de tiles (16 px) pré-renderizado, personagem animado, multijogador por canal de mapa.
// O servidor decide tudo (andar, portais); o cliente só antecipa o passo para parecer instantâneo.
import Phaser from "phaser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase, type Direcao, type Jogador } from "../supabase";

export interface Poi {
  id: string;
  tipo: string;
  nome: string;
  x: number;
  y: number;
  descricao: string;
}
interface Portal { x: number; y: number; w?: number; h?: number }
interface MapaDados {
  id: string;
  nome: string;
  w: number;
  h: number;
  solido: string;
  grama: string;
  portais: Portal[];
  pois: Poi[];
}

export interface Lugar { mapa_id: string; nome_mapa: string; x: number; y: number; naGrama: boolean; poi: Poi | null }

export interface Ganchos {
  /** O jogador mudou de lugar (ou de mapa). */
  aoLugar(l: Lugar): void;
  /** O servidor devolveu o estado do jogador (posição validada). */
  aoJogador(j: Jogador): void;
  aviso(texto: string): void;
}

export interface Controle {
  encerrar(): void;
  segurar(dir: Direcao | null): void;
  bloquear(sim: boolean): void;
  dizer(texto: string): void;
  recarregarJogador(): Promise<Jogador | null>;
  /** +1 aproxima, -1 afasta, 0 volta ao automático. */
  zoom(passo: -1 | 0 | 1): void;
}

const T = 16;
const PASSO_MS = 150;
const QUADROS: Record<Direcao, number> = { baixo: 0, esquerda: 3, direita: 6, cima: 9 };
const DELTA: Record<Direcao, [number, number]> = { cima: [0, -1], baixo: [0, 1], esquerda: [-1, 0], direita: [1, 0] };
declare const __BUILD__: string;
const BASE = import.meta.env.BASE_URL as string;
const V = `?v=${__BUILD__}`;
const px = (x: number) => x * T + 8;
const py = (y: number) => y * T + 15; // pés do personagem perto da base do tile

interface Ficha {
  sprite: Phaser.GameObjects.Sprite;
  nome: Phaser.GameObjects.Text;
  balao?: Phaser.GameObjects.Text;
  balaoTimer?: Phaser.Time.TimerEvent;
  x: number;
  y: number;
  aparencia: number;
  dir: Direcao;
}
interface Presenca { nome: string; aparencia: number; x: number; y: number; dir: Direcao }

function criarAnimacoes(cena: Phaser.Scene, i: number): void {
  const k = `p${i}`;
  (Object.keys(QUADROS) as Direcao[]).forEach((d) => {
    const b = QUADROS[d];
    if (!cena.anims.exists(`${k}-${d}`)) {
      cena.anims.create({
        key: `${k}-${d}`,
        frames: [b, b + 1, b + 2, b + 1].map((frame) => ({ key: k, frame })),
        frameRate: 8,
        repeat: -1,
      });
    }
  });
}

class CenaMundo extends Phaser.Scene {
  private jogador: Jogador;
  private ganchos: Ganchos;
  private mapa!: MapaDados;
  private cacheMapas = new Map<string, MapaDados>();
  private camadas: Phaser.GameObjects.Image[] = [];
  private eu!: Ficha;
  private outros = new Map<string, Ficha>();
  private canal?: RealtimeChannel;
  private teclas!: Record<string, Phaser.Input.Keyboard.Key>;
  private segurando: Direcao | null = null;
  private andando = false;
  private bloqueado = false;
  private mudandoMapa = false;
  private fila: Promise<void> = Promise.resolve();
  private encerrada = false;
  private timerTrack?: number;

  constructor(jogador: Jogador, ganchos: Ganchos) {
    super("mundo");
    this.jogador = { ...jogador };
    this.ganchos = ganchos;
  }

  preload(): void {
    for (let i = 0; i < 12; i++) {
      this.load.spritesheet(`p${i}`, `${BASE}assets/personagens/p${i}.png`, { frameWidth: 16, frameHeight: 32 });
    }
  }

  create(): void {
    for (let i = 0; i < 12; i++) criarAnimacoes(this, i);
    const kb = this.input.keyboard!;
    kb.disableGlobalCapture();
    this.teclas = kb.addKeys("UP,DOWN,LEFT,RIGHT,W,A,S,D") as Record<string, Phaser.Input.Keyboard.Key>;
    this.scale.on("resize", () => this.ajustarZoom());
    void this.entrarNoMapa(this.jogador.mapa_id, true);
  }

  // ---------- mapa ----------

  private async carregarMapa(id: string): Promise<MapaDados> {
    const guardado = this.cacheMapas.get(id);
    if (guardado) return guardado;
    const r = await fetch(`${BASE}assets/mapas/${id}.json${V}`);
    if (!r.ok) throw new Error("Mapa não encontrado.");
    const dados = (await r.json()) as MapaDados;
    await new Promise<void>((ok, erro) => {
      this.load.image(`${id}-baixo`, `${BASE}assets/mapas/${id}.png${V}`);
      this.load.image(`${id}-cima`, `${BASE}assets/mapas/${id}-cima.png${V}`);
      this.load.once("complete", () => ok());
      this.load.once("loaderror", () => erro(new Error("Falha ao carregar a arte do mapa.")));
      this.load.start();
    });
    this.cacheMapas.set(id, dados);
    return dados;
  }

  private async entrarNoMapa(id: string, primeira = false): Promise<void> {
    this.mudandoMapa = true;
    let dados: MapaDados;
    try {
      dados = await this.carregarMapa(id);
    } catch (e) {
      this.ganchos.aviso(e instanceof Error ? e.message : "Erro ao abrir o mapa.");
      this.mudandoMapa = false;
      return;
    }
    if (this.encerrada) return;
    this.mapa = dados;
    for (const c of this.camadas) c.destroy();
    const baixo = this.add.image(0, 0, `${id}-baixo`).setOrigin(0, 0).setDepth(0);
    const cima = this.add.image(0, 0, `${id}-cima`).setOrigin(0, 0).setDepth(1000);
    this.camadas = [baixo, cima];
    this.limparOutros();

    if (primeira) {
      this.eu = this.criarFicha(this.jogador.nome, this.jogador.aparencia, this.jogador.x, this.jogador.y, this.jogador.direcao, true);
    } else {
      this.colocar(this.eu, this.jogador.x, this.jogador.y);
      this.eu.dir = this.jogador.direcao;
      this.eu.sprite.anims.stop();
      this.eu.sprite.setFrame(QUADROS[this.eu.dir] + 1);
    }
    const c = this.cameras.main;
    c.startFollow(this.eu.sprite, true, 1, 1);
    c.roundPixels = true;
    this.ajustarZoom();
    this.conectar();
    this.mudandoMapa = false;
    this.avisarLugar();
  }

  private nivelZoom: number | null = (() => {
    try {
      const v = Number(localStorage.getItem("pkm-zoom"));
      return v >= 1 && v <= 6 ? v : null;
    } catch {
      return null;
    }
  })();

  private ajustarZoom(): void {
    const auto = Math.max(1.5, Math.min(4, Math.round(Math.min(this.scale.width / 420, this.scale.height / 280) * 2) / 2));
    const c = this.cameras.main;
    c.setZoom(this.nivelZoom ?? auto);
    if (this.mapa) {
      // com o mapa menor que a tela (zoom afastado), centraliza em vez de encostar no canto
      const mw = this.mapa.w * T;
      const mh = this.mapa.h * T;
      const vw = this.scale.width / c.zoom;
      const vh = this.scale.height / c.zoom;
      c.setBounds(-Math.max(0, vw - mw) / 2, -Math.max(0, vh - mh) / 2, Math.max(mw, vw), Math.max(mh, vh));
    }
  }

  zoom(passo: -1 | 0 | 1): void {
    const NIVEIS = [1, 1.5, 2, 3, 4, 5, 6];
    if (passo === 0) this.nivelZoom = null;
    else {
      const atual = this.cameras.main.zoom;
      let i = NIVEIS.findIndex((n) => n >= atual - 0.01);
      if (i < 0) i = NIVEIS.length - 1;
      i = Math.max(0, Math.min(NIVEIS.length - 1, i + passo));
      this.nivelZoom = NIVEIS[i];
    }
    try {
      if (this.nivelZoom === null) localStorage.removeItem("pkm-zoom");
      else localStorage.setItem("pkm-zoom", String(this.nivelZoom));
    } catch { /* sem armazenamento: vale só nesta sessão */ }
    this.ajustarZoom();
  }

  private naGrama(x: number, y: number): boolean {
    return this.mapa.grama.charAt(y * this.mapa.w + x) === "1";
  }
  private solido(x: number, y: number): boolean {
    if (x < 0 || y < 0 || x >= this.mapa.w || y >= this.mapa.h) return true;
    return this.mapa.solido.charAt(y * this.mapa.w + x) === "1";
  }
  private poiEm(x: number, y: number): Poi | null {
    return this.mapa.pois.find((p) => p.x === x && p.y === y) ?? null;
  }
  private portalEm(x: number, y: number): boolean {
    return this.mapa.portais.some((p) => x >= p.x && x < p.x + (p.w ?? 1) && y >= p.y && y < p.y + (p.h ?? 1));
  }

  private avisarLugar(): void {
    const x = this.jogador.x;
    const y = this.jogador.y;
    this.ganchos.aoLugar({ mapa_id: this.mapa.id, nome_mapa: this.mapa.nome, x, y, naGrama: this.naGrama(x, y), poi: this.poiEm(x, y) });
  }

  // ---------- fichas (personagens) ----------

  private criarFicha(nome: string, aparencia: number, x: number, y: number, dir: Direcao, dono = false): Ficha {
    const sprite = this.add.sprite(px(x), py(y), `p${aparencia}`, QUADROS[dir] + 1).setOrigin(0.5, 0.875);
    const texto = this.add
      .text(0, 0, nome, { fontFamily: "monospace", fontSize: "6px", color: dono ? "#ffffff" : "#e8f0a0", stroke: "#0b1020", strokeThickness: 2 })
      .setOrigin(0.5, 1)
      .setResolution(4);
    texto.texture.setFilter(Phaser.Textures.FilterMode.LINEAR);
    const f: Ficha = { sprite, nome: texto, x, y, aparencia, dir };
    this.posicionarAcessorios(f);
    return f;
  }

  private posicionarAcessorios(f: Ficha): void {
    f.sprite.setDepth(10 + f.sprite.y);
    f.nome.setPosition(f.sprite.x, f.sprite.y - 17).setDepth(2000);
    f.balao?.setPosition(f.sprite.x, f.sprite.y - 24).setDepth(2001);
  }

  private colocar(f: Ficha, x: number, y: number): void {
    this.tweens.killTweensOf(f.sprite);
    f.x = x;
    f.y = y;
    f.sprite.setPosition(px(x), py(y));
    this.posicionarAcessorios(f);
  }

  private moverFicha(f: Ficha, x: number, y: number, dir: Direcao, ms: number): void {
    this.tweens.killTweensOf(f.sprite);
    f.x = x;
    f.y = y;
    f.dir = dir;
    f.sprite.anims.play(`p${f.aparencia}-${dir}`, true);
    this.tweens.add({
      targets: f.sprite,
      x: px(x),
      y: py(y),
      duration: ms,
      ease: "Linear",
      onUpdate: () => this.posicionarAcessorios(f),
      onComplete: () => {
        f.sprite.anims.stop();
        f.sprite.setFrame(QUADROS[dir] + 1);
        this.posicionarAcessorios(f);
      },
    });
  }

  private limparOutros(): void {
    for (const f of this.outros.values()) this.destruirFicha(f);
    this.outros.clear();
  }
  private destruirFicha(f: Ficha): void {
    this.tweens.killTweensOf(f.sprite);
    f.balaoTimer?.remove();
    f.sprite.destroy();
    f.nome.destroy();
    f.balao?.destroy();
  }

  private mostrarBalao(f: Ficha, texto: string): void {
    f.balao?.destroy();
    f.balaoTimer?.remove();
    const b = this.add
      .text(0, 0, texto.slice(0, 60), {
        fontFamily: "monospace", fontSize: "6px", color: "#0f380f", backgroundColor: "#f0f8c0",
        padding: { x: 3, y: 2 }, wordWrap: { width: 90 }, align: "center",
      })
      .setOrigin(0.5, 1)
      .setResolution(4);
    b.texture.setFilter(Phaser.Textures.FilterMode.LINEAR);
    f.balao = b;
    this.posicionarAcessorios(f);
    f.balaoTimer = this.time.delayedCall(5000, () => {
      b.destroy();
      if (f.balao === b) f.balao = undefined;
    });
  }

  // ---------- entrada e movimento ----------

  segurar(d: Direcao | null): void {
    this.segurando = d;
  }
  bloquear(sim: boolean): void {
    this.bloqueado = sim;
    if (sim) this.segurando = null;
  }

  private direcaoDoTeclado(): Direcao | null {
    const t = this.teclas;
    if (t.UP.isDown || t.W.isDown) return "cima";
    if (t.DOWN.isDown || t.S.isDown) return "baixo";
    if (t.LEFT.isDown || t.A.isDown) return "esquerda";
    if (t.RIGHT.isDown || t.D.isDown) return "direita";
    return null;
  }

  override update(): void {
    if (!this.mapa || this.encerrada) return;
    const digitando = document.activeElement instanceof HTMLInputElement || document.activeElement instanceof HTMLTextAreaElement;
    if (this.andando || this.mudandoMapa || this.bloqueado) return;
    const d = this.segurando ?? (digitando ? null : this.direcaoDoTeclado());
    if (d) this.passo(d);
  }

  private passo(d: Direcao): void {
    const [dx, dy] = DELTA[d];
    const nx = this.jogador.x + dx;
    const ny = this.jogador.y + dy;
    this.eu.dir = d;
    if (this.solido(nx, ny)) {
      this.eu.sprite.anims.stop();
      this.eu.sprite.setFrame(QUADROS[d] + 1);
      return;
    }
    if (this.portalEm(nx, ny)) {
      void this.atravessarPortal(d);
      return;
    }
    this.andando = true;
    this.jogador.x = nx;
    this.jogador.y = ny;
    this.jogador.direcao = d;
    this.moverFicha(this.eu, nx, ny, d, PASSO_MS);
    void this.canal?.send({ type: "broadcast", event: "mov", payload: { id: this.jogador.id, x: nx, y: ny, dir: d } });
    this.time.delayedCall(PASSO_MS, () => {
      this.andando = false;
      this.avisarLugar();
      this.rastrear();
    });
    this.enviarPasso(d);
  }

  private enviarPasso(d: Direcao): void {
    this.fila = this.fila.then(async () => {
      if (this.encerrada) return;
      const { data, error } = await supabase.rpc("andar", { p_dir: d });
      if (this.encerrada) return;
      if (error || !data) {
        if (error && !/devagar/i.test(error.message)) this.ganchos.aviso(error.message);
        await this.ressincronizar();
        return;
      }
      const s = data as Jogador;
      if (s.mapa_id !== this.mapa.id) return;
      this.ganchos.aoJogador(s);
      if (!this.andando && (s.x !== this.jogador.x || s.y !== this.jogador.y)) {
        this.jogador = { ...this.jogador, ...s };
        this.colocar(this.eu, s.x, s.y);
        this.avisarLugar();
      }
    });
  }

  private async atravessarPortal(d: Direcao): Promise<void> {
    this.mudandoMapa = true;
    await this.fila;
    const { data, error } = await supabase.rpc("andar", { p_dir: d });
    if (this.encerrada) return;
    if (error || !data) {
      this.ganchos.aviso(error?.message ?? "Não foi possível passar.");
      this.mudandoMapa = false;
      await this.ressincronizar();
      return;
    }
    const s = data as Jogador;
    this.jogador = { ...this.jogador, ...s };
    this.ganchos.aoJogador(this.jogador);
    if (s.mapa_id !== this.mapa.id) await this.entrarNoMapa(s.mapa_id);
    else {
      this.colocar(this.eu, s.x, s.y);
      this.mudandoMapa = false;
      this.avisarLugar();
    }
  }

  /** Volta ao estado que o servidor conhece (após erro ou recusa). */
  private async ressincronizar(): Promise<void> {
    const j = await this.recarregar();
    if (!j || this.encerrada) return;
    if (j.mapa_id !== this.mapa.id) {
      await this.entrarNoMapa(j.mapa_id);
      return;
    }
    this.andando = false;
    this.colocar(this.eu, j.x, j.y);
    this.avisarLugar();
  }

  async recarregar(): Promise<Jogador | null> {
    const { data } = await supabase
      .from("jogadores")
      .select("id, nome, papel, aparencia, mapa_id, x, y, direcao, pa, dinheiro")
      .eq("id", this.jogador.id)
      .maybeSingle();
    if (!data) return null;
    this.jogador = { ...this.jogador, ...(data as Jogador) };
    this.ganchos.aoJogador(this.jogador);
    return this.jogador;
  }

  // ---------- multijogador ----------

  private conectar(): void {
    if (this.canal) void supabase.removeChannel(this.canal);
    const canal = supabase.channel(`mapa:${this.mapa.id}`, {
      config: { private: true, presence: { key: this.jogador.id }, broadcast: { self: false } },
    });
    canal.on("presence", { event: "sync" }, () => this.sincronizar(canal.presenceState<Presenca>()));
    canal.on("broadcast", { event: "mov" }, ({ payload }) => this.aoMover(payload as { id: string; x: number; y: number; dir: Direcao }));
    canal.on("broadcast", { event: "chat" }, ({ payload }) => this.aoChat(payload as { id: string; texto: string }));
    canal.subscribe((status) => {
      if (status === "SUBSCRIBED") this.rastrear(true);
    });
    this.canal = canal;
  }

  private rastrear(agora = false): void {
    if (!this.canal || this.encerrada) return;
    window.clearTimeout(this.timerTrack);
    const enviar = () => {
      const p: Presenca = { nome: this.jogador.nome, aparencia: this.jogador.aparencia, x: this.jogador.x, y: this.jogador.y, dir: this.jogador.direcao };
      void this.canal?.track(p);
    };
    if (agora) enviar();
    else this.timerTrack = window.setTimeout(enviar, 500);
  }

  private sincronizar(estado: Record<string, Presenca[]>): void {
    if (this.encerrada) return;
    const presentes: Record<string, Presenca> = {};
    for (const [chave, metas] of Object.entries(estado)) {
      if (chave === this.jogador.id || metas.length === 0) continue;
      presentes[chave] = metas[metas.length - 1];
    }
    for (const [chave, p] of Object.entries(presentes)) {
      const f = this.outros.get(chave);
      if (!f) this.outros.set(chave, this.criarFicha(p.nome, p.aparencia, p.x, p.y, p.dir));
      else if (!f.sprite.anims.isPlaying) this.colocar(f, p.x, p.y);
    }
    for (const chave of [...this.outros.keys()]) {
      if (!presentes[chave]) {
        this.destruirFicha(this.outros.get(chave)!);
        this.outros.delete(chave);
      }
    }
  }

  private aoMover(p: { id: string; x: number; y: number; dir: Direcao }): void {
    const f = this.outros.get(p.id);
    if (!f || typeof p.x !== "number" || typeof p.y !== "number") return;
    if (Math.abs(f.x - p.x) + Math.abs(f.y - p.y) > 2) this.colocar(f, p.x, p.y);
    this.moverFicha(f, p.x, p.y, p.dir, PASSO_MS);
  }

  private aoChat(p: { id: string; texto: string }): void {
    const f = this.outros.get(p.id);
    if (f && typeof p.texto === "string") this.mostrarBalao(f, p.texto);
  }

  dizer(texto: string): void {
    const t = texto.trim().slice(0, 60);
    if (!t || !this.eu) return;
    this.mostrarBalao(this.eu, t);
    void this.canal?.send({ type: "broadcast", event: "chat", payload: { id: this.jogador.id, texto: t } });
  }

  desconectar(): void {
    this.encerrada = true;
    window.clearTimeout(this.timerTrack);
    if (this.canal) void supabase.removeChannel(this.canal);
    this.canal = undefined;
  }
}

export async function iniciarMundo(pai: HTMLElement, jogador: Jogador, ganchos: Ganchos): Promise<Controle> {
  const cena = new CenaMundo(jogador, ganchos);
  const jogo = new Phaser.Game({
    type: Phaser.AUTO,
    parent: pai,
    backgroundColor: "#0b1020",
    pixelArt: true,
    roundPixels: true,
    scale: { mode: Phaser.Scale.RESIZE, width: "100%", height: "100%" },
    scene: cena,
  });
  return {
    encerrar: () => {
      cena.desconectar();
      jogo.destroy(true);
    },
    segurar: (d) => cena.segurar(d),
    bloquear: (s) => cena.bloquear(s),
    dizer: (t) => cena.dizer(t),
    recarregarJogador: () => cena.recarregar(),
    zoom: (p) => cena.zoom(p),
  };
}
