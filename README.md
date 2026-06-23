# EcoSdmUY · Explorador de Especies · Uruguay
**Versión 1.0**  
Manuel Spínola

---

## Estructura del proyecto

```
EcoSdmUY/
├── app.R                    # Punto de entrada
├── DESCRIPTION              # Metadatos y dependencias del proyecto
├── R/
│   ├── helpers.R            # Paleta de colores, tema bslib, escalas ggplot2
│   ├── utils_data.R         # Carga de covariables CHELSA pre-procesadas
│   ├── mod_sidebar.R        # Especie + resolución H3 + botón Ver distribución
│   ├── mod_registros.R      # Descarga GBIF / iNaturalist
│   ├── mod_modelo.R         # PA + ajuste + predicción presente/futura + AOA (sin UI)
│   ├── mod_mapas.R          # Mapas leaflet + leafgl (presente / futuro / AOA / AOA futuro)
│   └── mod_metricas.R       # Métricas, ROC, importancia de variables, PDP
├── data/
│   ├── uruguay_sf_ne.gpkg                       # Contorno de Uruguay (Natural Earth)
│   ├── bio_chelsa_presente_no_cor_uy_32721_h6.gpkg  # Variables bioclimáticas CHELSA actuales, res H3 = 6
│   ├── bio_chelsa_presente_no_cor_uy_32721_h7.gpkg  # ídem res 7
│   ├── bio_chelsa_presente_no_cor_uy_32721_h8.gpkg  # ídem res 8
│   ├── bio_chelsa_futuro_uy_32721_h6.gpkg            # Variables bioclimáticas CHELSA futuras SSP5-8.5, res 6
│   ├── bio_chelsa_futuro_uy_32721_h7.gpkg            # ídem res 7
│   └── bio_chelsa_futuro_uy_32721_h8.gpkg            # ídem res 8
└── www/
    └── logo_uy.png
```

---

## Decisión metodológica: solo variables bioclimáticas CHELSA

Esta app usa **exclusivamente variables bioclimáticas CHELSA no correlacionadas**
como predictores. Estas decisiones son intencionales:

### ¿Por qué solo variables bioclimáticas?

**1. Consistencia presente–futuro**  
Variables de paisaje como cobertura boscosa, NDVI o métricas de fragmentación
solo están disponibles para el presente. No existen proyecciones confiables de
estas variables bajo escenarios de cambio climático futuro (SSP5-8.5 2061–2080).
Usar variables de paisaje en el modelo presente impediría generar predicciones
futuras coherentes.

**2. Comparabilidad entre especies**  
Al usar el mismo conjunto de predictores bioclimáticos para todas las especies,
los resultados son comparables entre sí y el flujo de trabajo es completamente
automatizable — el usuario solo escoge la especie y la resolución.

### ¿Por qué CHELSA y no WorldClim?

