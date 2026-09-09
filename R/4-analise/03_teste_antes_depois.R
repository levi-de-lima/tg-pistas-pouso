# =============================================================================
# resultados_novo.R
# Série mensal de mineração por pista e teste antes/depois do surgimento.
# Diferença para o resultados.R: o zero do eixo é o vline_inicio (data observada
# no Planet) e não o inicio_est (detector heurístico, descartado).
# =============================================================================

library(sf)
library(dplyr)
library(tidyr)
library(lubridate)
library(purrr)
library(ggplot2)

# -----------------------------------------------------------------------------
# Parâmetros
# -----------------------------------------------------------------------------
PARAMS <- list(
  data_inicio = "2016-08-01",
  data_fim    = "2025-11-01",
  dist_max    = 6000,
  Ks          = c(1, 4),
  K_alvo      = 4,
  janela      = 12
)

dir_out <- "9_resultados/v2"
dir.create(file.path(dir_out, "histogramas"), recursive = TRUE, showWarnings = FALSE)

K_max <- max(PARAMS$Ks)

# -----------------------------------------------------------------------------
# Carregamento
# -----------------------------------------------------------------------------
# Lê só as colunas usadas e já descarta, no SQL, as detecções sem nenhuma pista
# dentro do raio. Como dist_1 é a menor distância, dist_1 > raio implica que
# nenhum rank entra. Sem geometria, que aqui não serve para nada.
colunas_k <- paste0("pista_", seq_len(K_max), ", dist_", seq_len(K_max), collapse = ", ")

query_gfw <- paste0(
  "SELECT doy, area, ", colunas_k,
  " FROM GFW_dist WHERE dist_1 <= ", PARAMS$dist_max
)

query_deter <- paste0(
  "SELECT doy, area, ", colunas_k,
  " FROM deter_dist WHERE dist_1 <= ", PARAMS$dist_max,
  " AND doy < '2019-01-02'"
)

GFW_raw      <- st_read("6_gfw/GFW_dist.gpkg", query = query_gfw, quiet = TRUE)
Deter_before <- st_read("7_alertas_before/deter_dist.gpkg", query = query_deter, quiet = TRUE)
base_pistas  <- read_sf("5_base_final/base_pistas_final.gpkg", layer = "pontos")

cat("Detecções dentro do raio: GFW", nrow(GFW_raw), "| DETER", nrow(Deter_before), "\n")

# Empilha os ranks um a um em vez de pivotar tudo de uma vez. O pivot_longer
# sobre as 7 colunas multiplicava a tabela por 7 antes de qualquer filtro.
empilha_ranks <- function(df) {
  map_dfr(seq_len(K_max), function(r) {
    tibble(
      doy       = as.Date(df$doy),
      area      = df$area,
      pista     = as.integer(df[[paste0("pista_", r)]]),
      dist      = df[[paste0("dist_", r)]],
      rank_novo = r
    ) %>%
      filter(!is.na(pista), dist <= PARAMS$dist_max)
  })
}

GFW_long <- bind_rows(empilha_ranks(GFW_raw), empilha_ranks(Deter_before))

rm(GFW_raw, Deter_before)
gc()

plano <- base_pistas %>%
  st_drop_geometry() %>%
  mutate(
    vline_inicio = as.Date(start_date),
    vline_fim    = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim) %>%
  filter(!is.na(vline_inicio)) %>%
  mutate(id_pista = as.integer(id_pista))

cat("Pistas com data de início observada: ", nrow(plano), "\n\n")

# -----------------------------------------------------------------------------
# Séries mensais por pista
# -----------------------------------------------------------------------------
grade <- expand_grid(
  id_pista = plano$id_pista,
  mes = seq(as.Date(PARAMS$data_inicio), as.Date(PARAMS$data_fim), by = "month")
)

resultados <- tibble()

