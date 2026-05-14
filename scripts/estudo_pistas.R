library(spatialEco)
library(ggplot2)
library(openxlsx)
library(mapview)
library(terra)
library(sf)
library(tidyverse)
library(webshot2)

pistas_xlsx <- read.xlsx("2_base_pistas/pistas.xlsx")
pistas_gpkg <- read_sf("2_base_pistas/base_pistas_atualizada.gpkg") %>% select(2,3,9,18)

pistas_shp <- read_sf("3_planet_orders/pistas_geometria/aois_417.shp")
ibge_shp <- read_sf("3_planet_orders/adicionais/aois_7.shp")
anac_shp <- read_sf("3_planet_orders/aois_4-08-04-2026-1510/aois_4.shp")

pistas_binded <- bind_rows(pistas_shp, anac_shp, ibge_shp)
rm(pistas_shp)
rm(ibge_shp)
rm(anac_shp)

pistas_binded$nome <- gsub("PIsta", "Pista", pistas_binded$nome)
pistas_binded$id_pista <- as.double(gsub("Pista\\s*", "", pistas_binded$nome))
pistas_binded_distinct <- pistas_binded %>% st_make_valid() %>% distinct(id_pista, .keep_all = TRUE) %>% st_transform(4674)
rm(pistas_binded)

base_pistas <- left_join(pistas_xlsx, pistas_gpkg, by = c("id_pista")) %>% 
  mutate(name = coalesce(name.y, name.x), Anac = coalesce(Anac.x, Anac.y)) %>% 
  select(-name.x, -name.y) %>% 
  select(-Anac.x, -Anac.y) %>% 
  relocate(name, .after = id_pista) %>% 
  relocate(Anac, .after = Dimas) %>% 
  filter(check==TRUE)
rm(pistas_xlsx)
rm(pistas_gpkg)

base_pistas <- base_pistas %>%
  mutate(
    start_date = as.Date(start_date),
    ano = year(start_date),
    semestre = if_else(month(start_date) <= 6, 1, 2),
    sd_ano_sem = ano + (semestre - 1) / 2
  ) %>% 
  select(-c(ano, semestre)) %>% 
  mutate(
    end_date = as.Date(end_date),
    inop_date = as.Date(inop_date),
    final_date = pmax(end_date, inop_date),
    ano = year(final_date),
    semestre = if_else(month(final_date) <= 6, 1, 2),
    fd_ano_sem = ano + (semestre - 1) / 2
  ) %>% 
  select(-c(ano, semestre)) %>% 
  st_as_sf() %>%
  st_transform(4674)

pistas_shp <- pistas_binded_distinct %>% select(c(id_pista, geometry))
pistas_dot <- base_pistas %>% select(-c(cluster_id, i, col, row, check, final_date)) %>% rename(nome = name, geometry = geom)
rm(base_pistas)
rm(pistas_binded_distinct)

# 1. Separar as 4 que não têm ponto
sem_ponto <- pistas_dot %>%
  filter(st_is_empty(geometry))

# 2. Calcular centroide dos polígonos correspondentes
centroides <- pistas_shp %>%
  filter(id_pista %in% sem_ponto$id_pista) %>%
  st_centroid() %>%
  select(id_pista, geometry)

# 3. Juntar os atributos das 4 com a nova geometria (centroide)
sem_ponto_corrigido <- sem_ponto %>%
  st_drop_geometry() %>%
  left_join(centroides, by = "id_pista") %>%
  st_as_sf()

# 4. Remontar o pistas_dot completo
pistas_dot_final <- pistas_dot %>%
  filter(!st_is_empty(geometry)) %>%
  bind_rows(sem_ponto_corrigido)

rm(centroides, pistas_dot, sem_ponto, sem_ponto_corrigido)

pistas_shp_final <- pistas_dot_final %>%
  st_drop_geometry() %>%                              # tira o ponto
  left_join(
    pistas_shp %>% select(id_pista, geometry),        # só a geometria do polígono
    by = "id_pista"
  ) %>%
  st_as_sf()                                          # reconstrói como sf com polígono

# Buffer 2km (métrico) → volta pra 4674 pra visualizar
pistas_buffer <- pistas_dot_final %>%
  st_transform(31981) %>%
  st_buffer(1000) %>%
  st_transform(4674)

# Para cada buffer, quais pontos caem dentro? (excluindo a própria pista)
pares <- st_join(
  pistas_buffer %>% select(id_pista),
  pistas_dot_final %>% select(id_pista),
  suffix = c("_buffer", "_ponto")
) %>%
  st_drop_geometry() %>%
  filter(id_pista_buffer != id_pista_ponto,
         id_pista_buffer < id_pista_ponto) %>%  # pares únicos
  distinct()

print(pares)


ids <- pistas_dot_final$id_pista
output_dir <- "5_base_final/screenshots/"
buffer_m <- 500  # ajuste o raio do buffer aqui

for (id in ids[372:length(ids)]) {
  pista_id <- id
  
  pista_dot <- pistas_dot_final %>% filter(id_pista == pista_id)
  pista_shp <- pistas_shp_final %>% filter(id_pista == pista_id)
  
  # Buffer define o extent do mapa
  zoom_extent <- pista_dot %>%
    st_transform(31981) %>%
    st_buffer(buffer_m) %>%
    st_transform(4674)
  
  # Camada invisível de zoom + pistas por cima
  m <- mapview(zoom_extent,
               alpha = 0, alpha.regions = 0,
               map.types = "Esri.WorldImagery", legend = FALSE) +
    mapview(pista_shp,
            color = "magenta", alpha.regions = 0, lwd = 2, legend = FALSE)
  
    mapshot2(m,
             file = paste0(output_dir, "Pista_", id, ".png"),
             remove_controls = c("homeButton", "layersControl"))
    print(paste("Concluído:", id))
}

pistas_dot_ilegais <- pistas_dot_final %>% filter(Anac == 0)
pistas_shp_ilegais <- pistas_shp_final %>% filter(Anac == 0)

pistas_dot_sd <- pistas_dot_ilegais %>% filter(!is.na(pistas_dot_ilegais$start_date))
pistas_shp_sd <- pistas_shp_ilegais %>% filter(!is.na(pistas_shp_ilegais$start_date))

mapview(pistas_dot_sd)

write_sf(pistas_dot_final %>% arrange(id_pista), "5_base_final/base_pistas_final.gpkg", layer = "pontos")
write_sf(pistas_shp_final %>% arrange(id_pista), "5_base_final/base_pistas_final.gpkg", layer = "poligonos", append = TRUE)
