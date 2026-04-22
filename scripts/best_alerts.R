library(sf)
library(spatialEco)
library(tidyverse)
library(ggplot2)

df <- read_sf("4_analise_comparativa/df_track.gpkg") %>%
  st_drop_geometry() %>% 
  # filter(nome == "GWF") %>% 
  pivot_wider(names_from = track, values_from = area) %>% 
  mutate(omissao = Planet_Only / Planet, comissao = Alert_Only / Alert)

plot_df <- df %>% 
  pivot_longer(cols = c(omissao,comissao), names_to = "metrica", values_to = "area_minerada")

ggplot(data = plot_df, aes(x = ano_sem, y = area_minerada, color = metrica)) + 
  geom_line() + 
  facet_wrap(~nome, ncol=3)
