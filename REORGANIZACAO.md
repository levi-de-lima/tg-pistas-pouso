# Plano de reorganização do repositório

Diagnóstico medido em 09/09/2026 e plano de migração em quatro fases.
Decisões já tomadas: um repositório com pastas por etapa, ramos abandonados
movidos para `_arquivo/`, dados originais publicados no Zenodo com DOI, e o
repositório fora do OneDrive.

---

## 1. Diagnóstico

**33,3 GB no total**, dos quais o material insubstituível soma **cerca de 55 MB**.

| bloco | tamanho | natureza |
|---|---|---|
| `1_fontes/` | 10.627 MB | público, baixável de novo |
| ramo v1 abandonado | 8.084 MB | descartável |
| saídas regeneráveis do pipeline | 8.686 MB | o script refaz |
| ramo `ALB_DETL` abandonado | 3.158 MB | descartável |
| duplicatas | 1.813 MB | descartável |
| lixo de sessão R e locks | 480 MB | descartável |
| resultados e gráficos | 503 MB | original |
| screenshots das pistas | 478 MB | original, subproduto de revisão |
| apresentações | 59 MB | original |
| tabela de taxas do benchmark | 25 MB | original (`df_track.gpkg`) |
| resultados PNG versionados | 22 MB | original |
| base de pistas | 6,4 MB | **o ativo científico do trabalho** |
| delineamento manual do Planet | 0,5 MB | **a verdade de campo** |
| scripts e texto | 0,4 MB | original |

Dentro de `1_fontes/`, a hidrografia sozinha ocupa 5.083 MB e o DETER 2.640 MB,
os dois baixáveis. Dentro de `3_planet_orders/`, os 249 MB são quase inteiramente
um `zip_gfw.zip` de 247 MB que não pertence àquela pasta; o delineamento manual em
si tem 0,5 MB.

**13,1 GB saem sem perda nenhuma**: ramos abandonados, duplicatas e lixo de sessão.

O git está saudável: 20 MB de histórico, 313 arquivos rastreados, 29,3 MB. Nenhum
blob grande foi commitado, então não há necessidade de reescrever histórico.

---

## 2. Estrutura proposta

O problema que ela resolve é o que você descreveu: qual script gera o quê, e onde
estão os arquivos úteis. Código separado por etapa numa árvore, dados numa árvore
só, separados por durabilidade, resultados numa terceira.

```
tg/
├── README.md                  ← o mapa: etapa, script, entrada, saída
├── TIMELINE.md                ← a cronologia do projeto
├── tg.Rproj
├── .gitignore
│
├── R/
│   ├── 0-comum/
│   │   └── caminhos.R         ← constantes de caminho e CRS, usado por todos
│   ├── 1-inventario-pistas/
│   │   ├── 01_consolida_fontes.R
│   │   ├── 02_cruza_anac.R
│   │   └── 03_base_final.R
│   ├── 2-selecao-alerta/
│   │   ├── 01_referencia_planet.R
│   │   ├── 02_compara_alertas.R
│   │   ├── 03_omissao_comissao.R
│   │   └── 04_calibra_mmu.R
│   ├── 3-serie-mineracao/
│   │   ├── 01_processa_gfw.R
│   │   └── 02_deter_retroativo.R
│   └── 4-analise/
│       ├── 01_knn_pistas.R
│       ├── 02_windroses.R
│       ├── 03_teste_antes_depois.R
│       ├── 04_grupo_controle.R
│       └── 05_graficos_compostos.R
│
├── dados/
│   ├── MANIFEST.md            ← VERSIONADO: de onde baixar cada fonte
│   ├── brutos/                ← ignorado: fontes públicas
│   ├── mestres/               ← VERSIONADO: pequeno e insubstituível
│   │   ├── pistas.xlsx
│   │   ├── base_pistas_final.gpkg
│   │   ├── planet_C63L51.gpkg
│   │   └── area_estudo/
│   └── derivados/             ← ignorado: o pipeline refaz
│
├── resultados/
│   ├── tabelas/               ← VERSIONADO: csv e gpkg pequenos
│   └── figuras/               ← VERSIONADO: os PNG que entram no artigo
│
├── artigo/
│   ├── main.tex
│   ├── refs.bib
│   └── figuras/
│
└── _arquivo/                  ← ignorado: ramos abandonados, nada apagado
    ├── ramo-v1/
    ├── ramo-alb-detl/
    ├── duplicatas/
    └── scripts/
```

