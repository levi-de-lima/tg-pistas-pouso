library(terra)
library(sf)
library(dplyr)
library(lubridate)
library(terra)
library(dbscan)

# 1. Carregamento e Preparação dos Dados Raster
area_estudo <- read_sf("1_fontes/area_estudo/area_de_estudo.gpkg")
Deter_raw <- read_sf("1_fontes/deter/Deter_before.gpkg") %>% st_intersection(area_estudo) %>% filter(CLASSNAME == "MINERACAO")

Deter <- Deter_raw %>% 
  rename(fid = fidao, doy = VIEW_DATE) %>% 
  select(doy, year, geom)

Deter_2016 <- Deter %>% filter(year == 2016)

Deter_2017 <- Deter %>% filter(year == 2017)
Deter_2018 <- Deter %>% filter(year == 2018)

Deter_2017_acum <- Deter %>% filter(doy < "2018-01-01")
Deter_2018_acum <- Deter %>% filter(doy < "2019-01-01")

Deter_2019 <- Deter %>% filter(year == 2019)

sf_use_s2(FALSE)
Deter_2017_dif <- st_difference(Deter_2017, st_union(Deter_2016))
Deter_2018_dif <- st_difference(Deter_2018, st_union(Deter_2017_acum))
Deter_2019_dif <- st_difference(Deter_2019, st_union(Deter_2018_acum))
sf_use_s2(TRUE)

deter_final <- bind_rows(Deter_2016, Deter_2017_dif, Deter_2018_dif, Deter_2019_dif)

sf_use_s2(FALSE)
deter_area <- deter_final %>% 
  st_transform(31981) %>% 
  mutate(area = as.numeric(st_area(geom))) %>% 
  st_transform(4674) %>% 
  st_make_valid() %>% 
  filter(!st_is_empty(geom))
sf_use_s2(TRUE)

write_sf(deter_area %>% select(doy, area, geom), "7_alertas_before/deter.gpkg")

Deter_c <- deter_area %>% st_make_valid() %>% filter(!st_is_empty(geom)) %>% select(doy, area, geom) %>% mutate(geom = st_centroid(geom))

write_sf(Deter_c, "7_alertas_before/deter_centroides.gpkg")


Deter_c <- read_sf("7_alertas_before/deter_centroides.gpkg")

pistas_ponto <- read_sf("5_base_final/base_pistas_final.gpkg", layer="pontos")


coords_Deter_mat    <- st_coordinates(Deter_c %>% st_transform(31981))
coords_pistas_mat <- st_coordinates(pistas_ponto %>% st_transform(31981))

system.time(
  knn_result <- kNN(
    x     = coords_pistas_mat,
    query = coords_Deter_mat,
    k     = 7
  )
)

for (k in 1:7) {
  Deter_c[[paste0("pista_", k)]] <- as.factor(pistas_ponto$id_pista[knn_result$id[, k]])
  Deter_c[[paste0("dist_",  k)]] <- knn_result$dist[, k]
}

write_sf(Deter_c, "deter_dist.gpkg")
