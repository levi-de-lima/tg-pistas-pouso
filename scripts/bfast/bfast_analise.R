# =============================================================================
# bfast_analise.R
# Pipeline principal: para cada pista, estima início e fim da atividade
# mineradora usando BFAST Lite em K=1 e K=4, e compara com a verdade-de-campo
# (vline_inicio e vline_fim).
# =============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(tidyr)
  library(lubridate)
  library(purrr)
  library(ggplot2)
})

source("scripts/bfast/bfast_funcoes.R")  # ajuste o caminho conforme sua organização

# -----------------------------------------------------------------------------
# Parâmetros do experimento
# -----------------------------------------------------------------------------
PARAMS <- list(
  data_inicio       = "2016-01-01",
  dist_max          = 6000,        # m, mesmo do código original
  Ks                = c(1, 4),
  min_meses_ativos  = 6,           # piso para rodar BFAST
  h_min             = 0.1,         # fração mínima de segmento (~12 meses em 10 anos)
  frac_limiar       = 0.05,        # 5% do P95 da taxa para classificar "ativo"
  janela_concord_d  = 180          # dias para concordância K1 vs K4
)

# -----------------------------------------------------------------------------
# Carregamento dos dados (mesmas fontes do seu script original)
# -----------------------------------------------------------------------------
GFW_raw       <- read_sf("6_gfw/GFW_dist.gpkg")
Deter_before  <- read_sf("7_alertas_before/deter_dist.gpkg") %>%
                   filter(doy < "2019-01-02")
base_pistas   <- read_sf("5_base_final/base_pistas_final.gpkg", layer = "pontos")
GFW           <- bind_rows(GFW_raw, Deter_before)

pistas_validade <- base_pistas %>%
  st_drop_geometry() %>%
  select(id_pista, start_date, end_date, inop_date)

# Verdade-de-campo (mesma lógica do sf_vline original, mas em formato wide)
verdade_pista <- base_pistas %>%
  st_drop_geometry() %>%
  mutate(
    vline_inicio = as.Date(start_date),
    vline_fim    = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim)

# Long format das detecções
GFW_long <- make_gfw_long(GFW, pistas_validade)

# -----------------------------------------------------------------------------
# Loop principal: estima (inicio, fim) para cada par (pista, K)
# -----------------------------------------------------------------------------
cat("Total de pistas: ", length(base_pistas$id_pista), "\n")

resultados <- map_dfr(base_pistas$id_pista[1:10], function(id) {
  cat("  Pista ", id, " ... ")
  res_id <- map_dfr(PARAMS$Ks, function(K) {
    tryCatch(
      estimar_uma_pista(
        GFW_long, id, K,
        data_inicio      = PARAMS$data_inicio,
        dist_max         = PARAMS$dist_max,
        min_meses_ativos = PARAMS$min_meses_ativos,
        h_min            = PARAMS$h_min,
        frac_limiar      = PARAMS$frac_limiar
      ),
      error = function(e) {
        tibble(
          id_pista = id, K = K,
          inicio_est = as.Date(NA), fim_est = as.Date(NA),
          n_breakpoints = NA_integer_, status = paste0("erro:", e$message),
          area_total = NA_real_
        )
      }
    )
  })
  cat(paste(res_id$status, collapse = " | "), "\n")
  res_id
})

# -----------------------------------------------------------------------------
# Pivot wide: uma linha por pista com colunas para K=1 e K=4 lado a lado
# -----------------------------------------------------------------------------
tabela <- resultados %>%
  pivot_wider(
    id_cols     = id_pista,
    names_from  = K,
    values_from = c(inicio_est, fim_est, n_breakpoints, status, area_total),
    names_glue  = "{.value}_K{K}"
  ) %>%
  left_join(verdade_pista, by = "id_pista")

# -----------------------------------------------------------------------------
# Diagnóstico interno: concordância entre K=1 e K=4
# -----------------------------------------------------------------------------
diagnostico <- tabela %>%
  mutate(
    delta_inicio = as.numeric(inicio_est_K1 - inicio_est_K4),
    delta_fim    = as.numeric(fim_est_K1    - fim_est_K4),
    concord_inicio = abs(delta_inicio) <= PARAMS$janela_concord_d,
    concord_fim    = abs(delta_fim)    <= PARAMS$janela_concord_d
  )

resumo_concord <- diagnostico %>%
  summarise(
    n_total         = n(),
    n_inicio_K1     = sum(!is.na(inicio_est_K1)),
    n_inicio_K4     = sum(!is.na(inicio_est_K4)),
    n_fim_K1        = sum(!is.na(fim_est_K1)),
    n_fim_K4        = sum(!is.na(fim_est_K4)),
    concord_inicio  = mean(concord_inicio, na.rm = TRUE),
    concord_fim     = mean(concord_fim,    na.rm = TRUE),
    media_delta_in  = mean(delta_inicio, na.rm = TRUE),
    mediana_delta_in= median(delta_inicio, na.rm = TRUE),
    media_delta_fim = mean(delta_fim, na.rm = TRUE),
    mediana_delta_fim = median(delta_fim, na.rm = TRUE)
  )
