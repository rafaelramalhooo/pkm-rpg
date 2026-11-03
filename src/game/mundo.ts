import Phaser from "phaser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { supabase, type Direcao, type Jogador } from "../supabase";

const T = 16;
export const LARGURA = 160;
export const ALTURA = 144;
const MS_POR_PASSO = 200; // 5 tiles/s (o servidor aceita até ~6 tiles/s)
const BASE = import.meta.env.BASE_URL;

const DIRS: Record<Direcao, { dx: number; dy: number; idx: number }> = {
  baixo: { dx: 0, dy: 1, idx: 0 },
  esquerda: { dx: -1, dy: 0, idx: 1 },
  direita: { dx: 1, dy: 0, idx: 2 },
  cima: { dx: 0, dy: -1, idx: 3 },
};

/** Entrada compartilhada com o direcional de toque (DOM). */
export interface Entrada {
  dir: Direcao | null;
}

interface Saida {
  x: number;
  y: number;
  w: number;
  h: number;
  mensagem: string;
}

/** O que cada jogador anuncia na presença do mapa (nome e aparência vêm do banco, não daqui). */
interface Posicao {
  x: number;
  y: number;
  dir: Direcao;
}

interface Outro {
  sprite: Phaser.GameObjects.Sprite;
  rotulo: Phaser.GameObjects.Text;
  aparencia: number;
  x: number;
  y: number;
  passo: number;
}

class CenaMundo extends Phaser.Scene {
  private tx: number;
  private ty: number;
  private olhando: Direcao;
  private andando = false;
  private passo = 0;
  private sprite!: Phaser.GameObjects.Sprite;
  private colisao!: Phaser.Tilemaps.LayerData;
  private largura = 0;
  private altura = 0;
  private saidas: Saida[] = [];
  private aviso!: Phaser.GameObjects.Text;
  private temporizadorAviso?: Phaser.Time.TimerEvent;
  private teclas!: Record<string, Phaser.Input.Keyboard.Key>;
  private liberaGiro = 0;
  private salvarEm = 0;
  private ultimoSalvo: string;
  private salvando = false;
  private canal?: RealtimeChannel;
  private presentes: Record<string, Posicao> = {};
  private outros = new Map<string, Outro>();
  private carregando = new Set<string>();
  private encerrada = false;

  constructor(
    private readonly jogador: Jogador,
    private readonly entrada: Entrada,
  ) {
    super("mundo");
    this.tx = jogador.x;
    this.ty = jogador.y;
    this.olhando = jogador.direcao;
    this.ultimoSalvo = this.chave();
  }

  preload(): void {
    this.load.image("tiles", `${BASE}assets/tiles.png`);
    this.load.spritesheet("treinadores", `${BASE}assets/personagens.png`, { frameWidth: T, frameHeight: T });
    this.load.tilemapTiledJSON("pallet", `${BASE}assets/mapas/pallet.json`);
  }

  create(): void {
    const mapa = this.make.tilemap({ key: "pallet" });
    const tileset = mapa.addTilesetImage("tiles", "tiles")!;
    mapa.createLayer("chao", tileset);
    mapa.createLayer("decoracao", tileset);
    this.colisao = mapa.getLayer("colisao")!;
    this.largura = mapa.width;
    this.altura = mapa.height;

    for (const o of mapa.getObjectLayer("saidas")?.objects ?? []) {
      const mensagem = (o.properties as { name: string; value: string }[] | undefined)?.find((p) => p.name === "mensagem");
      this.saidas.push({ x: o.x ?? 0, y: o.y ?? 0, w: o.width ?? T, h: o.height ?? T, mensagem: mensagem?.value ?? "Saída em construção" });
    }

    this.sprite = this.add.sprite(this.tx * T, this.ty * T, "treinadores", this.quadro(0)).setOrigin(0, 0).setDepth(10);

    const cam = this.cameras.main;
    cam.setBounds(0, 0, this.largura * T, this.altura * T);
    cam.startFollow(this.sprite, true, 1, 1, -T / 2, -T / 2);

    this.aviso = this.add
      .text(LARGURA / 2, ALTURA - 4, "", {
        fontFamily: "monospace",
        fontSize: "8px",
        color: "#9bbc0f",
        backgroundColor: "#0f380f",
        padding: { x: 3, y: 2 },
      })
      .setOrigin(0.5, 1)
      .setScrollFactor(0)
      .setDepth(100)
      .setVisible(false);

    // Teclado sem "capturar" as teclas (para não atrapalhar a digitação nos formulários).
    this.teclas = this.input.keyboard!.addKeys("UP,DOWN,LEFT,RIGHT,W,A,S,D", false) as Record<string, Phaser.Input.Keyboard.Key>;

    this.conectar();
  }

