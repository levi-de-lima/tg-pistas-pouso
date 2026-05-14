library(spatialEco)
library(ggplot2)
library(mapview)
library(terra)
library(sf)
library(dplyr)
library(tidyverse)
library(cowplot)

GFW_raw <- read_sf("6_gfw/GFW_dist.gpkg")
Deter_before <- read_sf("7_alertas_before/deter_dist.gpkg") %>% filter(doy < "2019-01-02")
base_pistas <- read_sf("5_base_final/base_pistas_final.gpkg", layer="pontos")

GFW <- bind_rows(GFW_raw, Deter_before)


# Lookup table de validade por pista
pistas_validade <- base_pistas %>%
  st_drop_geometry() %>%
  select(id_pista, start_date, end_date)

sf_vline <- base_pistas %>%
  mutate(
    # início
    vline_inicio = start_date,
    
    # fim = menor entre inpop_date e end_date
    vline_fim = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim) %>% 
  mutate(id_pista = as.factor(id_pista))

sf_vline_long <- sf_vline %>%
  pivot_longer(
    cols = c(vline_inicio, vline_fim),
    names_to = "tipo",
    values_to = "xintercept"
  )

# === Pré-processamento: faz UMA vez ===
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

# === Função: processa uma curva para um K específico ===
processa_K <- function(GFW_long_input, id, K) {
  
  # 1. Agrupa e calcula o acumulado original
  df_temp <- GFW_long_input %>%
    filter(pista == id, rank_novo <= K, dist <= 6000) %>%
    group_by(doy) %>%
    summarise(area = sum(area), .groups = "drop") %>%
    arrange(doy) %>%
    mutate(area = cumsum(area))
  
  # Salva a data máxima para o complete
  data_ultima <- max(df_temp$doy)
  
  df_temp %>%
    # 2. Expande a série temporal desde 2016
    complete(
      doy = seq(as.Date("2016-01-01"), data_ultima, by = "day")
    ) %>%
    # 3. Interpolação Linear
    mutate(
      area = approx(
        x = doy[!is.na(area)], 
        y = area[!is.na(area)], 
        xout = doy, 
        method = "linear", 
        rule = 2 # rule = 2 repete o valor mínimo para trás e o máximo para frente
      )$y
    ) %>%
    # 4. Formata a legenda
    mutate(
      K = factor(
        paste0("K = ", K), 
        levels = c("K = 1", "K = 4")
      )
    )
}

# === Loop ===
Ks <- c(1, 4)

for (i in base_pistas$id_pista) {
  id <- i
  cat("\nProcessando id_pista:", id, "\n")
  
  # Roda os 3 Ks e empilha
  sf_plot <- bind_rows(lapply(Ks, function(K) processa_K(GFW_long, id, K)))
  
  sf_pista <- sf_vline_long %>% filter(id_pista == id, !is.na(xintercept))
  
  graph <- ggplot(sf_plot, aes(x = doy, y = area, color = K)) +
    geom_line(linewidth = 0.7) +
    geom_vline(
      data = sf_pista,
      aes(xintercept = as.numeric(xintercept), linetype = tipo),
      color = "gray30"
    ) +
    scale_color_manual(values = c(
      "K = 1" = "#1976D2",
      "K = 4" = "#D32F2F"
    )) +
    labs(color = "Granularidade", linetype = "Marco") +
    theme(legend.position = "right")
  
  windrose_path <- paste0("6_gfw/all_wind_2/pista_", id, "_data.png")
  graph_final <- ggdraw(graph) +
    draw_image(windrose_path, x = 0.05, y = 0.55, width = 0.45, height = 0.45)
  
  file_name <- paste0("6_gfw/compound_graphs/pista_", id, "_data.png")
  ggsave(file_name, graph_final, width = 8, height = 6, dpi = 300, bg = "white")
}

# write_sf(sf_plot, "data/processed/GFW_pistas_plot.gpkg")