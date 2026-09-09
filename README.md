# Pistas de pouso e mineração artesanal na Amazônia Legal Brasileira

Trabalho de Graduação sobre a relação espaço-temporal entre o surgimento de
pistas de pouso e a atividade de garimpo na Amazônia Legal Brasileira, medida
por sistemas de alerta de distúrbio florestal.

A pergunta é de ordem temporal. A proximidade entre pistas de pouso e garimpo
já está documentada na literatura, mas proximidade é um retrato: não diz se a
pista precede a frente de mineração, por quanto tempo, nem se a taxa de
mineração no entorno muda depois que a pista aparece. Responder isso exige
pistas datadas uma a uma e uma série de mineração com resolução mensal.

## O que o projeto produz

- Um inventário de **379 pistas de pouso** na área de maior concentração de
  garimpo da Amazônia Legal, consolidado de seis fontes, cruzado com o cadastro
  da ANAC e datado por inspeção visual do acervo Planet.
- A comparação de **nove sistemas de alerta** de distúrbio florestal contra
  delineamento manual de mineração, com taxas de omissão e comissão.
- Uma série mensal de **área minerada no entorno de cada pista**, de agosto de
  2016 a novembro de 2025.
- Um teste pareado que compara a mineração nos doze meses anteriores e nos doze
  posteriores ao surgimento de cada pista.

## Estrutura

```
R/                     pipeline, em quatro etapas numeradas
  1-inventario-pistas/ consolidação das fontes, ANAC, base final datada
  2-selecao-alerta/    referência Planet, comparação dos 9 alertas, MMU
  3-serie-mineracao/   processamento do GFW, DETER retroativo
  4-analise/           kNN, windroses, teste antes/depois, grupo de controle

2_base_pistas/         base consolidada de pistas (versionada)
9_resultados/          figuras e tabelas de resultado (versionadas)
artigo/                manuscrito em LaTeX
_arquivo/              ramos abandonados, fora do controle de versão
TIMELINE.md            cronologia do projeto em sete fases
REORGANIZACAO.md       diagnóstico do repositório e plano de migração
```

As fontes públicas e as saídas intermediárias do pipeline **não estão
versionadas**: somam mais de 20 GB e são, respectivamente, baixáveis e
regeneráveis. Ver a seção Fontes de dados.

## O pipeline, etapa por etapa

Os caminhos nos scripts são relativos à raiz do projeto. Abra o `tg.Rproj` no
RStudio, que define o diretório de trabalho corretamente.

### Etapa 1 — Inventário de pistas

| script | faz |
|---|---|
| `01_consolida_fontes.R` | junta as seis fontes, agrupa duplicatas por buffer de 200 m e reduz cada aglomerado a um centroide |
| `02_cruza_anac.R` | intersecta com o cadastro da ANAC (buffer de 550 m) e marca a situação de registro |
| `03_base_final.R` | junta a planilha mestra de datas, calcula ano-semestre, gera um screenshot por pista e escreve a base final |

Produto: `5_base_final/base_pistas_final.gpkg`, camadas `pontos` e `poligonos`.
379 pistas, 54 registradas na ANAC e 325 não, 82 com data de início observável.

### Etapa 2 — Seleção do sistema de alerta

| script | faz |
|---|---|
| `01_referencia_planet.R` | monta a série do delineamento manual de mineração no tile C63L51 |
| `02_compara_alertas.R` | aplica a MMU aos nove alertas, acumula por semestre e calcula interseção, omissão e comissão |
| `03_omissao_comissao.R` | reporta as taxas por sistema e por semestre |
| `04_calibra_mmu.R` | testa o limiar da unidade mínima mapeável isoladamente |

Resultado: o **GFW integrated alerts** foi escolhido por ter a menor omissão
das nove, 34,5%. Sua comissão é a maior, 31,4%, e é removida na etapa seguinte.
O critério é assimétrico de propósito: mineração que o alerta nunca marcou não
se recupera; distúrbio marcado a mais sai com máscara.

### Etapa 3 — Série de mineração

| script | faz |
|---|---|
| `01_processa_gfw.R` | decodifica o raster do GFW, aplica a máscara de concordância e a máscara de não-mineração do DETER, vetoriza |
| `02_deter_retroativo.R` | diferencia o DETER de mineração ano a ano para estender a série de 2016 a 2018 |

