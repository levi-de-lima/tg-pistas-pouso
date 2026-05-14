library(dbscan)
library(sf)

pistas_ponto <- read_sf("5_base_final/base_pistas_final.gpkg")
GFW_c <- read_sf("6_gfw/GFW_centroide.gpkg")

coords_gfw_mat    <- st_coordinates(GFW_c %>% st_transform(31981))
coords_pistas_mat <- st_coordinates(pistas_ponto %>% st_transform(31981))

system.time(
  knn_result <- kNN(
    x     = coords_pistas_mat,
    query = coords_gfw_mat,
    k     = 7
  )
)

for (k in 1:7) {
  GFW_c[[paste0("pista_", k)]] <- as.factor(pistas_ponto$id_pista[knn_result$id[, k]])
  GFW_c[[paste0("dist_",  k)]] <- knn_result$dist[, k]
}

write_sf(GFW_c, "6_gfw/GFW_dist.gpkg")


# Matriz de distâncias entre todas as pistas
dist_pistas <- st_distance(
  pistas_ponto %>% st_transform(31981),
  pistas_ponto %>% st_transform(31981)
)

# Para cada pista, conta quantas outras estão dentro de 6000m
# (exclui a própria pista com dist > 0)
pistas_ponto$n_vizinhas_6km <- apply(dist_pistas, 1, function(x) {
  sum(x > 0 & x <= 6000)
})

# Resultado ordenado
pistas_ponto %>%
  st_drop_geometry() %>%
  select(id_pista, n_vizinhas_6km) %>%
  arrange(desc(n_vizinhas_6km)) %>%
  head(20)

