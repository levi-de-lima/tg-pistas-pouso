# TG — Pistas de Pouso Clandestinas e Mineração na Amazônia

Trabalho de Graduação dedicado a identificar pistas de pouso (legais e
clandestinas) na Amazônia Legal e a investigar a relação espaço-temporal
entre essas pistas e atividade de mineração detectada por sensoriamento
remoto.

O projeto combina dados de pistas (ANAC, OpenStreetMap, MapBiomas,
Mendeley/Dimas e digitalização manual sobre imagens Planet) com diferentes
sistemas de alerta de desmatamento/mineração (DETER, GLAD-S2, GFW, LUCA,
MapBiomas Alerta, PRODES, RADD, SAD, Tropisco) e séries temporais Planet,
e aplica BFAST Lite para estimar o início e o fim da fase mineradora
associada a cada pista.

---

## 1. Estrutura do repositório

```
.
├── tg.Rproj                  # Projeto RStudio
├── README.md                 # Este arquivo
├── .gitignore                # Regras de versionamento
├── windrose_mock.jsx         # Mockup React do plot de windrose
│
├── scripts/                  # Todos os scripts R do pipeline
│   ├── process_base.R              # Etapa 1 — consolida fontes de pistas
│   ├── pistas_legais.R             # Etapa 2 — cruzamento com ANAC
│   ├── estudo_pistas.R             # Etapa 3 — base final (pontos + polígonos)
│   ├── comparative.R               # Etapa 4 — alertas × Planet (tile C63L51)
│   ├── best_alerts.R               # Etapa 4b — omissão / comissão por alerta
│   ├── test_mmu.R                  # Etapa 4c — unidade mínima mapeável (MMU)
│   ├── ts_C63L51.R                 # Etapa 4d — série temporal Planet
│   ├── process_GFW.R               # Etapa 5 — raster GFW → vetor (v1)
│   ├── process_GFW_2.R             # Etapa 5 — raster GFW → vetor (v2, atual)
│   ├── prepare_prodes.R            # Etapa 6 — DETER pré-2019 + kNN com pistas
│   ├── exploratorio.R              # Etapa 6b — kNN GFW × pistas (7 vizinhas)
│   ├── windrose_analyses.R         # Etapa 7 — windrose (versão exploratória)
│   ├── all_windroses.R             # Etapa 7 — windrose para todas as pistas
│   ├── generate_graphs.R           # Etapa 8 — curvas K=1/K=4 + windrose embed
│   ├── generate_graphs2.R          # Etapa 8b — omissão/comissão por alerta
│   └── bfast/                      # Etapa 9 — detecção automática de início/fim
│       ├── README_bfast.md
│       ├── bfast_funcoes.R
│       ├── bfast_analise.R
│       └── bfast_diagnostico_visual.R
│
└── 2_base_pistas/             # Base consolidada de pistas (versionada)
    ├── pistas.xlsx                 # Tabela mestra com datas (start/end/inop)
    ├── pistas-backup.xlsx
    ├── base_pistas.csv
    ├── base_pistas_indexada.{shp,dbf,shx,prj,cpg,qmd}
    ├── processed_base.{shp,dbf,shx,prj}
    ├── final_base.{shp,dbf,shx,prj,cpg}
    ├── base_pistas_atualizada.gpkg
    └── pistas_legais_anac.gpkg
```

---

## 2. Pastas e arquivos não versionados

As pastas abaixo somam mais de **15 GB** de rasters, geopackages e outputs
intermediários, e ficam fora do repositório (ver `.gitignore`):

| Pasta | Conteúdo | Origem |
|---|---|---|
| `1_fontes/` | Fontes brutas: ANAC, área de estudo, DETER, GFW (`.tiff`), hidrografia, MapBiomas, pistas | Download externo |
| `3_planet_orders/` | AOIs e pedidos de imagens Planet, séries temporais por tile | Planet Explorer |
| `4_analise_comparativa/` | Cruzamentos Alert × Planet × DETER, gpkg acumulados, intersecções | `comparative.R` |
| `5_base_final/` | `base_pistas_final.gpkg` (pontos + polígonos), hidrografia recortada, screenshots | `estudo_pistas.R` |
| `6_gfw/` | Rasters e vetorizações GFW por semestre, kNN (`GFW_dist.gpkg`), windroses, compound graphs | `process_GFW*.R`, `windrose_analyses.R`, `all_windroses.R`, `generate_graphs.R` |
| `7_alertas_before/` | DETER mineração 2016-2019 (`deter.gpkg`), centroides e kNN | `prepare_prodes.R` |
| `8_exploratorio/` | Geopackages exploratórios (rios, mineração, centroides, aeroportos) | Exploração ad-hoc |
| `8_bfast_resultados/` | CSVs de saída do BFAST (tabela_final, lags, concordância) + PNGs de distribuição | `scripts/bfast/` |
| `apresentacoes/` | Slides (`*.pptx`), PDFs e prompts da banca / orientação | — |

