library(terra)
library(sf)

r <- rast("ALB_DETL.tif")
area <- read_sf("1_fontes/area_estudo/area_de_estudo.gpkg")
r_crop <- r %>% crop(area)

rcl <- matrix(c(
       0,  NA,
       1,  NA,
       2,  NA,
       3,  1,
       4,  1,
       5,  NA,
       6,  1,
       7,  NA,
       8,  NA,
       9,  1,
       10, 1,
       11, NA
   ), ncol = 2, byrow = TRUE)

r_filtrado <- classify(r_crop, rcl)

v <- st_as_sf(as.polygons(r_filtrado))

v_polyg <- v %>% st_cast("POLYGON")

v_valid <- v_polyg %>% st_make_valid()

v_transf <- v_valid %>% st_transform(4674)

write_sf(v_transf, "mask_valid_gfw.gpkg")

gfw <- read_sf("6_gfw/GFW_final_area.gpkg")

gfw_final <- st_difference(gfw, v_transf)
