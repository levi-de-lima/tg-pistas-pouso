library(spatialEco)
library(ggspatial)
library(ggplot2)
library(openxlsx)
library(mapview)
library(terra)
library(sf)
library(tidyverse)
library(RColorBrewer)

# O objetivo deste script é definir um buffer aceitável de distância das pistas de pouso em que se pode dizer que um
# determinado evento de mineração está relacionado a ela
#
# Para isso, vou fazer um análise com windrose plots, a ideia é, para cada pista, ter dois windrose plots, 
# um cujas cores representam os anos e outro cujas cores representam a área minerada
#
# Antes disso, duas coisas precisam ser feitas:
# 1. Obter um arquivo gpkg do GFW retirados os polígonos que não são de mineração
# 2. Escolher 10 pistas representativas para essa análise (separar 10 ids)

area_estudo <- read_sf("dados/mestres/area_estudo/area_de_estudo.gpkg")

Deter_cropped <- read_sf("dados/brutos/deter/Deter_cropped.gpkg")

Deter_non_miner <- Deter_cropped %>% filter(CLASSNAME != "MINERACAO")

GFW <- read_sf("dados/derivados/gfw/GFW_binded.gpkg")

GFW_filtered <- st_filter(GFW, Deter_non_miner, .predicate = st_disjoint)

# 1. Foi feito no QGIS
# 2. As pistas serão observadas usando o QGIS
#   As pistas 11, 12, 13 e 2432 do tile C63L51 serão incluídas
#   Deve-se escolher pistas em regiões com pouca mineração, 
#   com muita mineração e com alta densidade de pistas próximas
#   Escolher pistas com alta variedade de datas (início, fim, inop)
#
# Pistas: 25; 2407; 2406; 176; 2350; 72262

ids <- c(11, 12, 13, 25, 176, 196, 192, 2350, 2406, 2407, 2432, 2463, 2546, 2550, 72262)

GFW_raw <- read_sf("dados/derivados/gfw/GFW_final.gpkg") 
GFW <- GFW_raw %>% 
  # mutate(semestre = ifelse(month(DATE) <= 6, 1, 2), ano_sem = as.double(YEAR) + (semestre - 1)/2) %>% 
  st_transform(31981) %>% 
  mutate(area = as.double(st_area(geom))) %>% 
  st_transform(4674)

# Preparando a windrose:
# 1. Distâncias do círculos concêntricos: 1000 - 2000 - 3000 - 4000 - 5000 km
# 2. Direção do polígono em relação a pista: 
#   Centroide de ambos -> linha entre os centroides -> angulo
#   De 45 em 45º
# 3. Cores: Soma das área naquele range de ângulo; Semestre em que foi medida aquela observação
# O que precisarei:
#   GFW -> ano_sem, area, GEOMETRY(CENTROID)
#   Pistas -> Já tenho o dotted
# Adiocionalmente: adicionar no meio do gráfico a direção da pista -> não tenho ainda
#   Como calcular a direção da pista? -> PCA
#   Quando calculado adionar uma coluna com essa direção no dotted

GFW_raw <- read_sf("dados/derivados/gfw/GFW_dist.gpkg")
Deter_before <- read_sf("dados/derivados/deter_retroativo/deter_dist.gpkg") %>% dplyr::filter(doy < "2019-01-02")
base_pistas <- read_sf("dados/mestres/base_pistas_final.gpkg", layer="pontos")

GFW <- bind_rows(GFW_raw, Deter_before)

pistas_polig <- read_sf("dados/mestres/base_pistas_final.gpkg", layer="poligonos")
pistas_ponto <- read_sf("dados/mestres/base_pistas_final.gpkg", layer="pontos")

calc_orientacao <- function(geom) {
  # extrai coordenadas
  coords <- st_coordinates(geom)[, 1:2]
  
  # PCA
  pca <- prcomp(coords, center = TRUE, scale. = FALSE)
  
  # vetor principal
  v <- pca$rotation[,1]
  
  # ângulo em radianos
  ang <- atan2(v[2], v[1])
  
  # converte para graus (0–180)
  ang_deg <- ang * 180 / pi
  
  if (ang_deg < 0) ang_deg <- ang_deg + 180
  
  return(ang_deg)
}

pistas_ponto$pista_dir <- sapply(pistas_polig %>% st_transform(31981) %>% st_geometry, calc_orientacao)

# Centroides do GFW
GFW_c <- GFW %>% mutate(centroid = st_centroid(geom))

buffer_lim <- 6000

nearest <- st_nearest_feature(GFW_c %>% st_transform(31981), pistas_ponto %>% st_transform(31981))

GFW_pp <- GFW_c %>% 
  st_transform(31981) %>% 
  mutate(pista_proxima = as.factor(pistas_ponto$id_pista[nearest])) %>% 
  st_transform(4674)

