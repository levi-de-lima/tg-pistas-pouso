library(spatialEco)
library(ggplot2)
library(openxlsx)
library(mapview)
library(terra)
library(sf)
library(tidyverse)

area_estudo <- read_sf("1_fontes/area_estudo/area_de_estudo.gpkg")
GWF_raw <- rast("1_fontes/gwf/GWF_ALB.tiff")
GWF_raw <- GWF_raw %>% crop(area_estudo %>% st_transform(st_crs(GWF_raw)))

GWF_clamp <- clamp(GWF_raw, lower=30000, upper=45000, values=FALSE)

writeRaster(GWF_clamp, "6_gwf/GFW_area_de_estudo.tiff", overwrite=TRUE)

# gera todos os dias possíveis
origem <- as.Date("2015-01-01")
dias <- 1:4000  # cobre até ~2026

datas <- as_date(dias, origin = origem - 1)

ano_sem <- as.double(paste0(year(datas),if_else(month(datas) <= 6, 0, 5)))

# monta matriz para high confidence (3XXXX)
rcl_high <- data.frame(
  from = dias + 30000,
  to   = ano_sem
)

# monta matriz para highest confidence (4XXXX)
rcl_highest <- data.frame(
  from = dias + 40000,
  to   = ano_sem
)

rcl <- as.matrix(rbind(rcl_high, rcl_highest))

GWF_sem <- terra::classify(GWF_clamp, rcl, others = NA)

GWF_clean <- terra::sieve(GWF_sem, threshold = 40)


semestres <- c(20190, 20195, 20200, 20205, 20210, 20215, 20220, 20225, 20230, 20235, 20240, 20245, 20250, 20255)

for (sem in semestres) {
  cat("Processando semestre", sem, "\n")
  
  # isola um semestre
  rast_sem <- ifel(GWF_sem == sem, sem, NA)
  
  # vetoriza só esse semestre
  vet_sem <- as.polygons(rast_sem, dissolve = TRUE) %>%
    st_as_sf() %>%
    st_cast("POLYGON")
    # st_transform(31981) %>%
    # mutate(area = as.double(st_area(geometry))) %>%
    # filter(area > 10000) %>%
    # st_transform(4674) %>%
    mutate(ano_sem = sem / 10)
  
  # salva direto em arquivo
  write_sf(vet_sem, "6_gwf/GWF_vetorizado_2.gpkg",
           layer = paste0("sem_", sem),
           append = TRUE)
  
  gc()
  cat("Semestre", sem, "concluído\n")
}


GFW_area_estudo <- list()

for (i in 1:14) {
  cat("---------------------\n")
  cat("Processando semestre: ", semestres[i], "\n")
  GFW_vetor <- read_sf("6_gwf/GWF_vetorizado_2.gpkg", layer = paste0("sem_",semestres[i])) %>% st_transform(4674)
  cat("Vetor lido\n")
  
  GFW_area_estudo[[i]] <- GFW_vetor
  cat("Semestre", semestres[i], "concluído\n")
  cat("---------------------\n\n\n")
}

GFW_binded <- bind_rows(GFW_area_estudo)

write_sf(GFW_binded, "6_gwf/GFW_binded.gpkg")

GFW_mmu <- GFW_binded %>% 
  st_transform(31981) %>% 
  st_buffer(50) %>% 
  sf_dissolve() %>%
  st_buffer(-50) %>%
  mutate(area = as.double(st_area(x))) %>%
  filter(area > 10000) %>%
  st_transform(4674)
cat("MMU executado\n")

GFW_filtrado <- GFW_vetor %>% st_filter(GFW_mmu)
cat("Filtro feito\n")


nearest <- st_nearest_feature(GFW_filtrado, base_pistas)

GFW_filtrado <- GFW_filtrado %>%
  mutate(
    pista_proxima = as.factor(base_pistas$id_pista[nearest]),
    ano = year(DATE),
    semestre = if_else(month(DATE) <= 6, 1, 2),
    ano_sem = ano + (semestre - 1) / 2
  )

GFW_dissolved <- GFW_filtrado %>%
  group_by(pista_proxima, ano_sem) %>%
  summarise(geom = st_union(geom), .groups = "drop") %>% 
  st_transform(31981) %>% 
  mutate(area = as.double(st_area(geom))) %>% 
  st_transform(4674)

### PLOT ###

sf_plot <- GFW_dissolved %>% 
  st_drop_geometry() %>% 
  complete(
    pista_proxima,
    ano_sem = seq(2020, max(ano_sem), by = 0.5),
    fill = list(area = 0)
  )

sf_vline <- base_pistas %>%
  mutate(
    # início
    vline_inicio = start_date,
    
    # fim = menor entre inpop_date e end_date
    vline_fim = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim) %>% 
  mutate(id_pista = as.factor(id_pista)) %>% 
  rename(pista_proxima = id_pista)

sf_vline_long <- sf_vline %>%
  pivot_longer(
    cols = c(vline_inicio, vline_fim),
    names_to = "tipo",
    values_to = "xintercept"
  ) %>%
  filter(!is.na(xintercept),
         pista_proxima %in% unique(sf_plot$pista_proxima)) %>% 
  mutate(    
    ano = year(xintercept),
    semestre = if_else(month(xintercept) <= 6, 1, 2),
    xintercept = ano + (semestre - 1) / 2
  )

ggplot(sf_plot, aes(x = ano_sem, y = area)) +
  geom_line() +
  geom_vline(
    data = sf_vline_long,
    aes(xintercept = xintercept),
    linetype = "dashed"
  ) +
  facet_wrap(~ pista_proxima, ncol = 4, scales = "free_y")

write_sf(sf_plot, "data/processed/GFW_pistas_plot.gpkg")