  update(tempo: number): void {
    if (this.andando) return;
    const d = this.lerDirecao();
    if (d) {
      this.tentarMover(d, tempo);
      return;
    }
    this.sprite.setFrame(this.quadro(0));
    if (this.salvarEm && tempo >= this.salvarEm) void this.salvar();
  }

  private chave(): string {
    return `${this.tx},${this.ty},${this.olhando}`;
  }

  private quadro(q: number): number {
    return this.jogador.aparencia * 12 + DIRS[this.olhando].idx * 3 + q;
  }

  private lerDirecao(): Direcao | null {
    if (document.activeElement instanceof HTMLInputElement) return null; // digitando
    if (this.entrada.dir) return this.entrada.dir;
    const t = this.teclas;
    if (t.UP.isDown || t.W.isDown) return "cima";
    if (t.DOWN.isDown || t.S.isDown) return "baixo";
    if (t.LEFT.isDown || t.A.isDown) return "esquerda";
    if (t.RIGHT.isDown || t.D.isDown) return "direita";
    return null;
  }

  private bloqueado(x: number, y: number): boolean {
    if (x < 0 || y < 0 || x >= this.largura || y >= this.altura) return true;
    return this.colisao.data[y][x].index > 0;
  }

  private tentarMover(d: Direcao, tempo: number): void {
    if (tempo < this.liberaGiro) return;
    if (d !== this.olhando) {
      // Como nos jogos originais: primeiro vira, depois anda.
      this.olhando = d;
      this.sprite.setFrame(this.quadro(0));
      this.liberaGiro = tempo + 110;
      this.anunciar(this.tx, this.ty);
      return;
    }
    const { dx, dy } = DIRS[d];
    const nx = this.tx + dx;
    const ny = this.ty + dy;
    if (this.bloqueado(nx, ny)) {
      const fora = nx < 0 || ny < 0 || nx >= this.largura || ny >= this.altura;
      if (fora) {
        const s = this.saidas.find((o) => this.tx * T >= o.x && this.tx * T < o.x + o.w && this.ty * T >= o.y && this.ty * T < o.y + o.h);
        if (s) this.mostrarAviso(s.mensagem);
      }
      return;
    }
    this.andando = true;
    this.anunciar(nx, ny); // os outros já começam a caminhar até o tile de destino
    this.passo++;
    this.sprite.setFrame(this.quadro(this.passo % 2 === 1 ? 1 : 2));
    this.tweens.add({
      targets: this.sprite,
      x: nx * T,
      y: ny * T,
      duration: MS_POR_PASSO,
      onComplete: () => {
        this.tx = nx;
        this.ty = ny;
        this.andando = false;
        this.salvarEm = this.time.now + 800;
      },
    });
  }

  private mostrarAviso(texto: string): void {
    this.aviso.setText(texto).setVisible(true);
    this.temporizadorAviso?.remove(false);
    this.temporizadorAviso = this.time.delayedCall(2200, () => this.aviso.setVisible(false));
  }

  // ---------- Multijogador (presença no canal privado do mapa) ----------

  private conectar(): void {
    const canal = supabase.channel(`mapa:${this.jogador.mapa_id}`, {
      config: { private: true, presence: { key: this.jogador.id } },
    });
    canal.on("presence", { event: "sync" }, () => this.sincronizar(canal.presenceState<Posicao>()));
    canal.subscribe((status) => {
      if (status === "SUBSCRIBED") this.anunciar(this.tx, this.ty);
    });
    this.canal = canal;
  }

