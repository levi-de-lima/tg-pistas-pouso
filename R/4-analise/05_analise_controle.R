library(slider)
library(readr)
library(sf)
library(dplyr)
library(tidyr)
library(lubridate)
library(slider)
library(purrr)
library(ggplot2)


# -----------------------------------------------------------------------------
# Carregamento
# -----------------------------------------------------------------------------
base_pistas  <- read_sf("dados/mestres/base_pistas_final.gpkg", layer = "pontos")

controle <- read_sf("dados/derivados/base_final/grupo_controle/controle_non_buffer.gpkg")

pistas_validade <- base_pistas %>%
  st_drop_geometry() %>%
  select(id_pista, start_date, end_date)

pistas_datas <- base_pistas %>%
  st_drop_geometry() %>%
  mutate(
    vline_inicio = as.Date(start_date),
    vline_fim    = as.Date(pmin(inop_date, end_date, na.rm = TRUE))
  ) %>%
  select(id_pista, vline_inicio, vline_fim)

plano <- pistas_datas %>%
  mutate(conjunto = case_when(
    !is.na(vline_inicio) & !is.na(vline_fim) ~ "ambos",
    !is.na(vline_inicio)                     ~ "inicio",
    !is.na(vline_fim)                        ~ "fim",
    TRUE                                     ~ NA_character_
  )) %>%
  filter(!is.na(conjunto)) %>%
  mutate(id_pista = as.integer(id_pista))

cat("Total de pistas: ", nrow(plano), "\n")
cat("  Estimam ambos:  ", sum(plano$conjunto == "ambos"), "\n")
cat("  Só início:      ", sum(plano$conjunto == "inicio"), "\n")
cat("  Só fim:         ", sum(plano$conjunto == "fim"), "\n\n")




# --- Área total por mês ---
area_mes <- controle %>%
  st_make_valid() %>% 
  mutate(
    mes = floor_date(doy, "month")
  ) %>%
  group_by(mes) %>%
  summarise(
    area_total = sum(area, na.rm = TRUE),
    .groups = "drop"
  )

# --- Gráfico ---
p <- ggplot(
  area_mes,
  aes(
    x = mes,
    y = area_total
  )
) +
  
  geom_col(
    fill = "grey40"
  ) +
  
  scale_x_date(
    date_breaks = "1 year",
    date_labels = "%Y"
  ) +
  
  labs(
    title = "Área minerada ao longo do tempo",
    subtitle = "Soma mensal das áreas mineradas",
    x = "Ano",
    y = "Área total"
  ) +
  
  theme_bw() +
  
  theme(
    axis.text.x = element_text(
      angle = 45,
      hjust = 1
    )
  )



ggsave(
  "resultados/figuras/analise/histogramas/gerais_pista/area_controle.png",
  p,
  width = 12,
  height = 6,
  dpi = 300,
  bg = "white"
)
