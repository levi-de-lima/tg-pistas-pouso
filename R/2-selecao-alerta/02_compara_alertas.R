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

names <- list("Deter", "GLADS2", "GWF", "LUCA", "MapBiomas", "Prodes", "RADD", "SAD", "Tropisco")
list <- list(Deter, GLADS2, GWF, LUCA, MapBiomas, Prodes, RADD, SAD, Tropisco)

aplica_mmu <- function(alerta) {
  mask <- alerta %>%
    st_transform(31981) %>%
    st_buffer(50) %>%
    sf_dissolve() %>%
    st_buffer(-50) %>%
    mutate(area = as.double(st_area(x))) %>%
    filter(area > 10000) %>%
    st_transform(4674)
  
  alerta %>% st_filter(mask)
}

list_modified <- lapply(list, function(x) {x2 <- x %>%
    aplica_mmu() %>% 
    mutate(semestre = ifelse(month(DATE) <= 6, 1, 2), 
           ano_sem = as.double(YEAR) + (semestre - 1)/2) %>% 
    st_transform(31981) %>% 
    mutate(area = as.double(st_area(geom))) %>% 
    st_transform(4674)
    x3 <- sf_dissolve(x2, "ano_sem")
    x3 %>% st_make_valid() %>% rename(geom = x)
})

Planet <- sf_dissolve(Planet, "ano_sem") %>% rename(geom = x) %>% mutate(ano_sem = as.double(ano_sem))

mask_before <- ProdesBefore %>% 
  st_union() %>% st_as_sf() %>% 
  rename(geom = x) %>% 
  mutate(ano_sem = as.double(2019.5)) %>% 
  st_intersection(Planet %>% filter(ano_sem == 2020)) %>% 
  select(-ano_sem.1)

dates = seq(2020, 2025, by = 0.5)

for (i in 1:9) {

  dados_i <- list_modified[[i]] %>%
    mutate(ano_sem = as.double(ano_sem)) %>% 
    bind_rows(mask_before) %>% 
    arrange(ano_sem) %>% 
    st_make_valid()
    
  
  geoms_acum <- accumulate(dados_i$geom, st_union)
  
  list_modified[[i]] <- st_sf(
    ano_sem = dados_i$ano_sem,
    geom = geoms_acum,
    crs = st_crs(dados_i)
  ) %>% st_collection_extract(type="POLYGON") %>% 
    mutate(ano_sem = as.double(ano_sem))
}

names(list_modified) <- names
acum_sf <- bind_rows(list_modified, .id = "alert")
write_sf(acum_sf,"dados/derivados/benchmark/acumulado.gpkg")
st_layers("dados/derivados/benchmark/acumulado.gpkg")

mapview(list_modified[[8]] %>% filter(ano_sem == 2019.5), col.regions="purple", legend=FALSE) + 
  mapview(list_modified[[8]] %>% filter(ano_sem == 2020.5), col.regions="pink", legend=FALSE) + 
  mapview(list_modified[[8]] %>% filter(ano_sem == 2021.5), col.regions="blue", legend=FALSE) + 
  mapview(list_modified[[8]] %>% filter(ano_sem == 2022.5), col.regions="cyan", legend=FALSE) + 
  mapview(list_modified[[8]] %>% filter(ano_sem == 2023.5), col.regions="red", legend=FALSE)

sf_use_s2(FALSE)
intersections <- list()
for (i_alert in 1:9) {
  
  x2 <- list()
  
  for (i_date in 1:11) {
    x3 <- list_modified[[i_alert]] %>% 
      filter(ano_sem == dates[i_date]) %>% 
      st_make_valid()
    
    Planet_i <- Planet %>% filter(ano_sem == dates[i_date]) %>% st_make_valid()
    
    inters <- st_intersection(x3, Planet %>% filter(ano_sem == dates[i_date]))
    inters <- inters[!st_is_empty(inters)]
      
      x2[[i_date]] <- inters
    }

  intersections[[i_alert]] <- do.call(rbind, x2)
}

alert_wo_planet <- list()
for (i_alert in 1:9) {
  
  x2 <- list()
  
  for (i_date in 1:11) {
    x3 <- list_modified[[i_alert]] %>% 
      filter(ano_sem == dates[i_date]) %>% 
      st_make_valid()
    
    Planet_i <- Planet %>% filter(ano_sem == dates[i_date])
    
    if(nrow(x3) == 0){next}
    else{
      diff <- st_difference(x3, Planet %>% filter(ano_sem == dates[i_date]))
      diff <- diff[!st_is_empty(diff)] %>% select(-ano_sem.1)
      
      x2[[i_date]] <- diff
    }
  }
  
  alert_wo_planet[[i_alert]] <- do.call(rbind, x2)
}

