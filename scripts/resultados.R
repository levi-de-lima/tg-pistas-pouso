# =============================================================================
# bfast_analise.R
# Pipeline:
#   - Separa pistas em "tem vline_inicio" e "tem vline_fim".
#   - Para cada grupo, estima só o que faz sentido (início ou fim).
#   - Pistas com ambos rodam os dois detectores.
# =============================================================================

library(slider)
library(readr)
library(sf)
library(dplyr)
library(tidyr)
library(lubridate)
library(slider)
library(purrr)
library(ggplot2)

source("scripts/bfast/bfast_funcoes.R")

# -----------------------------------------------------------------------------
# Parâmetros
# -----------------------------------------------------------------------------
PARAMS <- list(
  data_inicio    = "2016-08-01",
  data_fim       = "2025-11-01",
  dist_max       = 6000,
  Ks             = c(1, 4),
  janela_slope   = 6,
  meses_basal    = 12,
  quantil_basal  = 0.25,
  fator_explosao = 3.0,
  frac_taxa_min  = 2.0,
  h_min          = 0.1,
  breaks_method  = "BIC",
  frac_plato     = 0.30,
  min_meses_sustentado = 6
)

# -----------------------------------------------------------------------------
# Carregamento
# -----------------------------------------------------------------------------
GFW_raw      <- read_sf("6_gfw/GFW_dist.gpkg")
Deter_before <- read_sf("7_alertas_before/deter_dist.gpkg") %>% filter(doy < "2019-01-02")
base_pistas  <- read_sf("5_base_final/base_pistas_final.gpkg", layer = "pontos")
GFW          <- bind_rows(GFW_raw, Deter_before)

pistas_validade <- base_pistas %>%
  st_drop_geometry() %>%
  select(id_pista, start_date, end_date)

make_gfw_long <- function(GFW_data, pistas_validade) {
  GFW_data %>%
    st_drop_geometry() %>%
    mutate(detect_id = row_number()) %>%
    pivot_longer(
      cols = matches("^(pista|dist)_\\d+$"),
      names_to = c(".value", "rank_orig"),
      names_pattern = "(pista|dist)_(\\d+)"
    ) %>%
    mutate(pista = as.integer(pista)) %>%
    left_join(pistas_validade, by = c("pista" = "id_pista")) %>%
    filter(!is.na(pista)) %>%
    group_by(detect_id) %>%
    arrange(dist, .by_group = TRUE) %>%
    mutate(rank_novo = row_number()) %>%
    ungroup()
}

GFW_long <- make_gfw_long(GFW, pistas_validade)

pistas_datas <- base_pistas %>%
  st_drop_geometry() %>%
  mutate(
    vline_inicio = as.Date(start_date),
    vline_fim    = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim)

plano <- pistas_datas %>%
  mutate(conjunto = case_when(
    !is.na(vline_inicio) & !is.na(vline_fim) ~ "ambos",
    !is.na(vline_inicio)                     ~ "inicio",
    !is.na(vline_fim)                        ~ "fim",
    TRUE                                     ~ NA_character_
  )) %>%
  filter(!is.na(conjunto)) %>%
  mutate(id_pista = as.integer(id_pista))

cat("Total de pistas: ", nrow(plano), "\n")
cat("  Estimam ambos:  ", sum(plano$conjunto == "ambos"), "\n")
cat("  Só início:      ", sum(plano$conjunto == "inicio"), "\n")
cat("  Só fim:         ", sum(plano$conjunto == "fim"), "\n\n")

# -----------------------------------------------------------------------------
# Loop for
# -----------------------------------------------------------------------------

resultados <- tibble()