Além disso, ficam ignorados:

- **Arquivos de sessão R:** `.Rhistory`, `.RData`, `.RDataTmp`, `.Rproj.user/`
- **Locks do Office:** `~$*.xlsx`, `~$*.pptx`, etc.
- **Arquivos de sistema:** `desktop.ini`, `.DS_Store`, `Thumbs.db`
- **Rasters por extensão:** `*.tif`, `*.tiff`, `*.img`
- **Comprimidos:** `*.zip`, `*.tar.gz`, `*.7z`, `*.rar`
- **Journals do GeoPackage:** `*.gpkg-journal`, `*.gpkg-shm`, `*.gpkg-wal`
- **Saídas regeneráveis na raiz:** `deter_dist.gpkg`, `GFW_final.gpkg`

A pasta `2_base_pistas/` é a única pasta numerada versionada — contém os
arquivos mestres relativamente pequenos (xlsx + shapefiles consolidados)
que servem de entrada para o restante do pipeline.

---

## 3. O pipeline, passo a passo

A numeração das pastas reflete a ordem natural da execução. Os scripts
em `scripts/` operam sobre essas pastas usando caminhos relativos a partir
da raiz do projeto.

### Etapa 1 — Consolidar fontes de pistas (`process_base.R`)
Lê as pistas combinadas (`2_base_pistas/final_base.shp`) e a área de
estudo, marca a origem de cada feição (MapBiomas, OSM, OSM-Poly, Manual,
Dimas) com flags binárias, aplica `st_buffer(200 m)` + `sf_dissolve()` para
agrupar pistas duplicadas em **clusters** e agrega cada cluster em um
centroide (`processed_base.shp`).

### Etapa 2 — Cruzamento com ANAC (`pistas_legais.R`)
Lê o cadastro consolidado da ANAC (`anac_consolidated.csv`), recorta-o
para a área de estudo, aplica buffer de 550 m e intersecciona com a base
gerada na Etapa 1 para marcar a flag `Anac = 1` (pista legalmente
cadastrada). Saída: `2_base_pistas/base_pistas_atualizada.gpkg` e
`2_base_pistas/pistas_legais_anac.gpkg`.

### Etapa 3 — Base final com datas (`estudo_pistas.R`)
Junta `2_base_pistas/pistas.xlsx` (planilha **mestra** com `start_date`,
`end_date`, `inop_date` preenchidos manualmente a partir de inspeção
visual das séries Planet) com `base_pistas_atualizada.gpkg`. Calcula
ano-semestre de início e fim, corrige pistas sem centroide, gera um
**screenshot por pista** (`5_base_final/screenshots/Pista_<id>.png`) sobre
Esri World Imagery e identifica pares de pistas próximas (< 1 km). Saída
final: `5_base_final/base_pistas_final.gpkg`, com camadas `pontos` e
`poligonos`.

### Etapa 4 — Comparação entre sistemas de alerta (`comparative.R`)
No tile de teste **C63L51** (que contém as pistas 11, 12, 13 e 2432),
carrega 9 fontes de alerta — DETER, GLAD-S2, GFW, LUCA, MapBiomas, PRODES,
RADD, SAD, Tropisco — e a série Planet (`temp_series_dissolved.gpkg`).

Para cada alerta aplica a **MMU** (buffer +50 m → dissolve → buffer −50 m
→ filtra área > 10 000 m²), classifica em semestres, acumula área no
tempo e calcula, por semestre, três conjuntos: `Intersection`,
`Planet-Alert` (omissão), `Alert-Planet` (comissão). Saídas:
`4_analise_comparativa/{Intersections,Alert-Planet,Planet-Alert}/<alert>.gpkg`
e `df_track.gpkg` com a área por (alerta × ano-semestre × track).

- `best_alerts.R` lê `df_track.gpkg`, calcula taxa de omissão
  (`Planet_Only / Planet`) e comissão (`Alert_Only / Alert`) por
  semestre e plota uma grade `facet_wrap(~alerta)`.
- `test_mmu.R` testa a MMU isolada sobre GFW e visualiza filtragem.
- `ts_C63L51.R` constrói a série Planet dissolvida (`temp_series_dissolved.gpkg`)
  a partir dos shapefiles `temporal_series_C63L51/`, semestralizada.

