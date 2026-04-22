library(spatialEco)
library(ggplot2)
library(openxlsx)
library(mapview)
library(terra)
library(sf)
library(tidyverse)

# O objetivo deste script é definir um buffer aceitável de distância das pistas de pouso em que se pode dizer que um
# determinado evento de mineração está relacionado a ela
#
# Para isso, vou fazer um análise com windrose plots, a ideia é, para cada pista, ter dois windrose plots, 
# um cujas cores representam os anos e outro cujas cores representam a área minerada
#
# Antes disso, duas coisas precisam ser feitas:
# 1. Obter um arquivo gpkg do GFW retirados os polígonos que não são de mineração
# 2. Escolher 10 pistas representativas para essa análise (separar 10 ids)

area_estudo <- read_sf("1_fontes/area_estudo/area_de_estudo.gpkg")

Deter_cropped <- read_sf("1_fontes/deter/Deter_cropped.gpkg")

Deter_non_miner <- Deter_cropped %>% filter(CLASSNAME != "MINERACAO")

GFW <- read_sf("6_gfw/GFW_binded.gpkg")

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

GFW <- read_sf("4_analise_comparativa/Alerts/GWF_sel.gpkg") %>% 
  mutate(semestre = ifelse(month(DATE) <= 6, 1, 2), ano_sem = as.double(YEAR) + (semestre - 1)/2) %>% 
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

pistas_polig <- read_sf("5_base_final/base_pistas_final.gpkg", layer="poligonos")
pistas_ponto <- read_sf("5_base_final/base_pistas_final.gpkg", layer="pontos")

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

buffer_lim <- 5000

# Loop por pista — cada iteração gera dois windrose plots
for (i in ids) {
  id <- i
  
  pista_pt      <- pistas_ponto %>% filter(id_pista == 11) %>% st_transform(31981)
  pista_dir_val <- pista_pt$pista_dir
  
  # Distância e Ângulo
  GFW_c$dist <- as.numeric(st_distance(GFW_c$centroid, pista_pt %>% st_transform(4674)))
  
  coords_gfw <- st_coordinates(GFW_c$centroid %>% st_transform(31981))
  coords_pt  <- st_coordinates(pista_pt)
  
  dx <- coords_gfw[, 1] - coords_pt[1, 1]
  dy <- coords_gfw[, 2] - coords_pt[1, 2]
  
  GFW_c$angulo <- atan2(dy, dx) * 180 / pi
  GFW_c$angulo[GFW_c$angulo < 0] <- GFW_c$angulo[GFW_c$angulo < 0] + 360
  
  # Ângulo relativo à orientação da pista
  GFW_c$angulo_rel <- (GFW_c$angulo - pista_dir_val) %% 360
  
  # --- PREPARAÇÃO DOS DADOS PARA O PLOT ---
  # Definimos intervalos de 1000m para as faixas (anéis)
  breaks_dist <- seq(0, buffer_lim, by = 1000)
  
  GFW_plot_agregado <- GFW_c %>%
    st_drop_geometry() %>%
    filter(dist <= buffer_lim) %>%
    mutate(
      ang_bin  = cut(angulo_rel, breaks = seq(0, 360, by = 15), 
                     labels = paste0(seq(0, 345, 15), "°"), include.lowest = TRUE),
      dist_bin = cut(dist, breaks = breaks_dist, include.lowest = TRUE)
    ) %>%
    group_by(ang_bin, dist_bin) %>% # Agrupamos também por semestre para o P1
    summarise(area_total = sum(area), data = mean(DATE), .groups = "drop") %>%
    # Garante que todas as fatias existam no dataframe (mesmo vazias)
    complete(ang_bin, dist_bin, fill = list(area_total = 0))
  
  # Plot 1: Raio = Distância | Cor = Semestre (Mais recente sobrepõe ou escala de tempo)
  # Nota: Como o raio é a distância, se houver vários semestres no mesmo bin, 
  # eles vão se "empilhar" dentro daquela faixa de distância.
  p1 <- ggplot(GFW_plot_agregado, aes(x = ang_bin, y = 1000, fill = data)) +
    geom_col(position = "stack", color = "white", linewidth = 0.2) +
    coord_polar(start = -pi / 2) +
    scale_y_continuous(breaks = breaks_dist) + 
    # scale_fill_date é a função específica para o tipo Date
    scale_fill_date(
      high = "#00264D",    # Cor para as datas mais antigas (Escuro)
      low = "#c6dbef",   # Cor para as datas mais recentes (Claro)
      na.value = "white", # NAs em branco
      # date_labels = "%Y-%m" 
    ) +
    labs(title = paste("Pista", id, "– Distância por Data"),
         subtitle = "Cada anel representa 1km de distância",
         fill = "Data", x = NULL, y = "Distância (m)") +
    theme_minimal()
  
  # Plot 2: Raio = Distância | Cor = Intensidade da Área (Gradiente)
  # Aqui agrupamos por bin de distância ignorando o semestre para ver a massa total
  GFW_plot_area <- GFW_plot_agregado %>%
    group_by(ang_bin, dist_bin) %>%
    summarise(area_total_bin = sum(area_total), .groups = "drop")
  
  p2 <- ggplot(GFW_plot_area, aes(x = ang_bin, y = 1000, fill = area_total_bin)) +
    geom_col(position = "stack", color = "white", linewidth = 0.2) +
    coord_polar(start = -pi / 2) +
    scale_y_continuous(breaks = breaks_dist) +
    scale_fill_gradient(low = "#f7f7f7", high = "#bd0026", name = "Área Total", trans="log10", na.value="white") +
    labs(title = paste("Pista", id, "– Distância por Área Minerada"),
         subtitle = "Cada anel representa 1km de distância",
         x = NULL, y = "Distância (m)") +
    theme_minimal()
  
  print(p1)
  print(p2)
}