for (id in 1:length(plano$id_pista)) {
  i <- id
  
  id_pista     <- plano$id_pista[i]
  vline_inicio <- plano$vline_inicio[i]
  vline_fim    <- plano$vline_fim[i]
  conjunto     <- plano$conjunto[i]
  
  cat("  Pista ", id_pista, " [", conjunto, "] ... ")
  
  res_id <- tibble()
  
  for (K in PARAMS$Ks) {
    
    serie_temp_id <- GFW_long %>%
      filter(pista == id_pista) %>%
      filter(rank_novo <= K, dist <= 6000) %>%
      group_by(doy) %>%
      summarise(area_evento = sum(area, na.rm = TRUE), .groups = "drop") %>%
      arrange(doy) %>%
      mutate(area_acum = cumsum(area_evento), K = K)
    
    serie_mensal <- serie_temp_id %>%
      mutate(mes = floor_date(doy, "month")) %>%
      group_by(mes) %>%
      summarise(area_mes = sum(area_evento, na.rm = TRUE), .groups = "drop")

    data_min <- as.Date(PARAMS$data_inicio)
    data_fim <- as.Date(PARAMS$data_fim)

    serie_mensal_completa <- serie_mensal %>%
      right_join(tibble(mes = seq(data_min, data_fim, by = "month")), by = "mes") %>%
      mutate(area_mes = replace_na(area_mes, 0)) %>%
      arrange(mes) %>%
      mutate(
        acum_area = cumsum(area_mes),
        slope = acum_area - lag(acum_area),
        slope_suave = slide_dbl(
          slope,
          mean,
          .before = 2,
          .complete = TRUE
        )
      )

    serie_ativa <- serie_mensal_completa

    # --- Detecta INÍCIO ---
    limiar_inicio <- quantile(
      serie_mensal_completa$slope_suave,
      probs=.10,
      na.rm=TRUE
    ) +
      0.3*mad(
        serie_mensal_completa$slope_suave,
        na.rm=TRUE
      )

    serie_ativa <- serie_ativa %>%
      mutate(
        ativo_inicio = !is.na(slope_suave) & slope_suave > limiar_inicio,

        persistente_inicio = ativo_inicio & slide_lgl(
          ativo_inicio,
          ~mean(.x, na.rm = TRUE) >= 0.6,
          .after  = 9,   # próximos 10 meses (inclusive o atual)
          .complete = TRUE
        )
      )

    inicio_est <- serie_ativa %>%
      mutate(
        inicio_bloco_inicio =
          persistente_inicio &
          !lag(persistente_inicio, default = TRUE)
      ) %>%
      filter(inicio_bloco_inicio) %>%
      slice(1) %>%
      mutate(mes = mes - months(1)) %>%
      pull(mes)

    # --- Detecta FIM ---
    limiar_fim <- quantile(
      serie_mensal_completa$slope_suave,
      probs=.10,
      na.rm=TRUE
    ) +
      0.3*mad(
        serie_mensal_completa$slope_suave,
        na.rm=TRUE
      )

    serie_ativa <- serie_ativa %>%
      mutate(
        inativo_fim = !is.na(slope_suave) & slope_suave < limiar_fim,

        persistente_fim =
          inativo_fim &
          lead(inativo_fim, 1, default = TRUE) &
          lead(inativo_fim, 2, default = TRUE) &
          lead(inativo_fim, 3, default = TRUE) &
          lead(inativo_fim, 4, default = TRUE)
      )

    if (tail(serie_ativa$inativo_fim, 1)) {

      fim_est <- serie_ativa %>%
        mutate(
          inicio_bloco_fim =
            persistente_fim &
            !lag(persistente_fim, default = TRUE)
        ) %>%
        filter(inicio_bloco_fim) %>%
        slice_tail(n = 1) %>%
        mutate(mes = mes - months(1)) %>%
        pull(mes)

    } else {
      fim_est <- NA
    }

    res_id <- bind_rows(res_id, serie_mensal_completa %>%
                          mutate(
                            id_pista   = id_pista,
                            K          = K,
                            inicio_est = inicio_est,
                            fim_est    = fim_est
                          )
                        )

    p <- ggplot(serie_ativa, aes(x = mes, y = acum_area)) +
      geom_line() +

      # Início estimado
      geom_vline(
        xintercept = inicio_est,
        linetype   = "dashed",
        color      = "blue"
      ) +

      # Fim estimado
      geom_vline(
        xintercept = fim_est,
        linetype   = "dashed",
        color      = "red"
      ) +

      # Início real (campo)
      geom_vline(
        xintercept = as.Date(vline_inicio),
        linetype   = "solid",
        color      = "blue"
      ) +

      # Fim real (campo)
      geom_vline(
        xintercept = as.Date(vline_fim),
        linetype   = "solid",
        color      = "red"
      ) +

      labs(
        title    = paste0("Pista ", id_pista, " | K = ", K),
        subtitle = "Azul = início  |  Vermelho = fim  |  Sólida = campo  |  Tracejada = estimado",
        x = "Mês",
        y = "Área acumulada"
      )

    file_name <- paste0("9_bfast_resultados/graficos/pista_", id_pista, ".png")
    ggsave(file_name, p, width = 8, height = 6, dpi = 300, bg = "white")
  }
  
  cat(paste(res_id$status_inicio, "/", res_id$status_fim, collapse = " | "), "\n")
  
  resultados <- bind_rows(resultados, res_id)
}

