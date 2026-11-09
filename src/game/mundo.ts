import Phaser from "phaser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase, type Jogador } from "../supabase";

const BASE = import.meta.env.BASE_URL;

// Geometria dos hexágonos (tiles do Kenney, "pointy-top", 120x140 px; linhas ímpares deslocadas à direita).
const LW = 120;
const LH = 140;
const DX = 120;
const DY = 105;
const RAIO = 69;
const MARGEM = 10;
const ZOOM_MAX = 1.3;

export interface Hex {
  q: number;
  r: number;
  bioma: string;
  tile: string;
  custo: number;
  bloqueado: boolean;
  poi_id: string | null;
  poi_nome: string | null;
  poi_descricao: string | null;
  rotulo: string | null;
  arco_liberado: number;
}

export interface Poi {
  id: string;
  nome: string;
  descricao: string;
}

/** Como o jogo avisa a interface (DOM) sobre o que acontece. */
export interface Ganchos {
  aoPA(pa: number, max: number): void;
  aoPoi(poi: Poi): void;
  aviso(texto: string): void;
}

export interface Controle {
  encerrar(): void;
  zoom(fator: number): void;
  centralizar(): void;
  atualizarPA(): Promise<void>;
}

/** O que cada jogador anuncia na presença do mapa (nome e aparência vêm do banco, não daqui). */
interface Posicao {
  q: number;
  r: number;
}

interface Ficha {
  caixa: Phaser.GameObjects.Container;
  q: number;
  r: number;
}

const chaveHex = (q: number, r: number) => `${q},${r}`;

function centro(q: number, r: number): { x: number; y: number } {
  return { x: MARGEM + LW / 2 + q * DX + (r % 2 ? DX / 2 : 0), y: MARGEM + LH / 2 + r * DY };
}

/** Vizinhos na grade "odd-r" (igual à função mover do servidor). */
function vizinhos(q: number, r: number): [number, number][] {
  const d = r % 2 === 0 ? [[-1, 0], [1, 0], [-1, -1], [0, -1], [-1, 1], [0, 1]] : [[-1, 0], [1, 0], [0, -1], [1, -1], [0, 1], [1, 1]];
  return d.map(([dq, dr]) => [q + dq, r + dr]);
}

class CenaMundo extends Phaser.Scene {
  private q: number;
  private r: number;
  private pa: number;
  private movendo = false;
  private encerrada = false;
  private hexes = new Map<string, Hex>();
  private minha!: Ficha;
  private outros = new Map<string, Ficha>();
  private carregando = new Set<string>();
  private presentes: Record<string, Posicao> = {};
  private canal?: RealtimeChannel;
  private destaque!: Phaser.GameObjects.Graphics;
  private chips: Phaser.GameObjects.GameObject[] = [];
  private inicio?: { x: number; y: number; sx: number; sy: number; arrastou: boolean };
  private pinca?: { d0: number; z0: number };
  private ignorarToque = false;
  private largura = 0;
  private altura = 0;

  constructor(
    private readonly jogador: Jogador,
    hexes: Hex[],
    private readonly paMax: number,
    private readonly ganchos: Ganchos,
  ) {
    super("mundo");
    this.q = jogador.x;
    this.r = jogador.y;
    this.pa = jogador.pa;
    for (const h of hexes) this.hexes.set(chaveHex(h.q, h.r), h);
    const colunas = Math.max(...hexes.map((h) => h.q)) + 1;
    const linhas = Math.max(...hexes.map((h) => h.r)) + 1;
    this.largura = MARGEM * 2 + colunas * DX + DX / 2;
    this.altura = MARGEM * 2 + (linhas - 1) * DY + LH;
  }

  preload(): void {
    for (const tile of new Set([...this.hexes.values()].map((h) => h.tile))) this.load.image(tile, `${BASE}assets/hex/${tile}.png`);
    this.load.spritesheet("treinadores", `${BASE}assets/personagens.png`, { frameWidth: 16, frameHeight: 16 });
  }

