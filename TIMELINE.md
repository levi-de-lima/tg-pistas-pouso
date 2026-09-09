# Linha do tempo do projeto

Reconstruída a partir das datas de modificação dos arquivos, do histórico do git
(4 commits) e da leitura dos scripts. Serve para separar o que é pipeline de
produção do que é ramo abandonado, e para localizar em que ponto cada resultado
foi gerado.

O README da raiz é de **14/05/2026** e descreve uma etapa BFAST que foi removida
do repositório em 07/07. Onde os dois divergirem, este arquivo é o mais recente.

---

## Fase 0 — Fontes (11/02 a 26/02)

| Data | O que |
|---|---|
| 11/02 | OSM / Geofabrik (corte dos dados do OpenStreetMap) |
| 19/02 14:09–14:11 | S1-AAD baixado: 1.040 imagens GeoTIFF, 1.040 PNG, 1.040 máscaras de segmentação, 1.040 anotações de bbox e 341 pares de change detection |
| 19/02 14:45 | MapBiomas `Pistas_de_Pouso_27_Mar_2023_v1.2` |
| 19/02 18:26 | `1_fontes/area_estudo` — definição dos 289 tiles (17 × 17) |
| 26/02 19:57 | Primeira camada de alertas (`SAD.gpkg`) |

## Fase 1 — Base de pistas (20/03 a 14/05)

| Data | O que |
|---|---|
| 20/03 | Início de `2_base_pistas` (`pistas.xlsx` e derivados) |
| 01/04 | Cadastro ANAC (`anac_consolidated.csv`) |
| 08/04 a 14/05 | 379 screenshots em `5_base_final/screenshots`, um por pista |
| 09/04 14:24–14:25 | `process_base.R` e `pistas_legais.R` |
| 14/05 12:38 | `estudo_pistas.R` |

Produto: `5_base_final/base_pistas_final.gpkg`, camadas `pontos` e `poligonos`.
379 pistas, 54 com registro ANAC e 325 sem, 82 com `start_date`, 63 com fim
observável e 124 com pelo menos uma data.

## Fase 2 — Benchmark dos alertas (26/02 a 09/04)

Nove sistemas comparados no tile C63L51 contra delineamento manual sobre o Planet.

| Data | O que |
|---|---|
| 26/02 a 09/04 | `4_analise_comparativa/Alerts` — 12 camadas preparadas |
| 09/04 14:02–14:12 | Saídas `Intersections`, `Alert-Planet`, `Planet-Alert` e as versões `non_acum` |
| 09/04 14:24–14:26 | `ts_C63L51.R`, `comparative.R`, `best_alerts.R` e `test_mmu.R` salvos numa janela de três minutos |

Resultado: GFW escolhido. Taxas calculadas a partir do `df_track.gpkg`, período
final (2025,0):

| sistema | omissão | comissão | soma |
|---|---|---|---|
| GFW | **34,5%** | 31,4% | 65,9 |
| GLAD-S2 | 40,5% | 24,2% | 64,8 |
| RADD | 41,7% | 23,6% | 65,3 |
| LUCA | 48,2% | 11,0% | **59,3** |
| PRODES | 49,8% | 12,3% | 62,2 |
| MapBiomas | 50,0% | 10,2% | 60,2 |
| TropiSCO | 52,9% | 11,7% | 64,7 |
| SAD | 61,4% | 8,8% | 70,2 |
| DETER | 68,4% | 19,8% | 88,1 |

O GFW tem a **menor omissão** com folga e a **maior comissão**. Pela soma dos dois
erros ele fica em sétimo de nove, e quem ganharia seria o LUCA. A escolha se
sustenta porque os dois erros não são simétricos: omissão não se recupera depois,
comissão se remove com máscara. É esse o papel da máscara do DETER na fase
seguinte.

O benchmark rodou sobre `4_analise_comparativa/Alerts/GWF_sel.gpkg`, o GFW cru
(1.540.911 feições, 02/01/2020 a 30/12/2024, sem filtro e sem máscara). A camada
de produção tem 11,2% desse volume e cobre 2019 a 2025. A decisão de projeto é
que o benchmark serve só para reduzir nove candidatos a um; tudo depois melhora o
sistema escolhido em vez de reabrir a escolha.

A referência do Planet não é acumulada, e não precisa ser: o delineamento manual
já sai cumulativo, porque na imagem se vê a cicatriz inteira. A série sobe de 206
para 761 ha com dois recuos de 10% e 3%, que são variação de interpretação.

## Fase 3 — Pipeline do GFW (25/03 a 22/04)