# Calcula vizinhos num raio de 6000m para cada pista
vizinhos <- base_pistas %>%
  st_transform(crs = 31981) %>% 
  mutate(
    n_vizinhos = lengths(
      st_is_within_distance(geom, geom, dist = 6000)
    )
  ) %>%
  st_drop_geometry() %>%
  dplyr::select(id_pista, n_vizinhos)

resultados_anotados <- resultados %>% 
  filter(!is.na(id_pista)) %>%
  left_join(plano, by = "id_pista") %>%           # <-- adiciona vline_inicio e vline_fim
  left_join(vizinhos, by = "id_pista") %>%
  left_join(
    base_pistas %>% st_drop_geometry() %>% dplyr::select(id_pista, Anac),
    by = "id_pista"
  ) %>%
  mutate(
    lag_inicio_dias = as.numeric(inicio_est - vline_inicio),
    lag_fim_dias    = as.numeric(fim_est    - vline_fim),
    legalidade = case_when(
      Anac == 1 ~ "Legal (Anac)",
      Anac == 0 ~ "Ilegal",
      TRUE      ~ NA_character_
    )
  ) %>%
  distinct(id_pista, K, inicio_est, fim_est, vline_inicio, vline_fim,
           legalidade, n_vizinhos, lag_inicio_dias, lag_fim_dias
           )

# -----------------------------------------------------------------------------
# Outros gráficos
# -----------------------------------------------------------------------------

ids <- resultados %>%
  filter(K == 4) %>%
  distinct(id_pista) %>%
  pull(id_pista)

for(i in ids){
  
  dados <- resultados %>%
    left_join(plano %>% dplyr::select(id_pista, vline_inicio, vline_fim), by = "id_pista") %>%
    filter(
      id_pista == i,
      K == 4,
      !is.na(vline_inicio[1])
    ) %>%
    mutate(
      meses_rel = interval(
        inicio_est,
        mes
      ) %/% months(1)
    ) %>%
    filter(
      meses_rel >= -12,
      meses_rel <= 12
    )
  
  if(nrow(dados) == 0) next
  
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
      limits = c(-12,13)
    ) +
    
    labs(
      title = paste("Pista", i, "- K=4"),
      subtitle = "0 = início da pista",
      x = "Meses relativos ao início",
      y = "Área"
    ) +
    
    theme_bw()
  
  nome_arquivo <- paste0(
    "9_bfast_resultados/histogramas/pista_",
    i,
    "_K4.png"
  )
  
  ggsave(
    filename = nome_arquivo,
    plot = p,
    width = 8,
    height = 6,
    dpi = 300,
    bg = "white"
  )
  
  cat("Salvo:", nome_arquivo, "\n")
}