Três regras que sustentam a estrutura:

**`dados/mestres/` só recebe o que não dá para refazer.** Se um arquivo sai de um
script rodando, ele vive em `derivados/` e não é versionado. Se sai de um download,
vive em `brutos/` e o `MANIFEST.md` diz de onde. Se saiu do seu olho na imagem, é
mestre e vai para o git.

**Todo script é numerado dentro da sua etapa.** A ordem de execução deixa de
depender de memória ou de README.

**Nenhum caminho é escrito à mão nos scripts.** Todos passam pelo `caminhos.R`, que
define a raiz de cada árvore e os dois CRS. Trocar um diretório passa a ser uma
linha em um arquivo, não busca e substituição em vinte.

---

## 3. Mapa de migração dos scripts

| hoje | vira | observação |
|---|---|---|
| `process_base.R` | `R/1-inventario-pistas/01_consolida_fontes.R` | |
| `pistas_legais.R` | `R/1-inventario-pistas/02_cruza_anac.R` | |
| `estudo_pistas.R` | `R/1-inventario-pistas/03_base_final.R` | |
| `ts_C63L51.R` | `R/2-selecao-alerta/01_referencia_planet.R` | |
| `comparative.R` | `R/2-selecao-alerta/02_compara_alertas.R` | |
| `best_alerts.R` | `R/2-selecao-alerta/03_omissao_comissao.R` | |
| `test_mmu.R` | `R/2-selecao-alerta/04_calibra_mmu.R` | |
| `process_GFW_2.R` | `R/3-serie-mineracao/01_processa_gfw.R` | primeira metade roda no geolab |
| `prepare_prodes.R` | `R/3-serie-mineracao/02_deter_retroativo.R` | |
| `exploratorio.R` | `R/4-analise/01_knn_pistas.R` | tirar as linhas 4 a 6, código morto |
| `all_windroses.R` | `R/4-analise/02_windroses.R` | tirar as linhas 21 a 29, ramo v1 |
| `resultados_novo.R` | `R/4-analise/03_teste_antes_depois.R` | |
| `grupo_controle.R` | `R/4-analise/04_grupo_controle.R` | corrigir a linha 101 |
| `generate_graphs.R` | `R/4-analise/05_graficos_compostos.R` | |
| `process_GFW.R` | `_arquivo/scripts/` | v1 abandonada |
| `mask_gfw.R` | `_arquivo/scripts/` | ramo `ALB_DETL` |
| `windrose_analyses.R` | `_arquivo/scripts/` | superado pelo `all_windroses.R` |
| `generate_graphs2.R` | `_arquivo/scripts/` | duplica o `best_alerts.R` |
| `resultados.R` | `_arquivo/scripts/` | substituído pelo `resultados_novo.R` |
| `analise_grupo_controle.R` | fundir no `04_grupo_controle.R` | hoje só gera um gráfico |

## 4. Mapa de migração dos dados

**Para `dados/mestres/`, versionado:**

| hoje | vira |
|---|---|
| `2_base_pistas/pistas.xlsx` | `dados/mestres/pistas.xlsx` |
| `5_base_final/base_pistas_final.gpkg` | `dados/mestres/base_pistas_final.gpkg` |
| `3_planet_orders/temporal_series_C63L51/` | `dados/mestres/planet_C63L51/` |
| `3_planet_orders/temp_series_dissolved.gpkg` | `dados/mestres/planet_C63L51.gpkg` |
| `3_planet_orders/pistas_geometria/`, `adicionais/`, `aois_*` | `dados/mestres/aois_planet/` |
| `1_fontes/area_estudo/` | `dados/mestres/area_estudo/` |
| `1_fontes/anac/anac_consolidated.csv` | `dados/mestres/anac_consolidated.csv` |

**Para `resultados/`, versionado:**

| hoje | vira |
|---|---|
| `4_analise_comparativa/df_track.gpkg` | `resultados/tabelas/df_track.gpkg` |
| `9_resultados/*.png` e subpastas | `resultados/figuras/` |
| `6_gfw/all_wind_2/`, `compound_graphs/` | `resultados/figuras/windroses/`, `compostos/` |