  create(): void {
    this.textures.get("treinadores").setFilter(Phaser.Textures.FilterMode.NEAREST);

    for (const h of this.hexes.values()) {
      const { x, y } = centro(h.q, h.r);
      this.add.image(x, y, h.tile).setDepth(0);
      if (h.rotulo) {
        this.add
          .text(x, y + (h.poi_id ? 38 : 10), h.rotulo, {
            fontFamily: "monospace",
            fontSize: "20px",
            fontStyle: "bold",
            color: "#fffbe6",
            stroke: "#0f380f",
            strokeThickness: 6,
          })
          .setOrigin(0.5, 0)
          .setDepth(8);
      }
    }
    this.destaque = this.add.graphics().setDepth(6);

    this.minha = this.criarFicha(this.jogador.nome, this.jogador.aparencia, this.q, this.r, 11);

    const cam = this.cameras.main;
    cam.setBounds(0, 0, this.largura, this.altura);
    this.ajustarZoom(true);
    this.centralizar();

    this.input.addPointer(1);
    this.input.on("pointerdown", (p: Phaser.Input.Pointer) => {
      if (this.pinca) return;
      this.inicio = { x: p.x, y: p.y, sx: cam.scrollX, sy: cam.scrollY, arrastou: false };
    });
    this.input.on("pointermove", (p: Phaser.Input.Pointer) => {
      const i = this.inicio;
      if (!i || !p.isDown || this.pinca) return;
      if (!i.arrastou && Math.hypot(p.x - i.x, p.y - i.y) > 8) i.arrastou = true;
      if (i.arrastou) {
        cam.scrollX = i.sx - (p.x - i.x) / cam.zoom;
        cam.scrollY = i.sy - (p.y - i.y) / cam.zoom;
      }
    });
    this.input.on("pointerup", (p: Phaser.Input.Pointer) => {
      const i = this.inicio;
      this.inicio = undefined;
      if (this.ignorarToque) {
        if (!this.input.pointer1.isDown && !this.input.pointer2.isDown) this.ignorarToque = false;
        return;
      }
      if (!i || i.arrastou) return;
      const w = cam.getWorldPoint(p.x, p.y);
      void this.tocar(w.x, w.y);
    });
    this.input.on("wheel", (_p: unknown, _o: unknown, _dx: number, dy: number) => this.zoom(dy > 0 ? 0.9 : 1.1));
    this.scale.on("resize", () => this.ajustarZoom(false));

    this.time.addEvent({ delay: 20000, loop: true, callback: () => void this.atualizarPA() });
    this.atualizarDestaque();
    this.conectar();
  }

  update(): void {
    const p1 = this.input.pointer1;
    const p2 = this.input.pointer2;
    if (p1.isDown && p2.isDown) {
      const d = Phaser.Math.Distance.Between(p1.x, p1.y, p2.x, p2.y);
      if (!this.pinca) {
        this.pinca = { d0: Math.max(d, 1), z0: this.cameras.main.zoom };
        this.inicio = undefined;
        this.ignorarToque = true;
      } else {
        this.definirZoom((this.pinca.z0 * d) / this.pinca.d0);
      }
    } else if (this.pinca && !p1.isDown && !p2.isDown) {
      this.pinca = undefined;
    }
  }

  // ---------- Câmera ----------

  private zoomMin(): number {
    return Math.min(this.scale.width / this.largura, this.scale.height / this.altura);
  }

  private definirZoom(z: number): void {
    this.cameras.main.setZoom(Phaser.Math.Clamp(z, this.zoomMin(), ZOOM_MAX));
  }

  private ajustarZoom(inicial: boolean): void {
    const cam = this.cameras.main;
    if (inicial) this.definirZoom(this.scale.width / (6 * DX));
    else this.definirZoom(cam.zoom);
  }

  zoom(fator: number): void {
    this.definirZoom(this.cameras.main.zoom * fator);
  }

  centralizar(): void {
    const { x, y } = centro(this.q, this.r);
    this.cameras.main.centerOn(x, y);
  }

  // ---------- Fichas ----------

  private criarFicha(nome: string, aparencia: number, q: number, r: number, profundidade: number): Ficha {
    const { x, y } = centro(q, r);
    const sprite = this.add.sprite(0, 26, "treinadores", aparencia * 12).setOrigin(0.5, 1).setScale(4);
    const rotulo = this.add
      .text(0, -42, nome, { fontFamily: "monospace", fontSize: "18px", fontStyle: "bold", color: "#e8f4c8", stroke: "#0f380f", strokeThickness: 5 })
      .setOrigin(0.5, 1);
    const caixa = this.add.container(x, y, [sprite, rotulo]).setDepth(profundidade);
    return { caixa, q, r };
  }