dados_resumo <- resultados %>%
  filter(
    K == 4,
    !is.na(inicio_est)
  ) %>%
  mutate(
    meses_rel = interval(
      inicio_est,
      mes
    ) %/% months(1)
  ) %>%
  filter(
    meses_rel >= -12,
    meses_rel <= 13
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
    limits = c(-12,13)
  ) +
  
  labs(
    title = "Área média relativa ao início (K=4)",
    subtitle = "Média entre todas as pistas alinhadas pelo início",
    x = "Meses relativos ao início",
    y = "Área média"
  ) +
  
  theme_bw()

ggsave(
  "9_bfast_resultados/histogramas/resumo_K4.png",
  p,
  width = 10,
  height = 6,
  dpi = 300,
  bg = "white"
)


tabela_resumo <- resultados %>%
  filter(
    K == 4,
    !is.na(inicio_est)
  ) %>%
  mutate(
    meses_rel = interval(
      inicio_est,
      mes
    ) %/% months(1)
  ) %>%
  filter(
    meses_rel >= -12,
    meses_rel <= 12
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
  )




# Histograma médias antes
p1 <- ggplot(
  tabela_resumo,
  aes(x = media_antes)
) +
  geom_histogram(
    bins = 20
  ) +
  labs(
    title = "Distribuição das médias antes do início",
    x = "Média da área antes",
    y = "Frequência"
  ) +
  theme_bw()

ggsave(
  "9_bfast_resultados/histogramas/media_antes.png",
  p1,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)


# Histograma médias depois
p2 <- ggplot(
  tabela_resumo,
  aes(x = media_depois)
) +
  geom_histogram(
    bins = 20
  ) +
  labs(
    title = "Distribuição das médias depois do início",
    x = "Média da área depois",
    y = "Frequência"
  ) +
  theme_bw()

ggsave(
  "9_bfast_resultados/histogramas/media_depois.png",
  p2,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)

wilcox.test(tabela_resumo$mediana_depois, 
            tabela_resumo$mediana_antes, 
            paired=TRUE, 
            alternative="great",
            conf.int = TRUE,
            conf.level = 0.99)

wilcox.test(log1p(tabela_resumo$mediana_depois), 
            log1p(tabela_resumo$mediana_antes), 
            paired=TRUE, 
            alternative="great",
            conf.int = TRUE,
            conf.level = 0.99)

t.test(log1p(tabela_resumo$media_depois), 
            log1p(tabela_resumo$media_antes), 
            paired=TRUE, 
            alternative="great",
            conf.int = TRUE,
            conf.level = 0.99)


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
  "9_bfast_resultados/histogramas/boxplot_antes_depois.png",
  p,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)

#


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
  "9_bfast_resultados/histogramas/hist_diffs.png",
  p_diff,
  width = 8,
  height = 6,
  dpi = 300,
  bg = "white"
)



####################################



dados_datas <- base_pistas %>%
  mutate(
    start_plot = coalesce(
      start_date,
      as.Date("2017-07-01")
    ),
    
    end_plot = coalesce(
      end_date,
      as.Date("2026-03-01")
    ),
    
    inicio_censurado = is.na(start_date),
    fim_censurado = is.na(end_date)
  )


dados_long <- dados_datas %>%
  select(
    id_pista,
    start_date,
    end_date
  ) %>%
  pivot_longer(
    cols = c(start_date,end_date),
    names_to = "tipo",
    values_to = "data"
  )

p <- ggplot(
  dados_long,
  aes(
    x = data,
    fill = tipo
  )
) +
  
  geom_density(
    alpha=.4
  ) +
  
  geom_vline(
    xintercept = as.Date("2017-07-01"),
    linetype="dashed"
  ) +
  
  geom_vline(
    xintercept = as.Date("2026-03-01"),
    linetype="dashed"
  ) +
  
  scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y"
  ) +
  
  labs(
    title="Distribuição temporal das pistas",
    subtitle="Linhas tracejadas = limites da janela observada",
    x="Ano",
    y="Densidade"
  ) +
  
  theme_bw()