**Para `dados/brutos/`, ignorado, com MANIFEST:** todo o resto de `1_fontes/`
(DETER, GFW, MapBiomas, hidrografia, pistas de terceiros) e
`4_analise_comparativa/Alerts/`.

**Para `dados/derivados/`, ignorado:** `6_gfw/GFW_*.gpkg` e `.tiff` da cadeia viva,
`7_alertas_before/`, as saídas de intersecção do `4_analise_comparativa/`,
`5_base_final/grupo_controle/`, `5_base_final/curso_dagua.gpkg` e hidrografia
recortada.

**Para `_arquivo/`, ignorado:**

- `ramo-v1/`: `6_gfw/GWF_vetorizado_explodido.gpkg`, `GFW_binded_exploded.gpkg`,
  `GFW_mask_mmu.gpkg`, `GFW_mmu_c_buffer.gpkg`, `tentativa.gpkg`,
  `GWF_classified.tiff`, `GFW_non_min_fixed.gpkg`
- `ramo-alb-detl/`: `ALB_DETL.tif`, `ALB_DETL_cropped.tif`, `mask_classes.tif`,
  `mask_binnary.tif`, `mask_gfw.gpkg`, `mask_union_gfw.gpkg`,
  `mask_valid_gfw.gpkg`, `Mining_Masked_GFWclass.gpkg`, `mask_only_miner_gfw.gpkg`
- `duplicatas/`: `6_gfw/GFW_centroides.gpkg`, `6_gfw/GFW_vectorized.gpkg`
- solto: `.RDataTmp`, `3_planet_orders/zip_gfw.zip`,
  `4_analise_comparativa/Deter_noOverlap_tiledQGIS.gpkg`, `8_exploratorio/`

**Screenshots.** Os 379 PNG somam 478 MB. São subproduto de revisão, não resultado.
Comprimir para JPEG de qualidade 85 derruba isso para algo entre 60 e 90 MB sem
perda de utilidade, e aí caberia em `resultados/` versionado. Enquanto isso não for
feito, ficam em `dados/derivados/screenshots/`, ignorados.

---

## 5. O novo `.gitignore`

```gitignore
# Sessão R e IDE
.Rhistory
.RData
.RDataTmp
.Rproj.user/
.Renviron

# Locks do Office e do sistema
~$*
desktop.ini
.DS_Store
Thumbs.db

# Dados: só mestres entram no git
dados/brutos/*
!dados/brutos/.gitkeep
dados/derivados/*
!dados/derivados/.gitkeep

# Ramos abandonados
_arquivo/

# Journals de GeoPackage
*.gpkg-journal
*.gpkg-shm
*.gpkg-wal

# LaTeX
artigo/*.aux
artigo/*.log
artigo/*.out
artigo/*.bbl
artigo/*.blg
artigo/*.toc

# Rasters e comprimidos nunca vão para o git
*.tif
*.tiff
*.img
*.zip
*.7z
*.rar
*.tar.gz
```

A inversão em relação ao `.gitignore` atual é importante: hoje ele lista o que
excluir, e cada arquivo novo grande é um risco de commit acidental. O novo bloqueia
`dados/brutos/` e `dados/derivados/` por inteiro e libera só o que você escolher.
Fica impossível commitar 900 MB sem querer.

---

## 6. As quatro fases

Cada fase é independente e reversível. Não pule a fase 0.

### Fase 0 — rede de segurança

```bash
cd "C:/Users/levid/OneDrive/Desktop/GitHub/tg"
git add -A
git commit -m "Estado antes da reorganizacao"
git tag pre-reorg
git push origin main --tags
```

Se algo der errado em qualquer fase seguinte, `git checkout pre-reorg` volta o
código. Os dados grandes não estão no git, então para eles a rede é o `_arquivo/`,
que não apaga nada.

### Fase 1 — sair do OneDrive

Essa você precisa fazer, porque eu não tenho acesso fora da pasta conectada.

```powershell
# feche o RStudio e o QGIS antes
mkdir C:\Users\levid\GitHub
robocopy "C:\Users\levid\OneDrive\Desktop\GitHub\tg" "C:\Users\levid\GitHub\tg" /E /MOVE
```