As duas máscaras deixam 11,2% dos alertas originais: 13.748 km² caem para
8.012 km² após a máscara de concordância e para 1.537 km² após a do DETER.
Produto final: 3.848.782 polígonos datados somando 1.533,9 km².

A primeira metade do `01_processa_gfw.R` rodou no ambiente do geolab, o que
explica os caminhos sem pasta e a chamada a `setwd()` no meio do script.

### Etapa 4 — Atribuição e análise

| script | faz |
|---|---|
| `01_knn_pistas.R` | encontra as 7 pistas mais próximas de cada detecção e suas distâncias |
| `02_windroses.R` | gráficos polares por pista, usados para calibrar o raio de influência em 6 km |
| `03_teste_antes_depois.R` | série mensal por pista e teste de Wilcoxon pareado ancorado na data observada no Planet |
| `04_grupo_controle.R` | mineração fora do buffer de 6 km de qualquer pista, como contrafactual |
| `05_analise_controle.R` | agrega a série do grupo de controle |
| `06_graficos_compostos.R` | curvas cumulativas combinadas com as windroses |

A atribuição usa duas regras. Em **K = 1** cada detecção conta para uma pista
só, a mais próxima. Em **K = 4** conta para até quatro. K = 1 é a regra
reportada; K = 4 entra como verificação de robustez.

## Fontes de dados

Nenhuma é versionada aqui. Todas são públicas, exceto as imagens Planet.

| fonte | uso |
|---|---|
| DETER (INPE) | alertas de mineração 2016–2018 e máscara de não-mineração |
| PRODES (INPE) | estado inicial do acúmulo no benchmark |
| GFW integrated alerts | série principal de mineração, 2019–2025 |
| MapBiomas Alerta | benchmark e grupo de controle |
| MapBiomas Airstrips Mapping Data | fonte de pistas |
| S1-AAD (Mendeley Data) | fonte de pistas em SAR |
| OpenStreetMap (Geofabrik) | fonte de pistas |
| IBGE | fonte de pistas |
| ANAC | cadastro de aeródromos, situação de registro |
| Planet, via Programa Brasil MAIS | indexação temporal e delineamento manual |
| GLAD-S2, LUCA, RADD, SAD, TropiSCO | benchmark de alertas |

## Convenções

- **CRS:** SIRGAS 2000 geográfico (EPSG:4674) para armazenamento e visualização;
  SIRGAS 2000 / UTM 21S (EPSG:31981) para toda conta métrica.
- **Ano-semestre:** `ano + (semestre - 1)/2`, com semestre 1 até junho. O
  segundo semestre de 2023 é 2023.5.
- **Identificador da pista:** `id_pista`, estável em todas as camadas a jusante
  da Etapa 1.
- **Janela de análise:** agosto de 2016 a novembro de 2025.

## Dependências

R ≥ 4.0 e os pacotes `sf`, `terra`, `tidyverse`, `dbscan`, `spatialEco`,
`mapview`, `webshot2`, `openxlsx`, `cowplot`, `ggspatial`, `RColorBrewer`.

```r
install.packages(c("sf","terra","tidyverse","dbscan","spatialEco","mapview",
                   "webshot2","openxlsx","cowplot","ggspatial","RColorBrewer"))
```

## Limitações conhecidas

- A máscara de não-mineração do DETER remove 80,8% dos alertas que sobraram da
  etapa anterior. Um terço dela é cicatriz de queimada, então mineração aberta
  sobre área queimada ou degradada sai junto. É uma fonte de omissão que o
  pipeline não corrige.
- As taxas de omissão e comissão da Etapa 2 descrevem o GFW cru. A camada
  efetivamente usada carrega dois filtros a mais e não foi remedida.
- A unidade mínima mapeável pertence à comparação entre alertas e não foi
  aplicada à camada de produção.
- Pistas a poucos quilômetros uma da outra compartilham detecções, então as
  pistas não são observações independentes no teste pareado.
- O desenho estabelece mudança de regime coincidente com o surgimento da pista,
  não mecanismo.

Um detector automático de início da fase mineradora foi construído e
descartado: discordou das datas observadas por mediana de 5,5 meses, com desvio
de 19 meses, acertando dentro de um trimestre em apenas 16% das pistas.

## Licença e citação

Código sob MIT, dados e texto sob CC BY 4.0. Ver `LICENSE`.

Para citar, ver `CITATION.cff`.

## Autoria

Levi de Lima. Trabalho de Graduação, 2026.