ggsave(
  "9_bfast_resultados/histogramas/gerais_pista/density_datas.png",
  p,
  width=10,
  height=6,
  dpi=300,
  bg="white"
)



########################################

# --- Área total por mês ---

area_total_mes <- resultados %>%
  filter(K == 4) %>%
  group_by(mes) %>%
  summarise(
    area_total = sum(area_mes, na.rm = TRUE),
    .groups = "drop"
  )

# --- Junta tudo ---
dados_plot <- area_total_mes %>%
  left_join(
    n_pistas_mes,
    by = "mes"
  ) %>%
  left_join(
    precip,
    by = "mes"
  )

# -----------------------
# Escalas
# -----------------------

offset <- 200

# escala da linha vermelha
escala_pistas <- max(
  dados_plot$area_total,
  na.rm = TRUE
) /
  (
    max(
      dados_plot$n_pistas,
      na.rm = TRUE
    ) - offset
  )

# escala da precipitação
escala_precip <- max(
  dados_plot$area_total,
  na.rm = TRUE
) /
  max(
    dados_plot$precip_total,
    na.rm = TRUE
  )

# -----------------------
# Gráfico
# -----------------------

p <- ggplot(
  dados_plot,
  aes(x = mes)
) +
  
  # Barras de área
  geom_col(
    aes(y = area_total),
    fill = "grey40"
  ) +
  
  # Linha vermelha: número de pistas
  geom_line(
    aes(
      y = (n_pistas - offset) *
        escala_pistas
    ),
    color = "red",
    linewidth = 1
  ) +
  
  # Linha azul: precipitação
  geom_area(
    aes(
      y = precip_total * escala_precip
    ),
    alpha = 0.7,
    fill = "lightblue"
  ) +
  
  scale_y_continuous(
    name = "Área total",
    
    sec.axis = sec_axis(
      ~ . / escala_pistas + offset,
      name = "Número de pistas",
      breaks = seq(200,400,50)
    )
  ) +
  
  scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y"
  ) +
  
  labs(
    title = "Área minerada, pistas ativas e precipitação",
    subtitle = paste(
      "Barras = área |",
      "Vermelho = pistas |",
      "Azul = precipitação"
    ),
    x = "Ano"
  ) +
  
  theme_bw() +
  
  theme(
    axis.text.x = element_text(
      angle = 45,
      hjust = 1
    )
  )

ggsave(
  "9_bfast_resultados/histogramas/gerais_pista/area_pistas_precip.png",
  p,
  width = 12,
  height = 6,
  dpi = 300,
  bg = "white"
)


###############################


resultados_razao <- resultados %>%
  distinct(id_pista, K, mes, area_mes) %>%
  left_join(plano %>% dplyr::select(id_pista, vline_inicio, vline_fim), by = "id_pista") %>%
  group_by(id_pista, K) %>%
  summarise(
    area_antes_inicio  = ifelse(
      !is.na(vline_inicio[1]),
      max(area_mes[mes > vline_inicio[1] - months(12) & 
                                         mes <= vline_inicio[1]], na.rm = TRUE),
      NA),
    area_depois_inicio = ifelse(
      !is.na(vline_inicio[1]),
             max(area_mes[mes > vline_inicio[1] & 
                                        mes <= vline_inicio[1] + months(12)], na.rm = TRUE),
      NA),
    area_antes_fim     = ifelse(
      !is.na(vline_fim[1]) & 
        as.numeric(difftime(max(mes), vline_fim[1], units = "days")) / 30 >= 6,
      median(area_mes[mes > vline_fim[1] - months(50) & mes <= vline_fim[1]], na.rm = TRUE),
      NA
    ),
    area_depois_fim    = ifelse(
      !is.na(vline_fim[1]) & 
        as.numeric(difftime(max(mes), vline_fim[1], units = "days")) / 30 >= 6,
      median(area_mes[mes > vline_fim[1] & mes <= vline_fim[1] + months(50)], na.rm = TRUE),
      NA
    ),
    .groups = "drop"
  )
  # mutate(
  #   area_antes_inicio  = ifelse(area_antes_inicio  == 0, 0.001, area_antes_inicio),
  #   area_depois_inicio = ifelse(area_depois_inicio == 0, 0.001, area_depois_inicio),
  #   area_antes_fim     = ifelse(area_antes_fim     == 0, 0.001, area_antes_fim),
  #   area_depois_fim    = ifelse(area_depois_fim    == 0, 0.001, area_depois_fim),
  #   razao_area_inicio = log(area_depois_inicio / area_antes_inicio),
  #   razao_area_fim    = log(area_depois_fim    / area_antes_fim)
  # )