for (K in PARAMS$Ks) {

  cat("  K =", K, "\n")

  serie_mensal <- GFW_long %>%
    filter(rank_novo <= K) %>%
    mutate(mes = floor_date(doy, "month")) %>%
    group_by(id_pista = pista, mes) %>%
    summarise(area_mes = sum(area, na.rm = TRUE), .groups = "drop")

  resultados <- bind_rows(
    resultados,
    grade %>%
      left_join(serie_mensal, by = c("id_pista", "mes")) %>%
      mutate(area_mes = replace_na(area_mes, 0)) %>%
      arrange(id_pista, mes) %>%
      group_by(id_pista) %>%
      mutate(acum_area = cumsum(area_mes)) %>%
      ungroup() %>%
      mutate(K = K)
  )
}

resultados <- resultados %>%
  left_join(plano, by = "id_pista") %>%
  mutate(
    meses_rel = interval(vline_inicio, mes) %/% months(1)
  )

# -----------------------------------------------------------------------------
# Histogramas por pista e gráfico resumo
# -----------------------------------------------------------------------------
ids <- resultados %>%
  filter(K == PARAMS$K_alvo) %>%
  distinct(id_pista) %>%
  pull(id_pista)

for (i in ids) {

  dados <- resultados %>%
    filter(
      id_pista == i,
      K == PARAMS$K_alvo,
      meses_rel >= -PARAMS$janela,
      meses_rel <= PARAMS$janela
    )

  if (nrow(dados) == 0) next

  p <- ggplot(
    dados,
    aes(
      x = meses_rel,
      y = area_mes
    )
  ) +

    geom_col(width = 1) +

    geom_vline(
      xintercept = 0,
      linetype = "dashed",
      linewidth = 1
    ) +

    scale_x_continuous(
      breaks = -12:12,
      limits = c(-13, 13)
    ) +

    labs(
      title = paste("Pista", i, "- K =", PARAMS$K_alvo),
      subtitle = "0 = surgimento da pista",
      x = "Meses relativos ao surgimento",
      y = "Área"
    ) +

    theme_bw()

  nome_arquivo <- file.path(
    dir_out, "histogramas",
    paste0("pista_", i, "_K", PARAMS$K_alvo, ".png")
  )

  ggsave(
    filename = nome_arquivo,
    plot = p,
    width = 8,
    height = 6,
    dpi = 300,
    bg = "white"
  )
}

dados_resumo <- resultados %>%
  filter(
    K == PARAMS$K_alvo,
    meses_rel >= -PARAMS$janela,
    meses_rel <= PARAMS$janela
  ) %>%
  group_by(meses_rel) %>%
  summarise(
    media_area = mean(area_mes, na.rm = TRUE),
    n = n(),
    .groups = "drop"
  )

p <- ggplot(
  dados_resumo,
  aes(
    x = meses_rel,
    y = media_area
  )
) +

  geom_col(width = 1) +

  geom_vline(
    xintercept = 0,
    linetype = "dashed",
    linewidth = 1
  ) +

  scale_x_continuous(
    breaks = -12:12,
    limits = c(-13, 13)
  ) +

  labs(
    title = paste0("Área média relativa ao surgimento da pista (K = ", PARAMS$K_alvo, ")"),
    subtitle = "Média entre todas as pistas alinhadas pela data de início",
    x = "Meses relativos ao surgimento",
    y = "Área média"
  ) +

  theme_bw()

ggsave(
  file.path(dir_out, "histogramas", paste0("resumo_K", PARAMS$K_alvo, ".png")),
  p,
  width = 10,
  height = 6,
  dpi = 300,
  bg = "white"
)

# -----------------------------------------------------------------------------
# Tabela antes/depois e testes
# -----------------------------------------------------------------------------
monta_resumo <- function(K_i) {

  resultados %>%
    filter(
      K == K_i,
      meses_rel >= -PARAMS$janela,
      meses_rel <= PARAMS$janela
    ) %>%
    group_by(id_pista) %>%
    summarise(

      media_antes = mean(
        area_mes[meses_rel < 0],
        na.rm = TRUE
      ),

      mediana_antes = median(
        area_mes[meses_rel < 0],
        na.rm = TRUE
      ),

      sd_antes = sd(
        area_mes[meses_rel < 0],
        na.rm = TRUE
      ),

      media_depois = mean(
        area_mes[meses_rel >= 0],
        na.rm = TRUE
      ),

      mediana_depois = median(
        area_mes[meses_rel >= 0],
        na.rm = TRUE
      ),

      sd_depois = sd(
        area_mes[meses_rel >= 0],
        na.rm = TRUE
      ),

      n_antes = sum(meses_rel < 0),
      n_depois = sum(meses_rel >= 0),

      .groups = "drop"
    ) %>%
    filter(n_antes > 0, n_depois > 0)
}