CHELSA (Climatologies at High resolution for the Earth's Land Surface Areas)
ofrece varias ventajas sobre WorldClim para Uruguay:

**Mejor representación de precipitación y temperatura**  
CHELSA usa un downscaling basado en modelos atmosféricos que captura mejor
los gradientes climáticos del territorio uruguayo, incluyendo la influencia
del Río de la Plata y el Atlántico Sur.

**Consistencia presente–futuro**  
Las proyecciones futuras de CHELSA (CHELSA-CMIP6) usan el mismo método de
downscaling que el presente, garantizando consistencia metodológica entre
ambos escenarios. WorldClim futuro y presente usan métodos distintos.

**Cobertura temporal y actualización**  
CHELSA cubre 1981–presente con actualizaciones periódicas, mientras que
WorldClim 2.1 tiene una línea base fija (1970–2000).

> Karger, D.N. et al. (2017). Climatologies at high resolution for the Earth's
> land surface areas. *Scientific Data*, 4, 170122.
> [doi:10.1038/sdata.2017.122](https://doi.org/10.1038/sdata.2017.122)

**Fuentes de descarga:**
- Presente: [chelsa-climate.org](https://chelsa-climate.org) → CHELSA-BIOCLIM+
- Futuro SSP5-8.5 2061–2080: mismo sitio → CHELSA-CMIP6 → ensamble de GCMs

### Filtro de correlación

Las variables bioclimáticas deben ser filtradas por correlación antes de
guardarlas en los `.gpkg`. Se recomienda usar `filter_collinear()` con un
umbral de correlación de Pearson r < 0.7.

---

## Preparar las covariables CHELSA

Los archivos `.gpkg` en `data/` deben prepararse antes de desplegar la app.
El formato GeoPackage (`.gpkg`) es el único formato soportado.

Ejemplo completo para resolución 7:

```r
library(h3sdm)
library(sf)
library(terra)
library(tidysdm)  # para filter_collinear()

# 1. Cargar contorno de Uruguay (Natural Earth)
uy_outline <- sf::st_read("data/uruguay_sf_ne.gpkg")

# 2. Grilla H3 para Uruguay (H3 genera en WGS84)
uy_grid_7 <- h3sdm_get_grid(uy_outline, res = 7)

# 3. Transformar grilla a EPSG:32721 (UTM zona 21S — CRS estándar para Uruguay)
#    Todo el procesamiento y los .gpkg finales deben estar en 32721.
#    Solo se transforma a 4326 en la app, justo antes de renderizar en leaflet.
uy_grid_7_32721 <- sf::st_transform(uy_grid_7, 32721)

# 4. Cargar rasters CHELSA (variables bioclimáticas actuales)
#    Los rasters deben estar reprojectados a EPSG:32721 antes de extraer.
bio_actual <- terra::rast("ruta/a/chelsa_bio_actual.tif")
bio_actual <- terra::project(bio_actual, "EPSG:32721")

# 5. Filtrar variables correlacionadas (r < 0.7)
vars_no_cor <- filter_collinear(bio_actual, cutoff = 0.7, method = "cor_caret")
bio_actual_nc <- bio_actual[[vars_no_cor]]

# 6. Extraer variables dentro de cada hexágono (media por hexágono)
cov_actual <- h3sdm_extract_num(bio_actual_nc, uy_grid_7_32721)
# Verificar CRS: debe ser EPSG:32721
sf::st_crs(cov_actual)$epsg  # → 32721

# 7. Guardar como GeoPackage en EPSG:32721
sf::st_write(cov_actual, "data/bio_chelsa_presente_no_cor_uy_32721_h7.gpkg",
             delete_dsn = TRUE)

# 8. Repetir para futuro — mismas variables, mismo CRS
bio_futuro <- terra::rast("ruta/a/chelsa_bio_futuro_ssp585_2061_2080.tif")
bio_futuro <- terra::project(bio_futuro, "EPSG:32721")
bio_futuro_nc <- bio_futuro[[vars_no_cor]]  # exactamente las mismas variables
cov_futuro <- h3sdm_extract_num(bio_futuro_nc, uy_grid_7_32721)
sf::st_write(cov_futuro, "data/bio_chelsa_futuro_uy_32721_h7.gpkg",
             delete_dsn = TRUE)

# 9. Repetir para resoluciones 6 y 8
```

> **Importante:**
> - Todos los `.gpkg` deben estar en **EPSG:32721** (UTM zona 21S). La app no hace
>   transformaciones de CRS en tiempo de ejecución — solo transforma
>   a 4326 justo antes de renderizar en leaflet.
> - Los archivos actual y futuro deben tener exactamente las mismas
>   columnas (mismas variables bioclimáticas). El modelo se entrena
>   con las variables actuales y predice sobre las futuras.
> - El filtro de correlación `filter_collinear()` se aplica **solo una vez**
>   sobre las variables actuales. Las mismas variables seleccionadas
>   se usan para el escenario futuro.

---

## Paquetes requeridos

```r
install.packages(c(
  "shiny", "bslib", "bsicons", "shinyjs",
  "leaflet", "leafgl",
  "sf", "terra", "dplyr", "rlang",
  "tidymodels", "parsnip", "recipes", "tune",
  "spatialsample", "yardstick",
  "DALEX", "ingredients",
  "ggplot2"
))

# h3sdm
remotes::install_github("mspinola/h3sdm")
```

---

## Desplegar en Posit Connect Cloud

```r
library(rsconnect)

# Configurar cuenta (solo la primera vez)
rsconnect::setAccountInfo(
  name   = "tu_usuario",
  token  = "TU_TOKEN",
  secret = "TU_SECRET"
)

# Desplegar
rsconnect::deployApp(
  appDir      = "ruta/a/EcoSdmUY",
  appName     = "explorador-especies-uy",
  appTitle    = "Explorador de Especies · Uruguay",
  forceUpdate = TRUE
)
```

### Nota sobre el tamaño de los archivos `data/`
Posit Connect Cloud tiene un límite de tamaño de bundle. Si los `.gpkg`
son grandes (> 1 GB), considerá:
- Almacenarlos en **Posit Connect Pins** (`pins::pin_write()`) y
  cargarlos al inicio desde `utils_data.R`.
- O usar una base de datos PostGIS accesible desde el servidor.

---

## Fuentes de datos de ocurrencia

| Fuente | URL |
|---|---|
| GBIF | [gbif.org](https://www.gbif.org) |
| iNaturalist | [inaturalist.org](https://www.inaturalist.org) |

## Fuentes de datos espaciales

| Capa | Fuente | Paquete R |
|---|---|---|
| Contorno de Uruguay | Natural Earth (escala medium) | `rnaturalearth` |

```r
library(rnaturalearth)
uy <- ne_countries(country = "Uruguay", scale = "medium", returnclass = "sf")
sf::st_write(uy, "data/uruguay_sf_ne.gpkg")
```

---

## EcoSuite

Esta app forma parte de **EcoSuite**, una colección de aplicaciones web
para visualización y consulta de biodiversidad. A diferencia de **StatSuite**
(herramientas analíticas con estructura de paquete R), las apps de EcoSuite
son productos de visualización standalone orientados al público general —
el usuario no necesita conocimientos de R ni de SDM.