# Atualiza resultados_anotados
resultados_anotados_2 <- resultados_anotados %>%
  left_join(resultados_razao, by = c("id_pista", "K"))




bw <- 1

dados_razao <- resultados_anotados_2 %>%
  filter(!is.na(razao_area_inicio), K == 4) %>%
  pull(razao_area_inicio)

# Cria os dados do histograma como tibble
hist_data <- tibble(x = dados_razao) %>%
  mutate(faixa = cut(x, breaks = seq(min(x), max(x), by = bw), right = FALSE)) %>%
  count(faixa) %>%
  mutate(x_mid = seq(min(dados_razao) + bw/2, max(dados_razao) - bw/2, 
                     length.out = n()))

# Fita exponencial nos pontos do histograma
fit <- nls(n ~ a * exp(b * x_mid), 
           data = hist_data, 
           start = list(a = 0.1, b = 0.2))

curva_exp <- tibble(
  x = seq(min(dados_razao), max(dados_razao), length.out = 300),
  y = predict(fit, newdata = tibble(x_mid = x))
)

p_inicio <- ggplot(tibble(x = dados_razao), aes(x = x)) +
  geom_histogram(binwidth = bw, fill = "#1976D2", color = "white", alpha = 0.7) +
  geom_line(data = curva_exp, aes(x = x, y = y), color = "red", linewidth = 1) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red", linewidth = 0.8) +
  labs(
    title = "Distribuição da razão de início",
    x     = "log(razão início)  —  positivo = mineração veio depois da pista",
    y     = "Número de pistas"
  ) +
  theme_bw()

p_inicio

file_name <- paste0("9_bfast_resultados/histograma_inicio_K4.png")
ggsave(file_name, p_inicio, width = 8, height = 6, dpi = 300, bg = "white")


# Calcula parâmetros sem outliers
dados_fim_core <- dados_razao_fim[abs(dados_razao_fim) <= 10]

media_fim <- mean(dados_fim_core)
dp_fim    <- sd(dados_fim_core)
n_fim     <- length(dados_razao_fim)  # mantém n total para escala correta

curva_normal_fim <- tibble(
  x = seq(min(dados_razao_fim), max(dados_razao_fim), length.out = 300),
  y = dnorm(x, mean = media_fim, sd = dp_fim) * n_fim * bw
)

p_fim <- resultados_anotados %>%
  mutate(
    razao_area_fim = ifelse(is.infinite(razao_area_fim),
                            sign(razao_area_fim) * 10, razao_area_fim)
  ) %>%
  filter(!is.na(razao_area_fim), K == 4) %>%
  ggplot(aes(x = razao_area_fim)) +
  geom_histogram(binwidth = bw, fill = "#1976D2",
                 color = "white", alpha = 0.8) +
  geom_line(data = curva_normal_fim, aes(x = x, y = y), color = "red", linewidth = 1) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "red", linewidth = 0.8) +
  labs(
    title = "Distribuição da razão de fim",
    x     = "log(razão fim)  —  negativo = atividade caiu após o fim",
    y     = "Número de pistas"
  ) +
  theme_bw() +
  theme(legend.position = "bottom")

file_name <- paste0("9_bfast_resultados/histograma_final_K4.png")
ggsave(file_name, p_fim, width = 8, height = 6, dpi = 300, bg = "white")
