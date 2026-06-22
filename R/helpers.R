library(bslib)
# ============================================================
# helpers.R — Configuración compartida entre módulos
# Explorador de Especies · Uruguay
# Paleta celeste/azul nacional uruguaya
# ============================================================

# ── Paleta de colores Uruguay ─────────────────────────────────
colores <- list(
  primario    = "#0038A8",   # azul bandera Uruguay
  secundario  = "#75AADB",   # celeste bandera Uruguay
  acento      = "#F7D117",   # amarillo sol de mayo
  peligro     = "#C0392B",   # rojo oscuro
  exito       = "#27AE60",   # verde
  advertencia = "#F39C12",   # naranja/amarillo
  fondo       = "#F4F6FB",   # fondo azul muy suave
  fondo_card  = "#EEF3FA",   # fondo cards
  texto       = "#1A1A2E",
  borde       = "#C0D0E8",
  navbar      = "#0038A8",   # navbar azul Uruguay

  tableau = c(
    "#0038A8", "#75AADB", "#F7D117", "#27AE60",
    "#C0392B", "#8E44AD", "#7F8C8D", "#A9CCE3"
  )
)

# ── Tema bslib ───────────────────────────────────────────────
tema_app <- bs_theme(
  version      = 5,
  bootswatch   = NULL,
  bg           = colores$fondo,
  fg           = colores$texto,
  primary      = colores$primario,
  secondary    = colores$secundario,
  success      = colores$exito,
  danger       = colores$peligro,
  warning      = colores$advertencia,
  base_font    = font_google("Nunito"),
  heading_font = font_google("Nunito", wght = 700),
  code_font    = font_google("Fira Mono")
) |>
  bs_add_rules("
  /* ── Navbar ── */
  .navbar { background-color: #0038A8 !important; }
  .navbar-brand, .navbar .nav-link { color: #ffffff !important; }
  .navbar .nav-link.active { border-bottom: 2px solid #F7D117; }

  /* ── Tabs activos ── */
  .nav-tabs .nav-link.active {
    background-color: #0038A8 !important;
    color: #ffffff !important;
    border-top-color: #0038A8 !important;
    border-left-color: #0038A8 !important;
    border-right-color: #0038A8 !important;
    border-bottom-color: transparent !important;
    font-weight: 600 !important;
  }
  .nav-tabs .nav-link:not(.active):hover {
    background-color: #EEF3FA !important;
    color: #0038A8 !important;
  }

  /* ── Botón primario ── */
  .btn-primary {
    background-color: #0038A8 !important;
    border-color: #0038A8 !important;
    color: #ffffff !important;
  }
  .btn-primary:hover {
    background-color: #002d8a !important;
    border-color: #002d8a !important;
  }

  /* ── Cards ── */
  .card > .card-header {
    background-color: #D6E4F7;
    color: #0038A8;
    font-weight: 700;
    border-bottom: none;
  }

  /* ── Sidebar ── */
  .bslib-sidebar-layout > .sidebar {
    background-color: #F4F6FB !important;
    border-right: 1px solid #C0D0E8;
  }

  /* ── Título explorador en sidebar ── */
  .titulo-explorador {
    color: #0038A8;
    font-size: 0.95rem;
    font-weight: 700;
    line-height: 1.3;
    text-align: center;
  }

  /* ── Alertas con tono azul suave ── */
  .alert-light {
    background-color: #EEF3FA;
    border-color: #C0D0E8;
  }
")

# ── Escalas ggplot2 ──────────────────────────────────────────
scale_fill_uy <- function(...) {
  ggplot2::scale_fill_manual(values = colores$tableau, ...)
}
scale_color_uy <- function(...) {
  ggplot2::scale_color_manual(values = colores$tableau, ...)
}