  private anunciar(x: number, y: number): void {
    if (!this.canal || this.encerrada) return;
    const posicao: Posicao = { x, y, dir: this.olhando };
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
      if (this.outros.has(chave)) this.moverOutro(chave, pos);
      else void this.criarOutro(chave);
    }
    for (const chave of [...this.outros.keys()]) if (!this.presentes[chave]) this.removerOutro(chave);
  }

  private async criarOutro(chave: string): Promise<void> {
    if (this.carregando.has(chave) || this.outros.has(chave)) return;
    this.carregando.add(chave);
    const { data } = await supabase.from("jogadores").select("nome, aparencia").eq("id", chave).maybeSingle();
    this.carregando.delete(chave);
    const pos = this.presentes[chave];
    if (this.encerrada || !data || !pos || this.outros.has(chave)) return; // saiu enquanto carregava
    const aparencia = Number(data.aparencia);
    const sprite = this.add.sprite(pos.x * T, pos.y * T, "treinadores", aparencia * 12 + DIRS[pos.dir].idx * 3).setOrigin(0, 0).setDepth(9);
    const rotulo = this.add
      .text(pos.x * T + T / 2, pos.y * T, String(data.nome), {
        fontFamily: "monospace",
        fontSize: "8px",
        color: "#e8f4c8",
        stroke: "#0f380f",
        strokeThickness: 3,
      })
      .setOrigin(0.5, 1)
      .setDepth(12);
    this.outros.set(chave, { sprite, rotulo, aparencia, x: pos.x, y: pos.y, passo: 0 });
  }

  private moverOutro(chave: string, pos: Posicao): void {
    const o = this.outros.get(chave);
    if (!o) return;
    const base = o.aparencia * 12 + DIRS[pos.dir].idx * 3;
    if (pos.x === o.x && pos.y === o.y) {
      o.sprite.setFrame(base); // só virou
      return;
    }
    const longe = Math.abs(pos.x - o.x) + Math.abs(pos.y - o.y) > 2;
    o.x = pos.x;
    o.y = pos.y;
    o.passo++;
    const duracao = longe ? 0 : MS_POR_PASSO;
    this.tweens.killTweensOf([o.sprite, o.rotulo]);
    o.sprite.setFrame(base + (o.passo % 2 === 1 ? 1 : 2));
    this.tweens.add({ targets: o.sprite, x: pos.x * T, y: pos.y * T, duration: duracao, onComplete: () => o.sprite.setFrame(base) });
    this.tweens.add({ targets: o.rotulo, x: pos.x * T + T / 2, y: pos.y * T, duration: duracao });
  }

  private removerOutro(chave: string): void {
    const o = this.outros.get(chave);
    if (!o) return;
    this.tweens.killTweensOf([o.sprite, o.rotulo]);
    o.sprite.destroy();
    o.rotulo.destroy();
    this.outros.delete(chave);
  }

  /** Sai do canal (ao trocar de tela, sair do jogo ou fechar). */
  desconectar(): void {
    this.encerrada = true;
    if (this.canal) void supabase.removeChannel(this.canal);
    this.canal = undefined;
  }

  /** Guarda a posição no servidor (que valida distância e velocidade). */
  async salvar(): Promise<void> {
    this.salvarEm = 0;
    const chave = this.chave();
    if (chave === this.ultimoSalvo || this.salvando) return;
    this.salvando = true;
    const { error } = await supabase.rpc("salvar_posicao", { p_x: this.tx, p_y: this.ty, p_dir: this.olhando });
    this.salvando = false;
    if (error) console.warn("Não foi possível salvar a posição:", error.message);
    else this.ultimoSalvo = chave;
  }
}

function calcularZoom(controlesVisiveis: boolean): number {
  const larg = window.innerWidth - 24;
  const alt = window.innerHeight - (controlesVisiveis ? 270 : 170);
  return Math.max(1, Math.floor(Math.min(larg / LARGURA, alt / ALTURA)));
}

/** Cria o jogo dentro de `pai`. Devolve uma função que encerra tudo. */
export function iniciarMundo(pai: HTMLElement, jogador: Jogador, entrada: Entrada, controlesVisiveis: () => boolean): () => void {
  const cena = new CenaMundo(jogador, entrada);
  const jogo = new Phaser.Game({
    type: Phaser.AUTO,
    parent: pai,
    width: LARGURA,
    height: ALTURA,
    pixelArt: true,
    roundPixels: true,
    backgroundColor: "#0f380f",
    scale: { mode: Phaser.Scale.NONE, zoom: calcularZoom(controlesVisiveis()) },
    scene: cena,
  });

  const aoRedimensionar = () => jogo.scale.setZoom(calcularZoom(controlesVisiveis()));
  const aoEsconder = () => {
    if (document.hidden) void cena.salvar();
  };
  window.addEventListener("resize", aoRedimensionar);
  document.addEventListener("visibilitychange", aoEsconder);

  return () => {
    void cena.salvar();
    cena.desconectar();
    window.removeEventListener("resize", aoRedimensionar);
    document.removeEventListener("visibilitychange", aoEsconder);
    jogo.destroy(true);
  };
}