| Data | O que |
|---|---|
| 25/03 17:35 | `GWF_ALB.tiff` chega, vindo do repositório do Projeto Dedicado. BigTIFF, 302.129 × 235.105, uint16, 0,0001°, nodata 0 |
| 26/03 18:17 | `GWF_classified.tiff` — primeira tentativa |
| 09/04 14:16 | `GFW_area_de_estudo.tiff` — `clamp(30000, 45000)` + recorte |
| 15/04 14:03–14:47 | `generate_graphs.R` e `process_GFW.R` (v1, vetorização por semestre, descartada) |
| **22/04 14:53** | `GFW_filtered.tiff` — multiplicação pela máscara `sum_alerts` |
| **22/04 15:08** | `GFW_min_only.tiff` — máscara `Deter_non_min`, inverse |
| 22/04 15:13–15:42 | Vetorização no QGIS (`6_gfw/vectorize_gfw.qgz`): `GFW_vectorized.gpkg` → corrigir geometrias → `GFW_vectorized_fix.gpkg` |
| 22/04 17:26 | `GFW_final.gpkg` — 3.848.782 polígonos, 02/01/2019 a 06/12/2025 |
| 22/04 17:27 | `process_GFW_2.R` salvo |
| 22/04 19:31 | `GFW_centroide.gpkg` — centroides + área, 1.533,9 km² |
| 22/04 | **Commit inicial do repositório** (`5427bc4`) |

A primeira metade de `process_GFW_2.R` rodou no geolab (linha 54:
`setwd("~/pistas-de-pouso")`), o que explica o caminho
`~/grupos/projeto-dedicado/sum_alerts_re.tif`. Os intermediários
`GFW_crop.tiff`, `GFW_data_raster.tiff` e `sum_alerts_final.tiff` ficaram lá.

### Atrito medido nos rasters intermediários

Contagem de pixels válidos em amostra de 4.250 das 42.500 linhas. Os três
rasters compartilham a mesma grade (42.500 × 42.500, 0,0001°, EPSG:4326).

| Etapa | % da área de estudo | Área |
|---|---|---|
| GFW após `clamp`, só *high* e *highest* | 6,20% | 13.748 km² |
| Após filtro `sum_alerts` | 3,61% | 8.012 km² |
| Após máscara `Deter_non_min` | 0,69% | 1.537 km² |

O `sum_alerts` remove 41,7% e a máscara do DETER remove 80,8% do que sobrou.
Restam 11,2% dos alertas originais. Os 1.537 km² extrapolados batem com os
1.533,9 km² somados no `GFW_final_area.gpkg`, diferença de 0,2%, o que valida
a linhagem inteira do raster bruto até o vetor analisado.

A máscara `Deter_non_min.gpkg` é o dissolve de todas as classes do DETER que não
são mineração, recortadas na área de estudo: um MULTIPOLYGON com 2.990 partes
vindo de 31.748 polígonos, dos quais 15.874 são `DESMATAMENTO_CR`, 12.198
`CICATRIZ_DE_QUEIMADA`, 3.004 `DEGRADACAO`, 407 `DESMATAMENTO_VEG`, 253
`CS_DESORDENADO` e 12 `CS_GEOMETRICO`.

## Fase 4 — Windroses, kNN e DETER retroativo (24/04 a 14/05)

| Data | O que |
|---|---|
| 24/04 13:58–15:22 | `windrose_analyses.R` e `6_gfw/images`: 15 pistas × 3 variantes (`_data`, `_area`, `_id`) = 45 PNGs. É a amostra de calibração do raio |
| 29/04 14:57–20:05 | `6_gfw/graphs` e `6_gfw/all_windroses`, 372 pistas cada. Primeira rodada em toda a base |
| 06/05 | `Deter_before` e `deter_orignal` baixados |
| 08/05 a 14/05 | `6_gfw/all_wind_2` e `6_gfw/compound_graphs`, 379 pistas cada. Segunda rodada, já com a base final |
| 13/05 19:17 | `GFW_dist.gpkg` — kNN das 7 pistas mais próximas de cada detecção |
| 13/05 19:23 | `prepare_prodes.R` e `deter_dist.gpkg` — DETER de mineração 2016–2019, diferenciado ano a ano |
| 14/05 13:25 | README |
| 14/05 | **Commit `bb866f2`**, "Add pipeline BFAST + windroses" |

A amostra de calibração tem **15** pistas, não 10 como dizem os slides. Os ids
estão em `all_windroses.R` linha 40: 11, 12, 13, 25, 176, 192, 196, 2350, 2406,
2407, 2432, 2463, 2546, 2550, 72262. O critério de escolha está nos comentários
das linhas 31 a 38: incluir as quatro do tile C63L51 e depois cobrir região com
pouca mineração, região com muita mineração, alta densidade de pistas vizinhas e
variedade de datas de início, fim e inoperação.

## Fase 5 — Resultados, o núcleo fechado (21/05 a 28/05)