planet_wo_alert <- list()
for (i_alert in 1:9) {
  
  x2 <- list()
  
  for (i_date in 1:11) {
    x3 <- list_modified[[i_alert]] %>% 
    filter(ano_sem == dates[i_date]) %>% 
    st_make_valid()
    
    Planet_i <- Planet %>% filter(ano_sem == dates[i_date])
    
    if(nrow(x3) == 0){next}
    else{
      diff <- st_difference(Planet %>% filter(ano_sem == dates[i_date]), x3)
      diff <- diff[!st_is_empty(diff)] %>% select(-ano_sem.1)
      
      x2[[i_date]] <- diff
    }
  }
  
  planet_wo_alert[[i_alert]] <- do.call(rbind, x2)
}

mapview(list_modified[[2]] %>% filter(ano_sem == 2024.5), col.regions="purple", legend=FALSE) + 
  mapview(Planet %>% filter(ano_sem == 2024.5), col.regions="pink", legend=FALSE) + 
  mapview(alert_wo_planet[[2]] %>% filter(ano_sem == 2024.5), col.regions="blue", legend=FALSE) + 
  mapview(planet_wo_alert[[2]] %>% filter(ano_sem == 2024.5), col.regions="cyan", legend=FALSE) + 
  mapview(intersections[[2]] %>% filter(ano_sem == 2024.5), col.regions="red", legend=FALSE)

for (i in 1:9) {
  write_sf(intersections[[i]], paste0("dados/derivados/benchmark/Intersections/",names[i],".gpkg"))
}

for (i in 1:9) {
  write_sf(alert_wo_planet[[i]], paste0("dados/derivados/benchmark/Alert-Planet/",names[i],".gpkg"))
}

for (i in 1:9) {
  write_sf(planet_wo_alert[[i]], paste0("dados/derivados/benchmark/Planet-Alert/",names[i],".gpkg"))
}

# Alert
processa_nome <- function(nome){
  
  Planet_inter <- read_sf(paste0("dados/derivados/benchmark/Intersections/", nome, ".gpkg")) %>%
    st_transform(31981) %>%
    mutate(area = as.double(st_area(geom))) %>%
    st_transform(4674) %>%
    mutate(track = "Intersecção")

  Planet_only <- read_sf(paste0("dados/derivados/benchmark/Planet-Alert/", nome, ".gpkg")) %>%
    st_transform(31981) %>%
    mutate(area = as.double(st_area(geom))) %>%
    st_transform(4674) %>%
    mutate(track = "Planet_Only")

  Alert_only <- read_sf(paste0("dados/derivados/benchmark/Alert-Planet/", nome, ".gpkg")) %>%
    st_transform(31981) %>% 
    mutate(area = as.double(st_area(geom))) %>% 
    st_transform(4674) %>% 
    mutate(track = "Alert_Only")
    
  
  Planet_track <- Planet %>%
    st_transform(31981) %>%
    mutate(area = as.double(st_area(geom))) %>%
    st_transform(4674) %>%
    mutate(track = "Planet")
  
  Alert_track <- list_modified[[nome]] %>%
    st_transform(31981) %>%
    mutate(area = as.double(st_area(geom))) %>%
    st_transform(4674) %>%
    mutate(track = "Alert")
  
  bind_rows(Planet_inter, Planet_track, Alert_track, Planet_only, Alert_only) %>%
    mutate(nome = nome)
}

alertas_final <- map_dfr(names, processa_nome) %>% select(-ano_sem.1)
df_plot <- alertas_final %>% mutate(ano_sem = ifelse(ano_sem==2019.5,2020,ano_sem))

df_plot <- df_plot %>%
  group_by(nome, ano_sem, track) %>%
  summarise(area = max(area), .groups = "drop")

df_plot <- df_plot %>%
  group_by(nome, track) %>%
  complete(ano_sem = seq(2020, 2025, by = 0.5)) %>%
  arrange(nome, track, ano_sem) %>%
  fill(area, .direction = "downup")

write_sf(df_plot, "resultados/tabelas/df_track.gpkg")

ggplot(df_plot, 
       aes(x = ano_sem, 
           y = area, 
           color = track,
           linetype = track)) +
  geom_line(size = 1, alpha = 0.5) +
  scale_linetype_manual(values = c(
    "Planet" = "solid",
    "Planet_Only" = "dashed",
    "Alert" = "solid",
    "Alert_Only" = "dashed",
    "Intersecção" = "solid"
  )) +
  facet_wrap(~ nome) + 
  theme_minimal()

mapview(alertas_final %>% 
          filter(nome == "Prodes", ano_sem==2020.5) %>% 
          arrange(desc(track)), zcol="track")
                                                               