# ============================================================
# utils_data.R
# Carga de covariables CHELSA pre-procesadas por resolución H3
# Explorador de Especies · Uruguay
# ============================================================

# ── Contorno de Uruguay ──────────────────────────────────────
# Fuente: Natural Earth via rnaturalearth (escala "medium")
# Generado con:
#   library(rnaturalearth)
#   uy <- ne_countries(country = "Uruguay", scale = "medium", returnclass = "sf")
#   sf::st_write(uy, "data/uruguay_sf_ne.gpkg")

.uy_outline_cache <- NULL

uy_outline <- function() {
  if (!is.null(.uy_outline_cache)) return(.uy_outline_cache)
  path <- file.path(DATA_DIR, "uruguay_sf_ne.gpkg")
  if (!file.exists(path)) {
    stop("[utils_data] No se encontró uruguay_sf_ne.gpkg en data/")
  }
  shp <- sf::st_read(path, quiet = TRUE)
  .uy_outline_cache <<- shp
  shp
}

# ── Rutas de datos ───────────────────────────────────────────
DATA_DIR <- "data"

# Mapeo resolución → archivo de covariables (solo h6 y h7 para Uruguay)
covariables_paths <- list(
  actual = list(
    "6" = file.path(DATA_DIR, "bio_chelsa_presente_no_cor_uy_32721_h6.gpkg"),
    "7" = file.path(DATA_DIR, "bio_chelsa_presente_no_cor_uy_32721_h7.gpkg")
  ),
  futuro = list(
    "6" = file.path(DATA_DIR, "bio_chelsa_futuro_uy_32721_h6.gpkg"),
    "7" = file.path(DATA_DIR, "bio_chelsa_futuro_uy_32721_h7.gpkg")
  )
)

# ── Cache en memoria (se carga una sola vez por sesión) ─────
.cov_cache <- new.env(parent = emptyenv())

#' Cargar covariables para una resolución dada
#'
#' @param resolucion character "6" o "7"
#' @param escenario  character "actual" o "futuro"
#' @return sf con h3_address + variables (o NULL si el archivo no existe)
cargar_covariables <- function(resolucion, escenario = "actual") {
  key <- paste0(escenario, "_res", resolucion)

  if (exists(key, envir = .cov_cache)) {
    return(get(key, envir = .cov_cache))
  }

  path <- covariables_paths[[escenario]][[as.character(resolucion)]]

  if (is.null(path) || !file.exists(path)) {
    warning(sprintf(
      "[utils_data] Archivo no encontrado: %s\n  Prepará el gpkg con h3sdm_extract_num() y colocálo en data/",
      path %||% "(ruta no definida)"
    ))
    return(NULL)
  }

  dat <- sf::st_read(path, quiet = TRUE)
  assign(key, dat, envir = .cov_cache)
  dat
}

#' Verificar disponibilidad de covariables
#' @return data.frame con estado de cada archivo
verificar_covariables <- function() {
  res <- do.call(rbind, lapply(c("6", "7"), function(r) {
    data.frame(
      resolucion = r,
      actual     = file.exists(covariables_paths$actual[[r]]),
      futuro     = file.exists(covariables_paths$futuro[[r]]),
      stringsAsFactors = FALSE
    )
  }))
  res
}

#' Operador %||% (null coalescing)
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ── Info de resoluciones ─────────────────────────────────────
info_resoluciones <- data.frame(
  res   = c("6", "7"),
  label = c(
    "6 — 36.1 km² (paisaje regional)",
    "7 — 5.2 km² (SDM fino ★)"
  ),
  area  = c("36.1 km²", "5.2 km²"),
  stringsAsFactors = FALSE
)