tabela_resumo <- monta_resumo(PARAMS$K_alvo)

for (K_i in PARAMS$Ks) {

  tr <- monta_resumo(K_i)

  cat("\n================ K =", K_i, " | n =", nrow(tr), "pistas ================\n")

  cat("\nmediana mensal:\n")
  print(wilcox.test(tr$mediana_depois,
                    tr$mediana_antes,
                    paired = TRUE,
                    alternative = "greater",
                    conf.int = TRUE,
                    conf.level = 0.99))

  cat("\nmédia mensal:\n")
  print(wilcox.test(tr$media_depois,
                    tr$media_antes,
                    paired = TRUE,
                    alternative = "greater",
                    conf.int = TRUE,
                    conf.level = 0.99))

  cat("pistas com aumento da área média:",
      sum(tr$media_depois > tr$media_antes), "de", nrow(tr), "\n")
  cat("mediana da área média antes (ha): ", round(median(tr$media_antes)/1e4, 2), "\n")
  cat("mediana da área média depois (ha):", round(median(tr$media_depois)/1e4, 2), "\n")
}

# -----------------------------------------------------------------------------
# Histogramas das médias, boxplot e diferenças
# -----------------------------------------------------------------------------
p1 <- ggplot(
  tabela_resumo,
  aes(x = media_antes)
) +
  geom_histogram(
    bins = 20
  ) +
  labs(
    title = "Distribuição das médias antes do surgimento da pista",
    x = "Média da área antes",
    y = "Frequência"
  ) +
  theme_bw()

ggsave(
  file.path(dir_out, "histogramas", "media_antes.png"),
  p1,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)

p2 <- ggplot(
  tabela_resumo,
  aes(x = media_depois)
) +
  geom_histogram(
    bins = 20
  ) +
  labs(
    title = "Distribuição das médias depois do surgimento da pista",
    x = "Média da área depois",
    y = "Frequência"
  ) +
  theme_bw()

ggsave(
  file.path(dir_out, "histogramas", "media_depois.png"),
  p2,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)

dados_box <- tabela_resumo %>%
  select(
    id_pista,
    media_antes,
    media_depois
  ) %>%
  pivot_longer(
    cols = c(media_antes, media_depois),
    names_to = "periodo",
    values_to = "media_area"
  ) %>%
  mutate(
    media_area = media_area/10^4
  )

p <- ggplot(
  dados_box,
  aes(
    x = periodo,
    y = media_area,
    fill = periodo
  )
) +

  geom_boxplot(
    alpha = .6,
    outlier.alpha = .5
  ) +

  labs(
    title = "Distribuição das áreas médias",
    subtitle = "Área média em hectares",
    x = "",
    y = "Área média",
    fill = "Período"
  ) +

  theme_bw()

ggsave(
  file.path(dir_out, "histogramas", "boxplot_antes_depois.png"),
  p,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)

dados_diff <- tabela_resumo %>%
  mutate(
    diferenca = media_depois - media_antes
  )

p_diff <- ggplot(
  dados_diff,
  aes(x = diferenca)
) +

  geom_histogram(
    bins = 25
  ) +

  geom_vline(
    xintercept = 0,
    linetype = "dashed"
  ) +

  labs(
    title = "Distribuição das diferenças",
    subtitle = "Diferença = depois − antes",
    x = "Diferença",
    y = "Frequência"
  ) +

  theme_bw()

ggsave(
  file.path(dir_out, "histogramas", "hist_diffs.png"),
  p_diff,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)
