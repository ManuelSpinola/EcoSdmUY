# ============================================================
# mod_modelo.R
# Módulo interno (sin UI propia):
#   1. Genera dataset PA con h3sdm
#   2. Ajusta modelo (GAM)
#   3. Predice distribución presente y futura
#   4. Calcula AOA presente y futuro
# Explorador de Especies · Uruguay
# CRS: EPSG:32721 (UTM zona 21S)
# ============================================================

# Este módulo no tiene UI — se invoca solo desde server
mod_modelo_server <- function(id, estado, sidebar_vals) {
  moduleServer(id, function(input, output, session) {

    # Disparar flujo cuando los registros están listos
    observeEvent(estado$registros_listos, ignoreNULL = TRUE, ignoreInit = TRUE, {
      req(!is.null(estado$registros_sf))
      req(nrow(estado$registros_sf) > 0)

      especie <- trimws(sidebar_vals$especie())
      res     <- sidebar_vals$resolucion()
      alg     <- sidebar_vals$algoritmo()
      req(nchar(especie) > 0)

      .ajustar_modelo(especie, res, alg, estado, sidebar_vals, session)
    })
  })
}

# ── Función interna del flujo completo ───────────────────────
.ajustar_modelo <- function(especie, res, alg, estado, sidebar_vals, session) {

  recs <- estado$registros_sf
  if (is.null(recs) || nrow(recs) == 0) {
    showNotification("No hay registros disponibles para modelar.",
                     type = "warning", duration = 5)
    return()
  }

  withProgress(message = paste("Ajustando modelo para", especie, "..."),
               detail  = "Preparando datos...", {

    tryCatch({

      # 1. Covariables actuales
      setProgress(0.1, detail = "Cargando covariables CHELSA...")
      cov_actual <- cargar_covariables(res, "actual")
      if (is.null(cov_actual)) {
        showNotification(
          paste0("Covariables actuales para resolución ", res, " no disponibles. ",
                 "Prepararlas con h3sdm_extract_num() y guardarlas en data/."),
          type = "error", duration = 10)
        return()
      }

      cov_dedup <- cov_actual[!duplicated(cov_actual$h3_address), ]
      vars_df   <- sf::st_drop_geometry(cov_dedup)

      # 2. Hexágonos de presencia
      # CRS 32721 = UTM zona 21S (Uruguay)
      setProgress(0.2, detail = "Asignando registros a hexágonos...")
      pres_sf <- h3sdm::h3sdm_pres_from_sf(
        records_sf    = sf::st_transform(recs, 32721),
        aoi_sf        = sf::st_transform(uy_outline(), 32721),
        res           = as.integer(res),
        expand_factor = 0.1
      )

      n_pres <- nrow(pres_sf)
      if (n_pres < 5) {
        showNotification(
          paste0("Solo ", n_pres, " hexágonos de presencia - necesitás más registros para modelar."),
          type = "error", duration = 8)
        return()
      }

      # 3. PA temporal para filtro de outliers
      setProgress(0.25, detail = "Filtrando outliers ambientales...")
      pred_sf <- h3sdm::h3sdm_predictors(cov_dedup)

      pa_temp <- h3sdm::h3sdm_pa(
        pres_sf       = pres_sf[, c("h3_address", "geometry")],
        predictors_sf = pred_sf,
        n_pseudoabs   = n_pres,
        buffer_k      = as.integer(sidebar_vals$buffer_k())
      )

      filtro      <- h3sdm::h3sdm_filter_outliers(
        h3sdm::h3sdm_data(pa_temp, pred_sf)
      )
      n_pres_post <- sum(filtro$pa_clean$presence == "1", na.rm = TRUE)

      estado$n_registros_modelo <- n_pres_post
      estado$n_removidos        <- filtro$n_removed
      if (filtro$n_removed > 0) {
        showNotification(
          paste0(
            "\u26a0\ufe0f ", filtro$n_removed,
            " hexágono(s) eliminado(s) como outlier(s) ambiental(es) ",
            "(D^2 > ", round(filtro$threshold_d2, 1), "). ",
            "Se usaron ", n_pres_post, " hexágonos de presencia para el modelo."
          ),
          type = "warning", duration = 8
        )
      }

      if (n_pres_post < 5) {
        showNotification(
          paste0("Tras el filtro ambiental quedaron solo ", n_pres_post,
                 " presencias - no es posible ajustar el modelo. ",
                 "Intentá con una especie con más registros."),
          type = "error", duration = 10)
        return()
      }

      # 4. PA final balanceado 1:1
      setProgress(0.3, detail = "Generando pseudoausencias balanceadas 1:1...")
      pres_clean <- filtro$pa_clean[filtro$pa_clean$presence == "1",
                                    c("h3_address", "geometry")]

      pa <- h3sdm::h3sdm_pa(
        pres_sf       = pres_clean,
        predictors_sf = pred_sf,
        n_pseudoabs   = n_pres_post,
        buffer_k      = as.integer(sidebar_vals$buffer_k())
      )

      estado$n_hex_pres <- n_pres_post
      estado$n_hex_aus  <- sum(pa$presence == "0", na.rm = TRUE)

      # 5. Construir dataset de modelado
      pa_base <- pa[!duplicated(pa$h3_address), c("h3_address", "presence")]
      dat     <- h3sdm::h3sdm_data(pa_base, pred_sf)
      estado$dat_rv <- dat

      presence_data <- dat |> dplyr::filter(presence == "1")

      # 6. Recipe
      setProgress(0.4, detail = paste("Configurando", toupper(alg), "..."))
      if (alg == "gam") {
        rec <- h3sdm::h3sdm_recipe_gam(dat, response_col = "presence")
      } else {
        rec <- h3sdm::h3sdm_recipe(dat, response_col = "presence")
        rec <- recipes::step_normalize(rec, recipes::all_numeric_predictors())
      }

      # 7. Especificación del modelo
      model_spec <- switch(alg,
        rf = parsnip::rand_forest(trees = 500) |>
               parsnip::set_engine("ranger") |>
               parsnip::set_mode("classification"),
        xgb = parsnip::boost_tree(trees = 300, learn_rate = 0.1) |>
                parsnip::set_engine("xgboost") |>
                parsnip::set_mode("classification"),
        logreg = parsnip::logistic_reg() |>
                   parsnip::set_engine("glm") |>
                   parsnip::set_mode("classification"),
        gam = parsnip::gen_additive_mod() |>
                parsnip::set_engine("mgcv") |>
                parsnip::set_mode("classification")
      )

      # 8. Workflow
      if (alg == "gam") {
        df_dat   <- sf::st_drop_geometry(dat)
        vars_dat <- setdiff(names(df_dat), c("h3_address", "presence", "x", "y"))
        vars_num <- vars_dat[sapply(df_dat[, vars_dat, drop = FALSE], is.numeric)]
        formula_str <- paste0(
          "presence ~ ",
          paste(paste0("s(", vars_num, ")"), collapse = " + "),
          " + s(x, y, bs = \"tp\")"
        )
        wf <- h3sdm::h3sdm_workflow_gam(
          gam_spec = model_spec,
          recipe   = rec,
          formula  = as.formula(formula_str)
        )
      } else {
        wf <- h3sdm::h3sdm_workflow(model_spec = model_spec, recipe = rec)
      }

      # 9. CV espacial
      setProgress(0.5, detail = "Validación cruzada espacial...")
      dat_valid <- sf::st_make_valid(dat)
      cv_split  <- h3sdm::h3sdm_spatial_cv(
        data     = dat_valid,
        method   = "block",
        v        = 5,
        repeats  = 1,
        square   = TRUE,
        cellsize = 30000
      )
      estado$cv_split_rv <- cv_split

      # 10. Ajustar
      setProgress(0.6, detail = "Ajustando modelo...")
      fitted <- h3sdm::h3sdm_fit_model(
        workflow      = wf,
        data_split    = cv_split,
        presence_data = presence_data
      )
      estado$modelo_ajustado <- fitted
      estado$algoritmo       <- alg
      estado$resolucion      <- res

      showNotification(
        paste0("Modelo ", toupper(alg), " ajustado — ", n_pres_post,
               " hexágonos de presencia · ", estado$n_hex_aus, " pseudoausencias."),
        type = "message", duration = 4)

      # 11. Predicción presente
      setProgress(0.7, detail = "Generando mapa de distribución presente...")
      pred_presente <- h3sdm::h3sdm_predict(fitted, pred_sf)
      estado$prediccion_sf <- pred_presente

      # 12. Predicción futura (si hay covariables)
      cov_futuro <- cargar_covariables(res, "futuro")
      if (!is.null(cov_futuro)) {
        setProgress(0.8, detail = "Generando mapa de distribución futura...")
        cov_fut_dedup <- cov_futuro[!duplicated(cov_futuro$h3_address), ]

        vars_presente  <- names(sf::st_drop_geometry(cov_dedup))
        vars_futuro    <- names(sf::st_drop_geometry(cov_fut_dedup))
        vars_faltantes <- setdiff(vars_presente, vars_futuro)

        if (length(vars_faltantes) > 0) {
          showNotification(
            paste0("Variables faltantes en covariables futuras: ",
                   paste(vars_faltantes, collapse = ", ")),
            type = "error", duration = 10)
          estado$pred_futuro_sf <- NULL
        } else {
          cols_keep     <- c(vars_presente[vars_presente %in% vars_futuro], "geom")
          cols_keep     <- intersect(cols_keep, names(cov_fut_dedup))
          cov_fut_dedup <- cov_fut_dedup[, cols_keep]

          pred_fut_sf   <- h3sdm::h3sdm_predictors(cov_fut_dedup)
          pred_futuro   <- h3sdm::h3sdm_predict(fitted, pred_fut_sf)
          estado$pred_futuro_sf <- pred_futuro
        }
      } else {
        estado$pred_futuro_sf <- NULL
        showNotification(
          paste0("Covariables futuras res-", res, " no disponibles. ",
                 "Solo se genera la distribución presente."),
          type = "warning", duration = 6)
      }

      # 13. AOA presente
      setProgress(0.85, detail = "Calculando AOA presente...")
      aoa_result <- h3sdm::h3sdm_aoa(
        newdata    = pred_presente,
        train      = dat,
        fit_object = fitted,
        cv         = cv_split
      )
      aoa_result <- aoa_result |>
        dplyr::mutate(
          prediction_aoa = dplyr::if_else(AOA == 1L, prediction, NA_real_)
        )
      estado$aoa_sf <- aoa_result

      # 14. AOA futuro (si hay predicción futura)
      if (!is.null(estado$pred_futuro_sf)) {
        setProgress(0.95, detail = "Calculando AOA futuro...")
        tryCatch({
          aoa_futuro <- h3sdm::h3sdm_aoa(
            newdata    = estado$pred_futuro_sf,
            train      = dat,
            fit_object = fitted,
            cv         = cv_split
          )
          aoa_futuro <- aoa_futuro |>
            dplyr::mutate(
              prediction_aoa = dplyr::if_else(AOA == 1L, prediction, NA_real_)
            )
          estado$aoa_futuro_sf <- aoa_futuro
        }, error = function(e) {
          estado$aoa_futuro_sf <- NULL
          showNotification(
            paste0("AOA futuro no disponible: ", conditionMessage(e)),
            type = "warning", duration = 6)
        })
      } else {
        estado$aoa_futuro_sf <- NULL
      }

      setProgress(1.0, detail = "¡Listo!")
      showNotification("Modelado completo.", type = "message", duration = 5)

    }, error = function(e) {
      showNotification(
        paste0("Error durante el modelado: ", conditionMessage(e)),
        type = "error", duration = 12)
    })
  })
}
