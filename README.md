# TG - Pistas de Pouso

Projeto de an\u00e1lise de pistas de pouso clandestinas, combinando dados da ANAC, OSM,
MapBiomas, DETER, GFW (Global Forest Watch) e imagens Planet para identificar e
monitorar pistas em \u00e1reas de interesse.

## Estrutura do reposit\u00f3rio

```
.
\u251c\u2500\u2500 tg.Rproj              # Projeto RStudio
\u251c\u2500\u2500 scripts/              # Scripts R de an\u00e1lise
\u2502   \u251c\u2500\u2500 process_base.R         # Consolida\u00e7\u00e3o da base de pistas
\u2502   \u251c\u2500\u2500 estudo_pistas.R        # An\u00e1lise explorat\u00f3ria da base
\u2502   \u251c\u2500\u2500 pistas_legais.R        # Filtro de pistas legais (ANAC)
\u2502   \u251c\u2500\u2500 comparative.R          # An\u00e1lise comparativa DETER x Planet x GFW
\u2502   \u251c\u2500\u2500 best_alerts.R          # Ranking de alertas
\u2502   \u251c\u2500\u2500 test_mmu.R             # Testes de unidade m\u00ednima mape\u00e1vel
\u2502   \u251c\u2500\u2500 ts_C63L51.R            # S\u00e9rie temporal para tile C63L51
\u2502   \u251c\u2500\u2500 process_GFW.R          # Processamento de dados GFW
\u2502   \u251c\u2500\u2500 generate_graphs.R      # Gera\u00e7\u00e3o de gr\u00e1ficos
\u2502   \u2514\u2500\u2500 windrose_analyses.R    # An\u00e1lises com wind rose
\u251c\u2500\u2500 2_base_pistas/        # Base consolidada de pistas (shapefiles + xlsx)
\u2514\u2500\u2500 windrose_mock.jsx     # Mockup de componente wind rose
```

## Pastas n\u00e3o versionadas

As pastas abaixo cont\u00eam dados brutos e intermedi\u00e1rios muito pesados (> 14GB no
total) e n\u00e3o s\u00e3o versionadas. A estrutura esperada pelos scripts \u00e9:

- `1_fontes/` \u2014 dados fonte (ANAC, \u00e1rea de estudo, DETER, GFW, pistas)
- `3_planet_orders/` \u2014 pedidos de imagens Planet
- `4_analise_comparativa/` \u2014 cruzamentos Alert x Planet x DETER
- `5_base_final/` \u2014 base final consolidada + screenshots
- `6_gfw/` \u2014 rasters e vetoriza\u00e7\u00f5es do Global Forest Watch
- `7_exploratorio/` \u2014 an\u00e1lises explorat\u00f3rias
- `apresentacoes/` \u2014 PDFs e pptx de entregas

## Como reproduzir

1. Clonar o reposit\u00f3rio
2. Abrir `tg.Rproj` no RStudio
3. Popular as pastas de dados externas (n\u00e3o versionadas) com os arquivos fonte
4. Rodar os scripts em ordem (ver coment\u00e1rios em cada arquivo)

## Depend\u00eancias principais

- R (>= 4.0)
- Pacotes: `sf`, `tidyverse`, `mapview`, `spatialEco`, `terra`, `raster`