  /** Posição final de cada ficha; quem divide o mesmo hexágono fica lado a lado. */
  private reposicionar(rapido = false): void {
    const grupos = new Map<string, string[]>();
    const todas: [string, Ficha][] = [["__eu__", this.minha], ...this.outros.entries()];
    for (const [id, f] of todas) {
      const k = chaveHex(f.q, f.r);
      grupos.set(k, [...(grupos.get(k) ?? []), id]);
    }
    for (const [id, f] of todas) {
      const ocupantes = (grupos.get(chaveHex(f.q, f.r)) ?? []).sort();
      const { x, y } = centro(f.q, f.r);
      const alvoX = x + (ocupantes.indexOf(id) - (ocupantes.length - 1) / 2) * 34;
      this.tweens.killTweensOf(f.caixa);
      if (rapido) f.caixa.setPosition(alvoX, y);
      else this.tweens.add({ targets: f.caixa, x: alvoX, y, duration: 260, ease: "Sine.easeInOut" });
    }
  }

  // ---------- Toque e movimento ----------

  private hexEm(x: number, y: number): Hex | undefined {
    let melhor: Hex | undefined;
    let dist = RAIO - 3;
    for (const h of this.hexes.values()) {
      const c = centro(h.q, h.r);
      const d = Math.hypot(c.x - x, c.y - y);
      if (d < dist) {
        dist = d;
        melhor = h;
      }
    }
    return melhor;
  }

  private async tocar(x: number, y: number): Promise<void> {
    const h = this.hexEm(x, y);
    if (!h || this.movendo) return;
    if (h.q === this.q && h.r === this.r) {
      this.abrirPoi(h);
      return;
    }
    if (!vizinhos(this.q, this.r).some(([q, r]) => q === h.q && r === h.r)) {
      this.ganchos.aviso("Ande um hexágono por vez: toque num vizinho do seu.");
      return;
    }
    if (h.bloqueado) {
      this.ganchos.aviso("O caminho está bloqueado.");
      return;
    }
    if (this.pa < h.custo) {
      this.ganchos.aviso(`PA insuficiente: este terreno custa ${h.custo} e você tem ${this.pa}.`);
      return;
    }
    this.movendo = true;
    this.atualizarDestaque();
    const { data, error } = await supabase.rpc("mover", { p_q: h.q, p_r: h.r });
    this.movendo = false;
    if (this.encerrada) return;
    if (error || !data) {
      this.ganchos.aviso(error?.message ?? "Não foi possível andar.");
      void this.atualizarPA();
      this.atualizarDestaque();
      return;
    }
    const j = data as Jogador;
    this.q = j.x;
    this.r = j.y;
    this.pa = Number(j.pa);
    this.minha.q = this.q;
    this.minha.r = this.r;
    this.ganchos.aoPA(this.pa, this.paMax);
    this.anunciar();
    this.reposicionar();
    this.atualizarDestaque();
    const c = centro(this.q, this.r);
    this.cameras.main.pan(c.x, c.y, 260, "Sine.easeInOut");
    if (h.poi_id) this.time.delayedCall(300, () => this.abrirPoi(h));
  }

  private abrirPoi(h: Hex): void {
    if (h.poi_id && h.poi_nome) this.ganchos.aoPoi({ id: h.poi_id, nome: h.poi_nome, descricao: h.poi_descricao ?? "" });
  }

  private atualizarDestaque(): void {
    this.destaque.clear();
    for (const o of this.chips) o.destroy();
    this.chips = [];
    const cor = (q: number, r: number, alfaLinha: number, alfaFundo: number, cor: number) => {
      const { x, y } = centro(q, r);
      const pts = Array.from({ length: 6 }, (_, k) => {
        const a = ((30 + 60 * k) * Math.PI) / 180;
        return new Phaser.Geom.Point(x + (RAIO - 2) * Math.cos(a), y + (RAIO - 2) * Math.sin(a));
      });
      this.destaque.fillStyle(cor, alfaFundo).fillPoints(pts, true);
      this.destaque.lineStyle(4, cor, alfaLinha).strokePoints(pts, true);
    };
    cor(this.q, this.r, 0.9, 0, 0xffffff);
    if (this.movendo) return;
    for (const [q, r] of vizinhos(this.q, this.r)) {
      const h = this.hexes.get(chaveHex(q, r));
      if (!h || h.bloqueado) continue;
      const pode = this.pa >= h.custo;
      cor(q, r, 0.9, 0.14, pode ? 0xffe14a : 0xb0b0b0);
      const { x, y } = centro(q, r);
      const disco = this.add.circle(x, y - 6, 21, pode ? 0xffe14a : 0x9a9a9a).setStrokeStyle(3, 0x2a1f00).setDepth(7);
      const num = this.add
        .text(x, y - 6, String(h.custo), { fontFamily: "monospace", fontSize: "26px", fontStyle: "bold", color: pode ? "#2a1f00" : "#5a2a2a" })
        .setOrigin(0.5)
        .setDepth(7.5);
      this.chips.push(disco, num);
    }
  }