### Etapa 5 — Processamento do GFW (`process_GFW_2.R`)
Pega o raster `GWF_ALB.tiff` (Global Forest Watch, codificação
`30000+dias` para *high* e `40000+dias` para *highest confidence*),
recorta à área de estudo, reclassifica cada pixel para o `ano_semestre`
correspondente, aplica `terra::sieve()` para remover ruído isolado e
vetoriza **por semestre** em `6_gfw/GWF_vetorizado_2.gpkg` (camada
`sem_YYYYS`). Em seguida concatena (`bind_rows`) os 14 semestres,
aplica a MMU global e gera `GFW_binded.gpkg` / `GFW_final.gpkg`.

`process_GFW.R` é uma versão anterior, mantida para referência.

### Etapa 6 — Vizinhança pista × alerta (`prepare_prodes.R`, `exploratorio.R`)
Para cada **detecção** do GFW (centroides) calcula, com `dbscan::kNN`,
as **7 pistas mais próximas** e suas distâncias, salvando as colunas
`pista_1..pista_7` e `dist_1..dist_7` em `6_gfw/GFW_dist.gpkg`. O mesmo
é feito para DETER 2016-2019 (`prepare_prodes.R`), gerando o
`7_alertas_before/deter_dist.gpkg`, que estende a série GFW (que começa
em 2019) para trás até 2016. As duas fontes são empilhadas (`bind_rows`)
nas etapas seguintes.

`exploratorio.R` também faz um diagnóstico de densidade de pistas
(quantas vizinhas dentro de 6 km).

### Etapa 7 — Windroses por pista (`all_windroses.R`)
Para cada pista, gera um gráfico polar (windrose) onde:

- o ângulo é a direção (em bins de 15°) da detecção em relação ao ponto
  central da pista;
- o raio é a distância em buckets de 1 km (até `buffer_lim = 6 km`);
- a cor codifica **data média** (verde), **área total minerada** (vermelho)
  ou **moda da pista mais próxima** (categórica);
- sobre o plot são desenhados rios (`5_base_final/curso_dagua.gpkg`) e
  pistas vizinhas dentro do buffer.

Saída: `6_gfw/all_wind_2/pista_<id>_data.png` (e variações
`_area.png`, `_id.png` na versão exploratória `windrose_analyses.R`).

### Etapa 8 — Curvas cumulativas e gráficos compostos (`generate_graphs.R`)
Para cada pista, monta a série temporal de **área acumulada de mineração**
no entorno, com duas granularidades:

- `K = 1` — só conta detecções cuja pista mais próxima é a pista alvo
  (interpretação causal direta);
- `K = 4` — conta detecções que listam a pista alvo entre suas 4 mais
  próximas (mais permissivo, captura cluster de pistas).

A série diária é interpolada linearmente (`approx`) para preencher dias
sem detecção, e o gráfico é combinado com a windrose correspondente via
`cowplot::ggdraw + draw_image`. Saída:
`6_gfw/compound_graphs/pista_<id>_data.png`.

`generate_graphs2.R` é a versão paralela para taxas de omissão/comissão.

### Etapa 9 — Detecção automática de início e fim com BFAST (`scripts/bfast/`)
Toma a série mensal de **taxa** (e não a cumulativa) de mineração em torno
de cada pista, em K=1 e K=4, e aplica `bfast::bfastlite()` para estimar
breakpoints estruturais. Cada segmento é classificado como **ativo** se
passar em dois testes:

1. **absoluto** — média do segmento > `frac_limiar × max(médias)`;
2. **relativo** — não houve queda > `queda_rel` em relação ao maior pico
   já visto (filtra "platôs com ruído").

A partir dos segmentos ativos, extrai `inicio_estimado` e `fim_estimado`
e compara com a verdade-de-campo (`vline_inicio = start_date`,
`vline_fim = pmin(end_date, inop_date)`) anotada em `pistas.xlsx`. Saídas
em `8_bfast_resultados/`:

- `tabela_final.csv` — uma linha por pista com estimativas K=1, K=4 e
  decisão final (K=1 prioritário, K=4 como fallback).
- `diagnostico_K.csv` — concordância entre K=1 e K=4.
- `resumo_concordancia.csv`, `resumo_lags.csv` — estatísticas agregadas
  (média/mediana dos lags em dias) + teste de Wilcoxon.
- `dist_lag_inicio.png`, `dist_lag_fim.png` — histograma das defasagens.

Detalhes, parâmetros e status possíveis estão documentados em
[`scripts/bfast/README_bfast.md`](scripts/bfast/README_bfast.md).

---

## 4. Fluxo de dependências (resumido)

