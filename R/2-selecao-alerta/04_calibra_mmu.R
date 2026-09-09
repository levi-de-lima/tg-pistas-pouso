library(sf)
library(mapview)
library(tidyverse)
library(spatialEco)
library(ggplot2)

Planet <- read_sf("dados/mestres/planet/temp_series_dissolved.gpkg") %>% rename(DATE = data)
tile_C63L51 <- read_sf("dados/mestres/area_estudo/tiles_area_estudo.shp") %>% filter(id == "C63L51")

Deter <- read_sf("dados/brutos/alertas/Deter_sel.gpkg") %>% filter(id == "C63L51")
# GLADL <- read_sf("dados/brutos/alertas/GLADL_sel.gpkg") %>% st_intersection(tile_C63L51)
GLADS2 <- read_sf("dados/brutos/alertas/GLADS2_sel.gpkg") %>% st_intersection(tile_C63L51)
GWF <- read_sf("dados/brutos/alertas/GWF_sel.gpkg") %>% st_intersection(tile_C63L51)
LUCA <- read_sf("dados/brutos/alertas/LUCA_sel.gpkg") %>% st_intersection(tile_C63L51)
MapBiomas <- read_sf("dados/brutos/alertas/MapBiomas_sel.gpkg") %>% filter(id == "C63L51")
ProdesBefore <- read_sf("dados/brutos/alertas/Prodes_before_sel_class.gpkg") %>% st_intersection(tile_C63L51) %>% filter(CLASS %in% c("Deforestation_upto_2007", "yearly_deforestation"))
Prodes <- read_sf("dados/brutos/alertas/Prodes_sel.gpkg") %>% filter(id == "C63L51") %>% rename(DATE = image_date, YEAR = year)
RADD <- read_sf("dados/brutos/alertas/RADD_sel.gpkg") %>% st_intersection(tile_C63L51)
SAD <- read_sf("dados/brutos/alertas/SAD.gpkg") %>% st_intersection(tile_C63L51)
Tropisco <- read_sf("dados/brutos/alertas/Tropisco_sel.gpkg") %>% st_intersection(tile_C63L51)

GWF_filtered <- GWF %>%
  st_transform(31981) %>%
  st_buffer(50) %>% 
  sf_dissolve() %>% 
  st_buffer(-50) %>% 
  mutate(area = as.double(st_area(x))) %>%
  filter(area > 10000) %>% 
  st_transform(4674)

GWF_masked <- GWF %>%
  st_filter(GWF_filtered)

mapview(GWF, col.regions = "grey") +
  mapview(GWF_filtered, col.regions = "red")
