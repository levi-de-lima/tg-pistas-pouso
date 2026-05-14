# =============================================================================
# bfast_diagnostico_visual.R
# Para cada pista, gera gráficos comparando:
#   - Curva cumulativa K=1 e K=4 (a mesma do código original)
#   - Vlines de verdade-de-campo (vline_inicio, vline_fim) em cinza
#   - Vlines BFAST estimadas em azul (K=1) e vermelho (K=4)
#   - Painel inferior: série mensal de taxa usada pelo BFAST + breakpoints
#
# Útil para inspeção visual de uma amostra antes de confiar no resultado agregado.
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(ggplot2)
  library(cowplot)
  library(purrr)
})

source("bfast_funcoes.R")

# Carrega os mesmos dados que bfast_analise.R
GFW_raw       <- read_sf("6_gfw/GFW_dist.gpkg")
Deter_before  <- read_sf("7_alertas_before/deter_dist.gpkg") %>%
                   filter(doy < "2019-01-02")
base_pistas   <- read_sf("5_base_final/base_pistas_final.gpkg", layer = "pontos")
GFW           <- bind_rows(GFW_raw, Deter_before)

pistas_validade <- base_pistas %>%
  st_drop_geometry() %>%
  select(id_pista, start_date, end_date, inop_date)

verdade_pista <- base_pistas %>%
  st_drop_geometry() %>%
  mutate(
    vline_inicio = as.Date(start_date),
    vline_fim    = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim)

GFW_long <- make_gfw_long(GFW, pistas_validade)

# Carrega resultados do BFAST já calculados (rode bfast_analise.R antes)
tabela_final <- read.csv("8_bfast_resultados/tabela_final.csv") %>%
  mutate(across(c(inicio_est_K1, fim_est_K1, inicio_est_K4, fim_est_K4,
                  vline_inicio, vline_fim, inicio_estimado, fim_estimado),
                as.Date))


# -----------------------------------------------------------------------------
# Função: gera painel diagnóstico para UMA pista
# -----------------------------------------------------------------------------