print(resumo_concord)

# -----------------------------------------------------------------------------
# Decisão final de estimativa por pista
# -----------------------------------------------------------------------------
# Regra:
#   - Se K=1 tem estimativa, usa K=1 (interpretação causal mais limpa).
#   - Senão, usa K=4 (fallback para pistas em cluster onde K=1 é vazio).
#   - Marca a fonte para rastreabilidade.

tabela_final <- tabela %>%
  mutate(
    inicio_estimado = coalesce(inicio_est_K1, inicio_est_K4),
    fim_estimado    = coalesce(fim_est_K1,    fim_est_K4),
    fonte_inicio    = case_when(
      !is.na(inicio_est_K1) ~ "K1",
      !is.na(inicio_est_K4) ~ "K4",
      TRUE                  ~ NA_character_
    ),
    fonte_fim       = case_when(
      !is.na(fim_est_K1) ~ "K1",
      !is.na(fim_est_K4) ~ "K4",
      TRUE               ~ NA_character_
    ),
    lag_inicio_dias = as.numeric(inicio_estimado - vline_inicio),
    lag_fim_dias    = as.numeric(fim_estimado    - vline_fim)
  )

# -----------------------------------------------------------------------------
# Estatísticas finais: lag entre mineração e pista
# -----------------------------------------------------------------------------
resumo_lags <- tabela_final %>%
  summarise(
    n_lag_inicio     = sum(!is.na(lag_inicio_dias)),
    media_lag_inicio = mean(lag_inicio_dias,  na.rm = TRUE),
    mediana_lag_in   = median(lag_inicio_dias, na.rm = TRUE),
    iqr_lag_inicio   = IQR(lag_inicio_dias,    na.rm = TRUE),
    n_lag_fim        = sum(!is.na(lag_fim_dias)),
    media_lag_fim    = mean(lag_fim_dias,  na.rm = TRUE),
    mediana_lag_fim  = median(lag_fim_dias, na.rm = TRUE),
    iqr_lag_fim      = IQR(lag_fim_dias,    na.rm = TRUE),
    # quantos casos a mineração começou ANTES da pista entrar em operação
    pct_min_antes_pista = mean(lag_inicio_dias < 0, na.rm = TRUE)
  )
print(resumo_lags)

# Teste de Wilcoxon: a defasagem é significativamente diferente de zero?
if (sum(!is.na(tabela_final$lag_inicio_dias)) > 5) {
  cat("\nWilcoxon (lag_inicio != 0):\n")
  print(wilcox.test(tabela_final$lag_inicio_dias, mu = 0,
                    alternative = "two.sided"))
}
if (sum(!is.na(tabela_final$lag_fim_dias)) > 5) {
  cat("\nWilcoxon (lag_fim != 0):\n")
  print(wilcox.test(tabela_final$lag_fim_dias, mu = 0,
                    alternative = "two.sided"))
}

# -----------------------------------------------------------------------------
# Salva resultados
# -----------------------------------------------------------------------------
dir.create("8_bfast_resultados", showWarnings = FALSE)
write.csv(tabela_final,  "8_bfast_resultados/tabela_final.csv",  row.names = FALSE)
write.csv(diagnostico,   "8_bfast_resultados/diagnostico_K.csv", row.names = FALSE)
write.csv(resumo_concord, "8_bfast_resultados/resumo_concordancia.csv",
          row.names = FALSE)
write.csv(resumo_lags,   "8_bfast_resultados/resumo_lags.csv",   row.names = FALSE)

cat("\nResultados salvos em 8_bfast_resultados/\n")

# -----------------------------------------------------------------------------
# Gráfico-resumo: distribuição dos lags
# -----------------------------------------------------------------------------
g_lag_inicio <- tabela_final %>%
  filter(!is.na(lag_inicio_dias)) %>%
  ggplot(aes(x = lag_inicio_dias / 30)) +
    geom_histogram(bins = 40, fill = "#1976D2", alpha = 0.7) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray30") +
    labs(
      title = "Defasagem: início da mineração vs. início da pista",
      subtitle = "Valores negativos: mineração começou ANTES da pista entrar em operação",
      x = "Lag (meses)", y = "Nº de pistas"
    ) +
    theme_minimal()

g_lag_fim <- tabela_final %>%
  filter(!is.na(lag_fim_dias)) %>%
  ggplot(aes(x = lag_fim_dias / 30)) +
    geom_histogram(bins = 40, fill = "#D32F2F", alpha = 0.7) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray30") +
    labs(
      title = "Defasagem: fim da mineração vs. fim da pista",
      subtitle = "Valores positivos: mineração continuou DEPOIS de a pista sair de operação",
      x = "Lag (meses)", y = "Nº de pistas"
    ) +
    theme_minimal()

ggsave("8_bfast_resultados/dist_lag_inicio.png", g_lag_inicio,
       width = 8, height = 5, dpi = 150)
ggsave("8_bfast_resultados/dist_lag_fim.png", g_lag_fim,
       width = 8, height = 5, dpi = 150)
