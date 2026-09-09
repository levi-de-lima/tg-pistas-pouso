library(terra)
library(sf)
library(dplyr)
library(lubridate)
library(terra)

# 1. Carregamento e Preparação dos Dados Raster
area_estudo <- read_sf("area_de_estudo.gpkg")
GWF_raw <- rast("GWF_ALB.tiff")

# Ajuste de CRS e Crop
area_estudo_proj <- st_transform(area_estudo, st_crs(GWF_raw))
GWF_clamp <- clamp(GWF_raw, lower=30000, upper=45000, values=FALSE)
GWF_crop <- crop(GWF_clamp, area_estudo_proj)

writeRaster(GWF_crop, "GFW_crop.tiff")

# 2. Criação da Tabela de Reclassificação (Preservando Datas)
# Origem dos dados GWF (ajuste conforme o manual do seu dado se necessário)
origem <- as.Date("2015-01-01")
dias_sequencia <- 1:5000 # Cobertura ampla

# Criar dataframe de conversão
df_datas <- data.frame(
  dia_cod = dias_sequencia,
  data_real = as.numeric(as.Date(dias_sequencia, origin = origem - 1))
)

# Matriz para High Confidence (30000) e Highest Confidence (40000)
rcl <- rbind(
  data.frame(from = df_datas$dia_cod + 30000, to = df_datas$data_real),
  data.frame(from = df_datas$dia_cod + 40000, to = df_datas$data_real)
)

# Reclassificar o raster: agora cada pixel tem o valor numérico da data exata
cat("Reclassificando raster para datas exatas...\n")
GFW_data_raster <- terra::classify(GWF_crop, as.matrix(rcl), others = NA)

writeRaster(GFW_data_raster, "GFW_data_raster.tiff")

sum_alerts <- rast("~/grupos/projeto-dedicado/sum_alerts_re.tif")
sum_alerts_crop <- crop(sum_alerts, area_estudo_proj)
writeRaster(GFW_data_raster, "GFW_data_raster.tiff")

sum_alerts_subst <- sum_alerts_crop %>% subst(1:2, NA)
sum_alerts_subst2 <- sum_alerts_subst %>% subst(3:6, 1)

writeRaster(sum_alerts_subst2, "sum_alerts_final.tiff")

GFW_filtered <- sum_alerts_subst2 * GFW_data_raster

writeRaster(GFW_filtered, "GFW_filtered.tiff")

setwd("~/pistas-de-pouso")
GFW_data_raster <- rast("GFW_data_raster.tiff")
GFW_filtered <- rast("GFW_filtered.tiff")
sum_alerts_subst2 <- rast("sum_alerts_final.tiff")

Deter_non_min <- read_sf("Deter_non_min.gpkg")
Deter_non_min2 <- vect(Deter_non_min)
GFW_min_only <- mask(GFW_filtered, Deter_non_min2, inverse=TRUE)

GFW_vect_fix <- read_sf("dados/derivados/gfw/GFW_vectorized_fix.gpkg")

GFW_final <- GFW_vect_fix %>% mutate(doy = as.Date(doy, origin="1970-01-01"))

GFW_final2 <- GFW_final %>% st_transform(4674)

GFW_final3 <- GFW_final2 %>% st_cast("MULTIPOLYGON") %>% st_cast("POLYGON")

write_sf(GFW_final3, "GFW_final.gpkg")