  async atualizarPA(): Promise<void> {
    const { data } = await supabase.from("jogadores").select("pa").eq("id", this.jogador.id).maybeSingle();
    if (this.encerrada || !data) return;
    this.pa = Number(data.pa);
    this.ganchos.aoPA(this.pa, this.paMax);
    this.atualizarDestaque();
  }

  // ---------- Multijogador (presença no canal privado do mapa) ----------

  private conectar(): void {
    const canal = supabase.channel(`mapa:${this.jogador.mapa_id}`, {
      config: { private: true, presence: { key: this.jogador.id } },
    });
    canal.on("presence", { event: "sync" }, () => this.sincronizar(canal.presenceState<Posicao>()));
    canal.subscribe((status) => {
      if (status === "SUBSCRIBED") this.anunciar();
    });
    this.canal = canal;
  }

  private anunciar(): void {
    if (!this.canal || this.encerrada) return;
    const posicao: Posicao = { q: this.q, r: this.r };
    void this.canal.track(posicao);
  }

  private sincronizar(estado: Record<string, Posicao[]>): void {
    if (this.encerrada) return;
    this.presentes = {};
    for (const [chave, metas] of Object.entries(estado)) {
      if (chave === this.jogador.id || metas.length === 0) continue;
      this.presentes[chave] = metas[metas.length - 1];
    }
    for (const [chave, pos] of Object.entries(this.presentes)) {
      const f = this.outros.get(chave);
      if (f) {
        f.q = pos.q;
        f.r = pos.r;
      } else void this.criarOutro(chave);
    }
    for (const chave of [...this.outros.keys()]) {
      if (!this.presentes[chave]) {
        this.outros.get(chave)?.caixa.destroy();
        this.outros.delete(chave);
      }
    }
    this.reposicionar();
  }

  private async criarOutro(chave: string): Promise<void> {
    if (this.carregando.has(chave) || this.outros.has(chave)) return;
    this.carregando.add(chave);
    const { data } = await supabase.from("jogadores").select("nome, aparencia").eq("id", chave).maybeSingle();
    this.carregando.delete(chave);
    const pos = this.presentes[chave];
    if (this.encerrada || !data || !pos || this.outros.has(chave)) return; // saiu enquanto carregava
    this.outros.set(chave, this.criarFicha(String(data.nome), Number(data.aparencia), pos.q, pos.r, 10));
    this.reposicionar(true);
  }

  /** Sai do canal (ao trocar de tela, sair do jogo ou fechar). */
  desconectar(): void {
    this.encerrada = true;
    if (this.canal) void supabase.removeChannel(this.canal);
    this.canal = undefined;
  }
}

/** Carrega o mapa do banco e cria o jogo dentro de `pai`. */
export async function iniciarMundo(pai: HTMLElement, jogador: Jogador, ganchos: Ganchos): Promise<Controle> {
  const [{ data: hexes, error }, { data: cfg }] = await Promise.all([
    supabase
      .from("hexes")
      .select("q, r, bioma, tile, custo, bloqueado, poi_id, poi_nome, poi_descricao, rotulo, arco_liberado")
      .eq("mapa_id", jogador.mapa_id),
    supabase.from("config").select("valor").eq("chave", "pa_por_dia").maybeSingle(),
  ]);
  if (error || !hexes || hexes.length === 0) throw new Error("Não foi possível carregar o mapa.");
  const paMax = Number(cfg?.valor ?? 10) || 10;

  const cena = new CenaMundo(jogador, hexes as Hex[], paMax, ganchos);
  const jogo = new Phaser.Game({
    type: Phaser.AUTO,
    parent: pai,
    backgroundColor: "#0f380f",
    scale: { mode: Phaser.Scale.RESIZE, width: "100%", height: "100%" },
    scene: cena,
  });
  ganchos.aoPA(jogador.pa, paMax);

  const aoVoltar = () => {
    if (!document.hidden) void cena.atualizarPA();
  };
  document.addEventListener("visibilitychange", aoVoltar);

  return {
    encerrar: () => {
      cena.desconectar();
      document.removeEventListener("visibilitychange", aoVoltar);
      jogo.destroy(true);
    },
    zoom: (f) => cena.zoom(f),
    centralizar: () => cena.centralizar(),
    atualizarPA: () => cena.atualizarPA(),
  };
}