| Data | O que |
|---|---|
| 21/05 14:28 | `precipitacao_tile_C51L41_2017_2026.csv` |
| 21/05 18:43 | Scatter de início e fim, K=1 e K=4 |
| 22/05 19:03 | Histogramas de razão de início e fim, K=1 e K=4 |
| 27/05 15:03–15:10 | `9_resultados/graficos`: 124 curvas cumulativas, uma por pista com data |
| 27/05 16:48–18:32 | `9_resultados/histogramas`: 124 histogramas ±12 meses, mais `resumo_K4`, `media_antes`, `media_depois`, `boxplot_antes_depois`, `hist_diffs`, `density_antes_depois` |
| 27/05 18:53–19:29 | `histogramas/gerais_pista`: `density_datas`, `area_total_mes`, `area_total_pistas`, `area_precipitacao`, `area_pistas_precip` |
| 28/05 17:31 | `resultados.R` salvo |

**É aqui que o núcleo do trabalho fecha**, com o teste de Wilcoxon pareado
comparando a área média mensal minerada nos 12 meses antes e nos 12 meses depois
da `start_date`, em K=4.

Os 124 gráficos de 27/05 correspondem exatamente às 124 pistas com pelo menos uma
data na base atual. A base foi reescrita em 09/06, mas as contagens que importam
(379 pistas, 82 com início, 63 com fim, 124 com alguma data) são idênticas às da
`base_pistas_final_antiga.gpkg` de 13/05, e os 124 ids batem com as duas versões.
Ou seja, a reescrita de 09/06 não afetou os resultados.

## Fase 6 — Exploratório pós-fechamento (28/05 a 09/06)

Tudo desta fase veio depois do núcleo estar fechado.

**Ramo `ALB_DETL`, abandonado.** De 28/05 17:49 a 03/06 16:15: `ALB_DETL.tif`,
`ALB_DETL_cropped.tif`, `mask_classes.tif`, `mask_gfw.gpkg`, `mask_union_gfw.gpkg`,
`mask_binnary.tif`, `mask_valid_gfw.gpkg`, `Mining_Masked_GFWclass.gpkg`,
`mask_only_miner_gfw.gpkg` e o script `mask_gfw.R`. Foi uma tentativa de aplicar
mais uma máscara de classes sobre o `GFW_final_area.gpkg`, comparar com o que já
existia e ver se ficava melhor. O `mask_gfw.R` nem chega a escrever o resultado.
Cronologicamente é impossível que tenha entrado na análise: o `GFW_dist.gpkg` é
de 13/05.

**Grupo de controle.** De 03/06 17:34 a 19:15: `deter_orig.gpkg`,
`grupo_controle.R`, `analise_grupo_controle.R` e `area_controle.png`. Mineração
fora do buffer de 6 km de qualquer pista, a partir de DETER, MapBiomas e GFW.

**Últimos ajustes.** 08/06 `tg.Rproj`; 09/06 01:14 `exploratorio.R`; 09/06 02:04
`.RData` e `.Rhistory`, a última sessão de R do projeto; 09/06 02:08
`base_pistas_final.gpkg` reescrito.

## Fase 7 — Depois (07/07 em diante)

| Data | O que |
|---|---|
| 07/07 | **Commit `f06e237`**, "Adiciona resultados, scripts de grupo de controle e máscara GFW; remove módulo bfast" |
| 16/07 | `1_fontes/hidrografia` atualizada |
| 19/08 | `ecorregioes.qgz` — ecorregiões, PRODES `v20260717`, Amazônia Legal. Ramo novo, ainda não integrado |
| 26/08 | `deter_tiles_ALB.gpkg` atualizado |

---

## Estado atual

**Fechado e usado no artigo**

- Base de pistas: 379 pistas, indexação temporal no Planet, cruzamento com ANAC.
- Benchmark dos 9 alertas no tile C63L51, com MMU e omissão/comissão.
- Pipeline do GFW: decodificação, filtro `sum_alerts`, máscara `Deter_non_min`,
  vetorização.
- DETER retroativo 2016–2019 estendendo a série para trás.
- kNN das 7 pistas mais próximas, raio de 6 km, atribuição K=1 e K=4.
- Séries mensais por pista e teste de Wilcoxon pareado antes/depois.

**Em construção**

- Grupo de controle. A linha 101 do `grupo_controle.R` lê
  `mask_only_miner_gfw.gpkg`, que é a máscara do ramo abandonado e não tem coluna
  `doy`, por isso as 52.524 feições `fonte = "gfw"` do `final_controle.gpkg` estão
  com data nula. A correção é apontar para `6_gfw/GFW_final_area.gpkg`. Falta
  também definir a estatística que compara pistas contra controle.

**Abandonado**