```
1_fontes/  ─┐
            ├─► process_base.R       ─► 2_base_pistas/processed_base
            ├─► pistas_legais.R      ─► 2_base_pistas/base_pistas_atualizada.gpkg
            └─► estudo_pistas.R      ─► 5_base_final/base_pistas_final.gpkg
                                          (pontos + polígonos)

1_fontes/gwf/GWF_ALB.tiff
    │
    ▼
process_GFW_2.R  ─► 6_gfw/GFW_binded.gpkg ─► GFW_final.gpkg

GFW_final.gpkg + base_pistas_final.gpkg
    │
    ▼
prepare_prodes.R / exploratorio.R  ─► 6_gfw/GFW_dist.gpkg
                                       7_alertas_before/deter_dist.gpkg

GFW_dist.gpkg + deter_dist.gpkg
    │
    ├─► all_windroses.R     ─► 6_gfw/all_wind_2/*.png
    ├─► generate_graphs.R   ─► 6_gfw/compound_graphs/*.png
    └─► scripts/bfast/      ─► 8_bfast_resultados/*

3_planet_orders/temporal_series_C63L51/
    │
    ▼
ts_C63L51.R  ─► 3_planet_orders/temp_series_dissolved.gpkg
    │
    ▼
comparative.R  ─► 4_analise_comparativa/{Intersections,Alert-Planet,Planet-Alert}/
                  4_analise_comparativa/df_track.gpkg
    │
    ▼
best_alerts.R  ─► gráficos omissão/comissão
```

---

## 5. Como reproduzir

1. **Clonar o repositório**
   ```bash
   git clone https://github.com/levi-de-lima/tg-pistas-pouso.git
   cd tg-pistas-pouso
   ```

2. **Abrir o `tg.Rproj` no RStudio** (define automaticamente o diretório
   de trabalho como a raiz do projeto, que é o esperado pelos scripts).

3. **Popular as pastas de dados** com os arquivos brutos (não
   versionados). Estrutura mínima esperada:

   ```
   1_fontes/
     ├── anac/anac_consolidated.csv
     ├── area_estudo/{area_de_estudo.gpkg, tiles_area_estudo.shp, ...}
     ├── deter/Deter_before.gpkg, Deter_cropped.gpkg
     ├── gwf/GWF_ALB.tiff
     ├── hidrografia/...
     ├── mapbiomas/...
     └── pistas/...

   3_planet_orders/
     ├── aois_*-*-*-*-*/
     ├── pistas_geometria/aois_417.shp
     ├── temporal_series_C63L51/aois_116.shp
     └── adicionais/aois_7.shp

   4_analise_comparativa/Alerts/
     ├── Deter_sel.gpkg, GLADS2_sel.gpkg, GWF_sel.gpkg,
     ├── LUCA_sel.gpkg, MapBiomas_sel.gpkg, RADD_sel.gpkg,
     ├── Prodes_sel.gpkg, Prodes_before_sel_class.gpkg,
     └── SAD.gpkg, Tropisco_sel.gpkg
   ```

4. **Rodar os scripts** na ordem da Seção 3. Cada script é
   auto-suficiente; a saída de um alimenta a entrada do próximo via os
   caminhos `<pasta_numerada>/...` codificados.

5. **(Opcional) Rodar o pipeline BFAST**
   ```r
   source("scripts/bfast/bfast_analise.R")
   source("scripts/bfast/bfast_diagnostico_visual.R")
   ```
   Os parâmetros estão centralizados no objeto `PARAMS` em
   `bfast_analise.R`.

---

## 6. Dependências

- **R** ≥ 4.0
- Pacotes principais:
  `sf`, `terra`, `raster`, `tidyverse` (dplyr, tidyr, purrr, lubridate,
  ggplot2, stringr), `spatialEco`, `mapview`, `webshot2`, `openxlsx`,
  `dbscan`, `bfast` (≥ 1.6.0, recomendado 1.7.x), `cowplot`,
  `ggspatial`, `RColorBrewer`.

Instalação rápida:
```r
install.packages(c(
  "sf", "terra", "raster", "tidyverse", "spatialEco", "mapview",
  "webshot2", "openxlsx", "dbscan", "bfast", "cowplot", "ggspatial",
  "RColorBrewer"
))
```

---

## 7. Convenções

- **CRS de trabalho:** `EPSG:4674` (SIRGAS 2000 geográfico) para
  intercâmbio e visualização; `EPSG:31981` (SIRGAS 2000 / UTM 21S) para
  cálculos métricos (buffer, área, distância).
- **Ano-semestre:** representado como `ano + (semestre - 1)/2`, com
  semestre = 1 se mês ≤ 6, senão 2. Ex.: 2023-09 → `2023.5`.
- **Identificador único da pista:** coluna `id_pista` em todas as
  camadas a jusante de `process_base.R`.
- **Camadas de `base_pistas_final.gpkg`:** `pontos` (centroide + atributos)
  e `poligonos` (forma da pista). Quase todos os scripts pós-Etapa 3 leem
  a camada `pontos`.

---

## 8. Autoria

Trabalho de Graduação — Levi de Lima.
Repositório: <https://github.com/levi-de-lima/tg-pistas-pouso>
