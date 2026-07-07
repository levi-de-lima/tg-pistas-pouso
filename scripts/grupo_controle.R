library(terra)
library(sf)
library(dplyr)
library(lubridate)
library(terra)
library(dbscan)

###############################
# Deter      ##################
###############################

# 1. Carregamento e Preparação dos Dados Raster
area_estudo <- read_sf("1_fontes/area_estudo/area_de_estudo.gpkg") %>% st_make_valid()
Deter_raw <- read_sf("1_fontes/deter/deter_orignal/deter_orig.gpkg") 
sf::sf_use_s2(FALSE)
Deter_cropped <- Deter_raw %>% st_intersection(area_estudo) %>% filter(CLASSNAME == "MINERACAO")
sf::sf_use_s2(TRUE)

Deter <- Deter_cropped %>% 
  rename(doy = VIEW_DATE) %>% 
  mutate(year = year(doy)) %>% 
  select(doy, year, geom)

Deter_2016 <- Deter %>% filter(year == 2016)

Deter_2017 <- Deter %>% filter(year == 2017)
Deter_2018 <- Deter %>% filter(year == 2018)
Deter_2019 <- Deter %>% filter(year == 2019)
Deter_2020 <- Deter %>% filter(year == 2020)
Deter_2021 <- Deter %>% filter(year == 2021)
Deter_2022 <- Deter %>% filter(year == 2022)
Deter_2023 <- Deter %>% filter(year == 2023)
Deter_2024 <- Deter %>% filter(year == 2024)

Deter_2017_acum <- Deter %>% filter(doy < "2018-01-01")
Deter_2018_acum <- Deter %>% filter(doy < "2019-01-01")
Deter_2019_acum <- Deter %>% filter(doy < "2020-01-01")
Deter_2020_acum <- Deter %>% filter(doy < "2021-01-01")
Deter_2021_acum <- Deter %>% filter(doy < "2022-01-01")
Deter_2022_acum <- Deter %>% filter(doy < "2023-01-01")
Deter_2023_acum <- Deter %>% filter(doy < "2024-01-01")
Deter_2024_acum <- Deter %>% filter(doy < "2025-01-01")

Deter_2025 <- Deter %>% filter(year == 2025)

sf_use_s2(FALSE)
Deter_2017_dif <- st_difference(Deter_2017, st_union(Deter_2016))
Deter_2018_dif <- st_difference(Deter_2018, st_union(Deter_2017_acum))
Deter_2019_dif <- st_difference(Deter_2019, st_union(Deter_2018_acum))
Deter_2020_dif <- st_difference(Deter_2020, st_union(Deter_2019_acum))
Deter_2021_dif <- st_difference(Deter_2021, st_union(Deter_2020_acum))
Deter_2022_dif <- st_difference(Deter_2022, st_union(Deter_2021_acum))
Deter_2023_dif <- st_difference(Deter_2023, st_union(Deter_2022_acum))
Deter_2024_dif <- st_difference(Deter_2024, st_union(Deter_2023_acum))
Deter_2025_dif <- st_difference(Deter_2025, st_union(Deter_2024_acum))
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

write_sf(deter_area %>% select(doy, area, geom), "5_base_final/grupo_controle/deter_controle.gpkg")

###############################
# MapBiomas      ##############
###############################

MapBiomas_raw <- read_sf("1_fontes/mapbiomas/MapBiomas_ALB.gpkg")
sf::sf_use_s2(FALSE)
MB_cropped <- MapBiomas_raw %>% st_transform(4674) %>% 
  st_intersection(area_estudo) %>% filter(VPRESSAO == "mining" | VPRESSAO == "ilegal_mining")
sf::sf_use_s2(TRUE)

MapBiomas <- MB_cropped %>% 
  rename(doy = DATADETEC) %>% 
  mutate(year = year(doy)) %>% 
  select(doy, year, geom)

sf_use_s2(FALSE)
mapbiomas_area <- MapBiomas %>% 
  st_transform(31981) %>% 
  mutate(area = as.numeric(st_area(geom))) %>% 
  st_transform(4674) %>% 
  st_make_valid() %>% 
  filter(!st_is_empty(geom))
sf_use_s2(TRUE)

write_sf(mapbiomas_area %>% select(doy, area, geom), "5_base_final/grupo_controle/mapbiomas_controle.gpkg")

###############################
# GFW & final      ############
###############################

gfw <- read_sf("mask_only_miner_gfw.gpkg")

sf_use_s2(FALSE)
gfw_area <- gfw %>% 
  st_transform(31981) %>% 
  mutate(area = as.numeric(st_area(geom))) %>% 
  st_transform(4674) %>% 
  st_make_valid() %>% 
  filter(!st_is_empty(geom))
sf_use_s2(TRUE)

write_sf(gfw_area, "5_base_final/grupo_controle/gfw_controle.gpkg")

final <- bind_rows(
  gfw = gfw_area,
  mapbiomas = mapbiomas_area,
  deter = deter_area,
  .id = "fonte"
)

write_sf(final, "5_base_final/grupo_controle/final_controle.gpkg")

final_controle <- read_sf("5_base_final/grupo_controle/final_controle.gpkg")

base_pistas  <- read_sf("5_base_final/base_pistas_final.gpkg", layer = "pontos")

pistas_buffer <- base_pistas %>% 
  st_transform(31981) %>% 
  st_buffer(6000) %>% 
  st_transform(4674)

write_sf(pistas_buffer, "5_base_final/grupo_controle/pistas_buffer.gpkg")

sf_use_s2(FALSE)
controle_non_buffer <- st_difference(final_controle, pistas_buffer)
sf_use_s2(TRUE)

write_sf(controle_non_buffer, "5_base_final/grupo_controle/non_buffer_controle.gpkg")
