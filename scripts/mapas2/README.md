# Mapas v2 (método .tmx, tile a tile)

Os mapas do jogo são montados por regras (grade de 16 px) e salvos como `.tmx` (Tiled) + JSON/PNG para o jogo.

- `cidade.py` (`gerar(cfg)`), `interior.py`, `gin.py`, `liga.py`, `lab_tmx.py`: motores e configurações.
- `rotas.py`: configuração das 12 rotas (usada pelos `rotaN_tmx.py`, `caminho_va_tmx.py`, `costa*_tmx.py`).
- `verificar.py`: confere cada mapa (alcançabilidade, portais, trilhas, pontos de interesse).
- `integrar.py`: acerta as coordenadas de chegada dos portais e copia JSON/PNG para `public/assets/mapas`.
- `tmx/`: os mapas em formato Tiled (sem os tilesets, que ficam fora do repositório; defina `PACOTE_TILES_DIR`).

Os PNG/JSON do jogo já estão em `public/assets/mapas`; estes scripts só são necessários para refazer mapas.