moda <- function(x) {
  x <- na.omit(x)
  if (length(x) == 0) return(NA)
  
  tab <- table(x)
  # Retorna o valor como factor preservando os níveis originais
  factor(names(tab)[which.max(tab)], levels = levels(x))
}

rios <- read_sf("dados/derivados/base_final/curso_dagua.gpkg") %>% st_transform(4674)

for (i in pistas_ponto$id_pista[144:length(pistas_ponto$id_pista)]) {
  cat("\n============================\n")
  cat("Iniciando ID:", i, "\n")
  
  id <- i
  
  cat("→ Filtrando pista\n")
  pista_pt      <- pistas_ponto %>% filter(id_pista == i) %>% st_transform(31981)
  # pista_dir_val <- pista_pt$pista_dir
  
  cat("→ Calculando distância\n")
  
  GFW_filtered <- GFW %>%
    filter({
      p <- across(starts_with("pista_")) %>% as.matrix()
      d <- across(starts_with("dist_"))  %>% as.matrix()
      rowSums((p == id) & (d <= 6000), na.rm = TRUE) > 0
    })
  
  GFW_filtered$dist <- as.numeric(st_distance(GFW_filtered$geom, pista_pt %>% st_transform(4674)))
  GFW_filtered$doy <- as.Date(GFW_filtered$doy)
  
  cat("→ Calculando ângulos\n")
  coords_pt  <- st_coordinates(pista_pt)
  coords_gfw <- st_coordinates(GFW_filtered$geom %>% st_transform(31981))
  
  dx <- coords_gfw[, 1] - coords_pt[1, 1]
  dy <- coords_gfw[, 2] - coords_pt[1, 2]
  
  GFW_filtered$angulo <- atan2(dy, dx) * 180 / pi
  GFW_filtered$angulo[GFW_filtered$angulo < 0] <- GFW_filtered$angulo[GFW_filtered$angulo < 0] + 360
  
  # cat("→ Calculando ângulo relativo\n")
  # GFW_filtered$angulo_rel <- (GFW_filtered$angulo - pista_dir_val) %% 360
  
  cat("→ Preparando dados para plot\n")
  breaks_dist <- seq(0, buffer_lim, by = 1000)
  
  GFW_plot_agregado <- GFW_filtered %>%
    st_drop_geometry() %>%
    filter(dist <= buffer_lim) %>%
    mutate(
      ang_bin  = cut(angulo, breaks = seq(0, 360, by = 15), 
                     labels = paste0(seq(0, 345, 15), "°"), include.lowest = TRUE),
      dist_bin = cut(dist, breaks = breaks_dist, include.lowest = TRUE)
    ) %>%
    group_by(ang_bin, dist_bin) %>%
    summarise(area_total = sum(area), data = mean(doy), pp = moda(pista_1), .groups = "drop") %>%
    complete(ang_bin, dist_bin, fill = list(area_total = 0))
  
  cat("→ Preparando hidrografia\n")
  
  buffer_pista <- st_buffer(pista_pt, buffer_lim)
  rios_clip <- st_intersection(rios %>% st_transform(31981), buffer_pista) %>% 
    st_collection_extract("LINE") %>% 
    st_cast("LINESTRING") %>%
    st_segmentize(dfMaxLength = 50)   # <-- ÚNICA mudança: densifica a cada 50m
  
  rios_coords <- st_coordinates(rios_clip) %>%
    as.data.frame() %>%
    mutate(
      dx      = X - coords_pt[1, 1],
      dy      = Y - coords_pt[1, 2],
      dist    = sqrt(dx^2 + dy^2),
      angulo  = atan2(dy, dx) * 180 / pi,
      angulo  = ifelse(angulo < 0, angulo + 360, angulo),
      # ang_rel = (angulo - pista_dir_val) %% 360,
      x_plot  = angulo / 15 + 1,
      # [MUDANÇA 1] limite do wrap: 24 -> 24.5
      # garante x_plot ∈ [0.5, 24.5] = mesmo range das colunas do geom_col(width=1)
      x_plot  = ifelse(x_plot > 24.5, x_plot - 24, x_plot)
    ) %>%
    group_by(L1) %>%
    group_modify(~ {
      df <- .x
      if (nrow(df) < 2) {
        df$grupo <- paste(.y$L1, 0, sep = "_"); return(df)
      }
      dx <- abs(df$x_plot - lag(df$x_plot, default = first(df$x_plot)))
      salto_idx <- which(dx > 12)
      if (length(salto_idx) == 0) {
        df$grupo <- paste(.y$L1, 0, sep = "_"); return(df)
      }
      # [MUDANÇA 2] insere pontos virtuais nos limites (24.5 e 0.5)
      # com dist interpolada, preservando a continuidade do rio onde cruza 0°
      novos <- list(); sub <- 0L
      df$subgrupo <- 0L
      for (i in 2:nrow(df)) {
        if (i %in% salto_idx) {
          x_prev <- df$x_plot[i - 1]; x_curr <- df$x_plot[i]
          d_prev <- df$dist[i - 1];   d_curr <- df$dist[i]
          if (x_prev > x_curr) {
            x1_lim <- 24.5; x2_lim <- 0.5
            dist_total <- (24.5 - x_prev) + (x_curr - 0.5)
            frac1 <- (24.5 - x_prev) / dist_total
          } else {
            x1_lim <- 0.5; x2_lim <- 24.5
            dist_total <- (x_prev - 0.5) + (24.5 - x_curr)
            frac1 <- (x_prev - 0.5) / dist_total
          }
          d_interp <- d_prev + (d_curr - d_prev) * frac1
          novos[[length(novos) + 1]] <- data.frame(
            dist = d_interp, x_plot = x1_lim, subgrupo = sub, .pos = i - 0.6
          )
          sub <- sub + 1L
          novos[[length(novos) + 1]] <- data.frame(
            dist = d_interp, x_plot = x2_lim, subgrupo = sub, .pos = i - 0.4
          )
          df$subgrupo[i] <- sub
        } else {
          df$subgrupo[i] <- sub
        }
      }
      df$.pos <- seq_len(nrow(df))
      out <- bind_rows(df, bind_rows(novos)) %>%
        arrange(.pos) %>%
        select(-.pos)
      out$grupo <- paste(.y$L1, out$subgrupo, sep = "_")
      out
    }) %>%
    ungroup()
  
  camada_rios <- geom_path(
    data = rios_coords,
    aes(x = x_plot, y = dist, group = grupo),
    color = "#006064",
    linewidth = 0.4,
    inherit.aes = FALSE
  )
  
  cat("→ Preparando pistas no buffer\n")
  
  pistas_clip <- pistas_ponto %>%
    st_transform(31981) %>%
    filter(as.numeric(st_distance(geom, pista_pt)) <= buffer_lim)
  
  pistas_coords <- st_coordinates(pistas_clip) %>%
    as.data.frame() %>%
    mutate(
      dx      = X - coords_pt[1, 1],
      dy      = Y - coords_pt[1, 2],
      dist    = sqrt(dx^2 + dy^2),
      angulo  = atan2(dy, dx) * 180 / pi,
      angulo  = ifelse(angulo < 0, angulo + 360, angulo),
      # ang_rel = (angulo - pista_dir_val) %% 360,
      x_plot  = angulo / 15 + 1,
      x_plot  = ifelse(x_plot > 24.5, x_plot - 24, x_plot),   # <-- ÚNICA mudança
      id_pista = pistas_clip$id_pista
    )
  
  camada_pistas <- list(
    # Ponto
    geom_point(
      data = pistas_coords,
      aes(x = x_plot, y = dist), 
      color = "#1A237E",
      size  = 2.6,
      inherit.aes = FALSE
    )
  )
  
  cat("→ Gerando Plot 1\n")
  p1 <- ggplot(GFW_plot_agregado, aes(x = ang_bin, y = 1000, fill = data)) +
    geom_col(position = "stack", color = "white", linewidth = 0.2, width = 1) +
    coord_polar(start = -pi / 2, direction=-1) +
    scale_y_continuous(breaks = breaks_dist, limits = c(0, buffer_lim)) + 
    scale_fill_date(
      high = "#33691E",
      low = "#F9FBE7",
      na.value = "white"
    ) +
    labs(title = NULL, subtitle = NULL, fill = NULL, x = NULL, y = NULL) +  # remove títulos e eixo y
    theme_minimal() +
    theme(
      legend.position    = "bottom",
      legend.direction   = "horizontal",
      legend.key.width   = unit(2.4, "cm"),     # estende a barra
      legend.key.height  = unit(0.35, "cm"),    # opcional, deixa a barra mais "fina" e elegante
      legend.box.spacing = unit(0, "pt"),       # remove o espaço padrão entre plot e legenda
      legend.margin      = margin(t = -10, b = 0, l = 0, r = 0)  # sobe a legenda em direção ao plot
    ) + 
    annotation_north_arrow(location = "tl", which_north = "true",
                           height = unit(1, "cm"), width = unit(1, "cm"),
                           pad_x = unit(1,"cm"), pad_y = unit(1,"cm"))
  
  cat("→ Salvando imagens\n")
  ggsave(paste0("resultados/figuras/windroses/pista_", id, "_data.png"), p1+camada_pistas+camada_rios, width = 8, height = 6, dpi = 300, bg = "transparent")
  
  cat("→ Exibindo plots\n")
  print(p1+camada_rios+camada_pistas)
  
  cat("Finalizado ID:", i, "\n")
}