Depois abra o `tg.Rproj` no novo caminho e confirme que o `git status` responde.
Se quiser manter backup em nuvem dos dados pesados, o caminho é o contrário do
atual: o repositório fora do OneDrive, e `dados/brutos/` como link simbólico para
uma pasta dentro do OneDrive.

O motivo não é preferência. O OneDrive sincroniza arquivos do `.git` no meio da
escrita, o que corrompe o índice, e hoje ele está subindo e descendo 33 GB de forma
contínua.

### Fase 2 — mover o abandonado para `_arquivo/`

Não quebra nada, porque nenhum script vivo lê esses arquivos. A única exceção é o
`grupo_controle.R` linha 101, que lê `mask_only_miner_gfw.gpkg`, e essa linha já
precisa ser corrigida de qualquer forma para apontar ao `GFW_final_area.gpkg`.

Ganho imediato: 13,1 GB fora da vista e fora do sync.

### Fase 3 — reorganizar código e dados

Aqui os caminhos quebram, e é por isso que vem por último. A ordem que reduz o
risco: criar o `R/0-comum/caminhos.R` primeiro, mover os scripts, trocar os
caminhos literais pelas constantes, e só então mover os dados. Rodar cada etapa uma
vez depois de mexer nela, em vez de mexer em tudo e testar no fim.

---

## 7. Zenodo e a seção de disponibilidade de dados

O Zenodo integra com o GitHub: você autoriza o repositório, cria uma release com
tag, e ele arquiva o estado daquela tag e emite um DOI. Cada release nova ganha um
DOI próprio e existe um DOI guarda-chuva que sempre aponta para a versão mais
recente. É esse o DOI que vai no artigo.

Publicar dois registros, não um:

**Registro 1, o código.** A release do repositório, via integração automática. Cita
o pipeline.

**Registro 2, os dados originais.** Upload manual de um pacote pequeno, e é o que
tem valor de reuso independente:

- `base_pistas_final.gpkg`, as 379 pistas com datas, situação ANAC e proveniência
- `pistas.xlsx`, a planilha mestra com as três datas por pista
- `planet_C63L51`, o delineamento manual da mineração no tile de referência
- `df_track.gpkg`, as taxas de omissão e comissão dos nove sistemas
- um `README.md` com dicionário de dados, CRS, período coberto e limitações

Tudo isso somado fica abaixo de 35 MB. É o ativo mais original do trabalho e é o que
outro pesquisador vai querer usar. Uma base de 379 pistas de pouso datadas
individualmente sobre imagem Planet não existe publicada em nenhum outro lugar, e as
duas referências que o artigo usa para contagem de pistas, a do MapBiomas e a do
Intercept, não trazem data por pista.

Licença sugerida: CC-BY 4.0 nos dados e MIT ou GPL-3 no código.

## 8. Política para arquivos pesados

Quatro regras, em ordem de preferência:

**Não versione o que dá para baixar.** O `dados/MANIFEST.md` guarda URL, data do
download e versão de cada fonte. Dez gigabytes viram uma página de texto, e a
reprodutibilidade fica melhor, não pior, porque hoje ninguém sabe qual coleção do
MapBiomas ou qual data de corte do GFW você usou.

**Não versione o que dá para refazer.** O script é a receita. Se refazer custa três
horas de processamento, isso vai no README como aviso, não no git como blob.

**Publique o pequeno e original com DOI.** É o Zenodo acima.

**Git LFS só se sobrar necessidade.** A conta gratuita do GitHub dá 1 GB de
armazenamento LFS e 1 GB por mês de banda; pacotes de 50 GB custam 5 dólares por
mês. Para os 478 MB de screenshots comprimidos caberia no gratuito, mas nem isso é
necessário se você comprimir para JPEG. Para os 33 GB atuais seria assinatura
permanente para guardar sobretudo lixo e coisa regenerável, o que é a decisão
errada.

O que não recomendo: DVC, `git-annex` ou qualquer camada extra de versionamento de
dados. São ferramentas boas para pipeline que roda muitas vezes com dados que mudam.
Aqui o pipeline rodou uma vez, os dados brutos são públicos e imutáveis, e a
complexidade não se paga antes da entrega do TCC.
