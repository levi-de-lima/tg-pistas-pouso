# TG - Pistas de Pouso

Projeto de análise de pistas de pouso clandestinas, combinando dados da ANAC, OSM,
MapBiomas, DETER, GFW (Global Forest Watch) e imagens Planet para identificar e
monitorar pistas em áreas de interesse.

## Estrutura do repositório

```
.
├── tg.Rproj              # Projeto RStudio
├── scripts/              # Scripts R de análise
│   ├── process_base.R         # Consolidação da base de pistas
│   ├── estudo_pistas.R        # Análise exploratória da base
│   ├── pistas_legais.R        # Filtro de pistas legais (ANAC)
│   ├── comparative.R          # Análise comparativa DETER x Planet x GFW
│   ├── best_alerts.R          # Ranking de alertas
│   ├── test_mmu.R             # Testes de unidade mínima mapeável
│   ├── ts_C63L51.R            # Série temporal para tile C63L51
│   ├── process_GFW.R          # Processamento de dados GFW
│   ├── generate_graphs.R      # Geração de gráficos
│   └── windrose_analyses.R    # Análises com wind rose
├── 2_base_pistas/        # Base consolidada de pistas (shapefiles + xlsx)
└── windrose_mock.jsx     # Mockup de componente wind rose
```

## Pastas não versionadas

As pastas abaixo contêm dados brutos e intermediários muito pesados (> 14GB no
total) e não são versionadas. A estrutura esperada pelos scripts é:

- `1_fontes/` — dados fonte (ANAC, área de estudo, DETER, GFW, pistas)
- `3_planet_orders/` — pedidos de imagens Planet
- `4_analise_comparativa/` — cruzamentos Alert x Planet x DETER
- `5_base_final/` — base final consolidada + screenshots
- `6_gfw/` — rasters e vetorizações do Global Forest Watch
- `7_exploratorio/` — análises exploratórias
- `apresentacoes/` — PDFs e pptx de entregas

## Como reproduzir

1. Clonar o repositório
2. Abrir `tg.Rproj` no RStudio
3. Popular as pastas de dados externas (não versionadas) com os arquivos fonte
4. Rodar os scripts em ordem (ver comentários em cada arquivo)

## Dependências principais

- R (>= 4.0)
- Pacotes: `sf`, `tidyverse`, `mapview`, `spatialEco`, `terra`, `raster`