- Ramo `ALB_DETL` (28/05 a 03/06).
- `process_GFW.R`, versão 1 da vetorização por semestre (15/04).
- `exploratorio.R` linhas 4 a 6: leem `Mining_Masked_GFWclass.gpkg` mas a linha 9
  sobrescreve com `GFW_centroide.gpkg`, e a linha 5 tem um `st_centroid()` sem
  argumento que nem roda. Editado em 09/06 e nunca executado.
- BFAST. Existiu em `scripts/bfast/` entre 14/05 e 07/07, com `bfast_funcoes.R`,
  `bfast_analise.R`, `bfast_diagnostico_visual.R` e um README próprio, usando
  `bfastlite()` para estimar quebras estruturais e classificar cada pista em
  `fase_completa`, `ativa_em_curso`, `ativa_sem_quebras`, `sem_atividade`,
  `atividade_muito_curta` ou `poucas_deteccoes`. Substituído pelo detector
  heurístico do `resultados.R` e removido no commit de 07/07. Recuperável com
  `git show bb866f2:scripts/bfast/bfast_analise.R`.

## A MMU não entrou na camada de produção

Confirmado por contagem de feições. A vetorização produz 3.848.782 polígonos e
esse número não muda em nenhum passo seguinte:

| arquivo | data | feições |
|---|---|---|
| `GFW_vectorized.gpkg` | 22/04 15:13 | 3.848.782 |
| `GFW_vectorized_fix.gpkg` | 22/04 15:42 | 3.848.782 |
| `GFW_final.gpkg` | 22/04 17:26 | 3.848.782 |
| `GFW_centroide.gpkg` | 22/04 19:31 | 3.848.782 |
| `GFW_dist.gpkg` | 13/05 19:17 | 3.848.782 |
| `GFW_final_area.gpkg` | 29/05 12:58 | 3.848.782 |

A MMU usa `st_filter`, que reduziria a contagem. Não houve nenhuma etapa de
filtragem. Os artefatos de MMU que existem no repositório, `GFW_mmu_c_buffer.gpkg`
com 34.813 feições e `GFW_mask_mmu.gpkg` com 86.524, são de **15/04**, uma semana
antes da corrida de produção, e pertencem ao `process_GFW.R` (v1, abandonado).

A MMU portanto vive em dois lugares: no benchmark, aplicada aos nove sistemas
para torná-los comparáveis, e na v1 abandonada. Não na camada analisada.

## O `sum_alerts` não é a extensão pré-2019

O filtro é uma multiplicação por máscara binária, e multiplicação só remove, nunca
adiciona. Medido nos rasters: o período é **idêntico** antes e depois, 02/01/2019
até o fim de 2025. Ele não toca na cobertura temporal.

A extensão para antes de 2019 é outra coisa, e é vetorial: `prepare_prodes.R`
gera o `deter_dist.gpkg` com o DETER de mineração 2016–2019, em 13/05, três
semanas depois. O `resultados.R` linha 44 lê esse arquivo e empilha com o GFW.

O que o `sum_alerts` faz é filtrar espacialmente, e o efeito se concentra na
classe de confiança mais fraca: mantém 87,1% dos pixels *highest confidence* e só
28,1% dos *high confidence*. A composição da camada passa de 48,8% / 51,2% para
23,5% / 76,5%.

A leitura mais provável é **concordância sobre distúrbio**: o raster conta quantos
sistemas detectaram distúrbio em cada pixel, e manter 3 a 6 exige corroboração de
pelo menos três. Isso explica o alinhamento com a classe de confiança do próprio
GFW, que já é definida por concordância entre os sistemas que o compõem.

A leitura alternativa, concordância sobre **mineração**, não fecha
quantitativamente: sobrariam 8.012 km² com três ou mais sistemas classificando
como mineração, e a máscara do DETER logo em seguida derruba 80,8% disso. Três
sistemas errando sobre 6.475 km² é implausível.

Consequência para o artigo: a camada analisada **não é GFW puro**, é o subconjunto
de alertas do GFW corroborado por pelo menos dois outros sistemas. Isso é um
critério de detecção mais forte do que qualquer produto isolado, e é mais uma
razão pela qual as taxas do benchmark não descrevem a série final.

Falta só saber **quais** sistemas estão somados.

## Pontos em aberto para o artigo

1. O que a banda do `sum_alerts_re.tif` conta e quais sistemas estão somados.
   O filtro corta 41,7% dos alertas, então precisa estar documentado. É o único
   ponto da metodologia que ainda não dá para escrever.
2. Qual versão ou data de corte do integrated alerts é a cópia do `GWF_ALB.tiff`
   no Projeto Dedicado.
3. O critério objetivo que fixou o raio em 6 km. A amostra e os critérios de
   escolha das 15 pistas estão documentados nos comentários do `all_windroses.R`,
   mas não o que no windrose marcou essa distância.