diagnostico_pista <- function(id_pista_alvo,
                              GFW_long, tabela_final, verdade_pista,
                              data_inicio = "2016-01-01") {

  # --- (1) Série cumulativa K=1 e K=4, com complete()+approx (só visual)
  curvas <- map_dfr(c(1, 4), function(K) {
    bruto <- processa_K_bruto(GFW_long, id_pista_alvo, K)
    if (nrow(bruto) == 0) return(NULL)
    data_ult <- max(bruto$doy)
    bruto %>%
      transmute(doy = doy, area = area_acum, K = K) %>%
      complete(doy = seq(as.Date(data_inicio), data_ult, by = "day")) %>%
      mutate(
        area = approx(doy[!is.na(area)], area[!is.na(area)],
                      xout = doy, method = "linear", rule = 2)$y,
        K = factor(paste0("K = ", K), levels = c("K = 1", "K = 4"))
      ) %>%
      fill(K, .direction = "downup")
  })

  if (is.null(curvas) || nrow(curvas) == 0) return(NULL)

  # --- (2) Série mensal de taxa (a que entra no BFAST)
  mensais <- map_dfr(c(1, 4), function(K) {
    bruto <- processa_K_bruto(GFW_long, id_pista_alvo, K)
    if (nrow(bruto) == 0) return(NULL)
    m <- preparar_mensal(bruto, data_inicio = data_inicio)
    if (is.null(m)) return(NULL)
    m %>% mutate(K = factor(paste0("K = ", K), levels = c("K = 1", "K = 4")))
  })

  # --- (3) Vlines: verdade-de-campo + estimativas BFAST
  vc <- verdade_pista %>% filter(id_pista == id_pista_alvo)
  est <- tabela_final %>% filter(id_pista == id_pista_alvo)

  vlines <- tibble(
    xintercept = c(vc$vline_inicio, vc$vline_fim,
                   est$inicio_est_K1, est$fim_est_K1,
                   est$inicio_est_K4, est$fim_est_K4),
    tipo = c("pista_inicio", "pista_fim",
             "bfast_K1_inicio", "bfast_K1_fim",
             "bfast_K4_inicio", "bfast_K4_fim")
  ) %>% filter(!is.na(xintercept))

  cores_v <- c(
    pista_inicio    = "gray30",  pista_fim    = "gray30",
    bfast_K1_inicio = "#1976D2", bfast_K1_fim = "#1976D2",
    bfast_K4_inicio = "#D32F2F", bfast_K4_fim = "#D32F2F"
  )
  tipo_v <- c(
    pista_inicio = "solid",  pista_fim = "dashed",
    bfast_K1_inicio = "solid", bfast_K1_fim = "dashed",
    bfast_K4_inicio = "solid", bfast_K4_fim = "dashed"
  )

  # --- (4) Painel de cima: cumulativa
  g_cum <- ggplot(curvas, aes(x = doy, y = area, color = K)) +
    geom_line(linewidth = 0.7) +
    geom_vline(data = vlines,
               aes(xintercept = as.numeric(xintercept),
                   color = tipo, linetype = tipo),
               show.legend = TRUE) +
    scale_color_manual(values = c(
      "K = 1" = "#1976D2", "K = 4" = "#D32F2F", cores_v)) +
    scale_linetype_manual(values = c("K = 1" = "solid", "K = 4" = "solid",
                                     tipo_v)) +
    labs(title = paste0("Pista ", id_pista_alvo,
                        " — status K1: ", est$status_K1,
                        " | status K4: ", est$status_K4),
         y = "Área acumulada (m²)", x = NULL) +
    theme_minimal() +
    theme(legend.position = "right",
          legend.text = element_text(size = 7))

  # --- (5) Painel de baixo: taxa mensal + breakpoints
  g_taxa <- ggplot(mensais, aes(x = mes, y = taxa, color = K)) +
    geom_col(aes(fill = K), alpha = 0.4, position = "identity") +
    geom_vline(data = vlines,
               aes(xintercept = as.numeric(xintercept), color = tipo,
                   linetype = tipo),
               show.legend = FALSE) +
    scale_color_manual(values = c(
      "K = 1" = "#1976D2", "K = 4" = "#D32F2F", cores_v)) +
    scale_fill_manual(values = c("K = 1" = "#1976D2", "K = 4" = "#D32F2F")) +
    scale_linetype_manual(values = c("K = 1" = "solid", "K = 4" = "solid",
                                     tipo_v)) +
    labs(y = "Taxa mensal (m²)", x = "Data") +
    theme_minimal() +
    theme(legend.position = "none") +
    facet_wrap(~ K, ncol = 1, scales = "free_y")

  plot_grid(g_cum, g_taxa, ncol = 1, rel_heights = c(1.2, 1))
}


# -----------------------------------------------------------------------------
# Gera diagnóstico para uma AMOSTRA de pistas (rápido) ou TODAS
# -----------------------------------------------------------------------------
dir.create("8_bfast_resultados/diagnostico_visual", showWarnings = FALSE)

# Amostra estratificada por status: pega exemplos representativos
amostra_ids <- tabela_final %>%
  group_by(status_K4) %>%
  slice_sample(n = 5) %>%
  pull(id_pista)

# Descomente para rodar em TODAS as pistas:
# amostra_ids <- tabela_final$id_pista

for (id in amostra_ids) {
  cat("Diagnóstico pista", id, "\n")
  p <- tryCatch(
    diagnostico_pista(id, GFW_long, tabela_final, verdade_pista),
    error = function(e) { message("  Erro: ", e$message); NULL }
  )
  if (!is.null(p)) {
    ggsave(paste0("8_bfast_resultados/diagnostico_visual/diag_pista_", id, ".png"),
           p, width = 10, height = 7, dpi = 120, bg = "white")
  }
}

cat("Diagnósticos salvos em 8_bfast_resultados/diagnostico_visual/\n")
