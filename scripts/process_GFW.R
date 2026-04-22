library(spatialEco)
library(ggplot2)
library(openxlsx)
library(mapview)
library(terra)
library(sf)
library(tidyverse)

GFW_area_estudo <- list()

semestres <- c(20190, 20195, 20200, 20205, 20210, 20215, 20220, 20225, 20230, 20235, 20240, 20245, 20250, 20255)

for (i in 1:14) {
  cat("---------------------\n")
  cat("Processando semestre: ", semestres[i], "\n")
  GFW_vetor <- read_sf("6_gfw/GWF_vetorizado_explodido.gpkg", layer = paste0("sem_",semestres[i])) %>% st_transform(4674)
  cat("Vetor lido\n")
  
  GFW_area_estudo[[i]] <- GFW_vetor
  cat("Semestre", semestres[i], "concluído\n")
  cat("---------------------\n\n\n")
}

GFW_binded <- bind_rows(GFW_area_estudo)

write_sf(GFW_binded, "6_gfw/GFW_binded_exploded.gpkg")

GFW_dissolved <- GFW_binded %>% sf_dissolve()

GFW_pista <- read_sf("6_gfw/GFW_pista.gpkg")

GFW_mmu_buffer <- GFW_pista %>% 
  st_transform(31981) %>% 
  st_buffer(50) %>%
  sf_dissolve() %>%
  st_buffer(-50)

GFW_mmu_filter <- GFW_mmu_buffer %>% 
  mutate(area = as.double(st_area(x))) %>%
  filter(area > 10000) %>%
  st_transform(4674)

write_sf(GFW_mmu_filter, "6_gwf/GFW_mmu_c_buffer.gpkg")

