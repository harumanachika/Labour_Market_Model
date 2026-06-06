# 労働市場モデル・シミュレーション V2

#--- 初期ディレクトリ ---------------------------------------------------------
setwd("c:/Users/harum/GitHub/Public/Labour_Market_Model/")
par(mfrow = c(1, 1))
# httpgdを使う場合は hgd() を実行

#--- データの読み込み ---------------------------------------------------------
# Hall-Jorgenson型ユーザーコストとJIP/SNA合成指標は build_hj_user_cost_comparison.R で作成する。
user_cost_base_path <- "output/data_UserCost_with_HJ.csv"
user_cost_composite_path <- "output/hj_jip_sna_user_cost_composite.csv"

if (!file.exists(user_cost_base_path) || !file.exists(user_cost_composite_path)) {
  stop("ユーザーコストCSVがありません。先に build_hj_user_cost_comparison.R を実行してください。")
}

user_cost_base <- readr::read_csv(user_cost_base_path, show_col_types = FALSE) |>
  dplyr::transmute(
    year = as.integer(`...1`),
    RK = RK,
    RI = RI
  )

user_cost_composite <- readr::read_csv(user_cost_composite_path, show_col_types = FALSE) |>
  dplyr::select(
    year,
    UCAP = composite_uc_index_2015,
    UCAP_source = composite_source
  )

user_cost_data <- user_cost_base |>
  dplyr::left_join(user_cost_composite, by = "year")

head(user_cost_data)

#--- 既存コードの後ろに接続する拡張ブロック ----------------------------------
# LabourForce.rは変更せず、CES/MPLベースの需要方程式を推定する。
lf_raw <- readr::read_csv("data/data_LabourForce.csv", show_col_types = FALSE)

hist_years <- 1995:2025
all_years <- 1995:2040

if (!"A_LABOR" %in% names(lf_raw)) {
  lf_raw <- lf_raw |>
    dplyr::mutate(A_LABOR = 1)
}

lf_extended <- tibble::tibble(year = all_years) |>
  dplyr::left_join(lf_raw, by = "year") |>
  dplyr::left_join(user_cost_data, by = "year") |>
  dplyr::mutate(
    RY = Y / D_GDP * 100,
    D_GDP = D_GDP / 100,
    P = P / 100,
    E = dplyr::if_else(year %in% hist_years, E * 10, NA_real_),
    W = dplyr::if_else(year %in% hist_years, W / 100, NA_real_),
    L = E * H,
    W_PY = W / D_GDP,
    UCAP = UCAP / 100,
    A_LABOR = dplyr::coalesce(A_LABOR, 1),
    log_L = log(L),
    log_RY = log(RY),
    log_RK = log(RK),
    log_W_PY = log(W_PY),
    log_UCAP = log(UCAP),
    log_A_LABOR = log(A_LABOR)
  ) |>
  dplyr::filter(year >= 1997, year <= 2025)

#--- 労働増大的CESから導く労働需要式 -----------------------------------------
# 生産関数:
# Y = [alpha * K^rho + (1 - alpha) * (A_LABOR * L)^rho]^(1/rho)
# rho = (sigma - 1) / sigma
#
# 完全競争の下で W / P_Y = MPL とすると、
# log(W / P_Y) = log(1 - alpha) + ((sigma - 1) / sigma) * log(A_LABOR)
#                + (1 / sigma) * log(Y / L)
#
# したがって、bimetsで扱いやすい労働需要式は、
# log(L) = c0 + log(Y) - sigma * log(W / P_Y)
#          + (sigma - 1) * log(A_LABOR)
#
# ここでは V1.1 の LOG(MHD) 型に合わせ、L = MHD = E * H とする。
# 現時点で A_LABOR の実績系列がなければ1に正規化し、推計では
# log(A_LABOR) = g_a * (year - 2015) の労働増大的トレンドとして識別する。
ces_labor <- lf_extended |>
  dplyr::transmute(
    year,
    t_ai = year - 2015,
    L,
    RY,
    RK,
    W_PY,
    UCAP,
    UCAP_source,
    log_L,
    log_RY,
    log_RK,
    log_W_PY,
    log_UCAP
  ) |>
  dplyr::filter(
    is.finite(log_L), is.finite(log_RY), is.finite(log_W_PY)
  )

fit_labor_aug_ces <- stats::nls(
  log_L ~ c0 + log_RY - sigma * log_W_PY + (sigma - 1) * g_a * t_ai,
  data = ces_labor,
  start = list(c0 = 2.5, sigma = 0.5, g_a = 0.01),
  algorithm = "port",
  lower = c(c0 = -10, sigma = 0.05, g_a = -0.20),
  upper = c(c0 = 10, sigma = 5.00, g_a = 0.20),
  trace = FALSE
)

print(summary(fit_labor_aug_ces))

coef_labor_aug <- stats::coef(fit_labor_aug_ces)
sigma_hat <- unname(coef_labor_aug["sigma"])
g_a_hat <- unname(coef_labor_aug["g_a"])
a_labor_coef <- sigma_hat - 1

labor_aug_fit <- ces_labor |>
  dplyr::mutate(
    A_LABOR_hat = exp(g_a_hat * t_ai),
    fitted_log_L = stats::predict(fit_labor_aug_ces),
    fitted_L = exp(fitted_log_L),
    residual_log_L = log_L - fitted_log_L
  )

# readr::write_csv(
#   broom::tidy(fit_labor_aug_ces),
#   "output/labourforce_v2_labor_augmenting_ces_nls_coefficients.csv"
# )

# readr::write_csv(
#   tibble::tibble(
#     parameter = c("c0_hat", "sigma_hat", "g_a_hat", "a_labor_coef"),
#     estimate = c(unname(coef_labor_aug["c0"]), sigma_hat, g_a_hat, a_labor_coef)
#   ),
#   "output/labourforce_v2_labor_augmenting_ces_params.csv"
# )

#--- 合成ユーザーコストを使う感応度分析 --------------------------------------
# 基準モデルの安定性を優先し、UCAPは本文用の基準推計から外す。
# ただし、合成ユーザーコストを明示した代替仕様として、UCAP係数を自由係数で推計する。
#
# 労働需要関数の関係:
# 1. 当初の経験的需要式:
#    log(L) = c0 + c_y * log(Y) + c_w * log(W / P_Y) + c_lag * log(L[-1])
#    GDP、実質賃金、労働投入の調整遅れを使う、マクロ計量モデル向けの安定的な仕様。
# 2. 労働増大的CESの基準式:
#    log(L) = c0 + log(Y) - sigma * log(W / P_Y) + (sigma - 1) * log(A_LABOR)
#    当初式の賃金係数 c_w を -sigma と解釈し、AI・自動化・TFPをA_LABORとして明示した仕様。
# 3. UCAP入りCES比率式:
#    log(L) = c0 + log(K) - sigma * log(W / P_Y) + sigma * log(UCAP / P_Y)
#             + (sigma - 1) * log(A_LABOR)
#    資本と労働の相対価格を明示する理論式。ただし、合成UCAPは厳密な資本サービス価格と
#    完全に一致するとは限らないため、感応度分析ではUCAP係数をbeta_ucapとして自由推計する。
ucap_sensitivity_data <- ces_labor |>
  dplyr::filter(is.finite(log_RK), is.finite(log_UCAP))

fit_labor_aug_ces_ucap <- tryCatch(
  stats::nls(
    log_L ~ c0 + log_RK - sigma * log_W_PY + beta_ucap * log_UCAP + (sigma - 1) * g_a * t_ai,
    data = ucap_sensitivity_data,
    start = list(c0 = 2.2, sigma = 0.5, beta_ucap = 0.0, g_a = 0.01),
    algorithm = "port",
    lower = c(c0 = -30, sigma = 0.05, beta_ucap = -5.00, g_a = -0.20),
    upper = c(c0 = 30, sigma = 5.00, beta_ucap = 5.00, g_a = 0.20),
    trace = FALSE
  ),
  error = function(e) {
    warning("Skipping UCAP sensitivity model: ", conditionMessage(e))
    NULL
  }
)

if (!is.null(fit_labor_aug_ces_ucap)) {
  print(summary(fit_labor_aug_ces_ucap))

  coef_ucap <- stats::coef(fit_labor_aug_ces_ucap)

#   readr::write_csv(
#     broom::tidy(fit_labor_aug_ces_ucap),
#     "output/labourforce_v2_labor_augmenting_ces_ucap_sensitivity_coefficients.csv"
#   )

#   readr::write_csv(
#     tibble::tibble(
#       parameter = c("c0_hat", "sigma_hat", "beta_ucap_hat", "g_a_hat", "a_labor_coef"),
#       estimate = c(
#         unname(coef_ucap["c0"]),
#         unname(coef_ucap["sigma"]),
#         unname(coef_ucap["beta_ucap"]),
#         unname(coef_ucap["g_a"]),
#         unname(coef_ucap["sigma"]) - 1
#       )
#     ),
#     "output/labourforce_v2_labor_augmenting_ces_ucap_sensitivity_params.csv"
#   )
}

readr::write_csv(
  labor_aug_fit,
  "output/labourforce_v2_labor_augmenting_ces_fitted.csv"
)

#------- 今回の労働需要式を使ったbimets将来シミュレーション -------------------

suppressWarnings(suppressPackageStartupMessages({
  library(bimets)
  library(xts)
  library(ggplot2)
  library(gridExtra)
}))

without_warning_output <- function(expr) {
  value <- NULL
  output <- utils::capture.output(
    value <- suppressWarnings(suppressMessages(force(expr))),
    type = "output"
  )
  warning_output <- grepl("warning", output, ignore.case = TRUE) |
    grepl("Simulation will continue", output, fixed = TRUE) |
    grepl('Use the "FORECAST" option', output, fixed = TRUE)
  output <- output[!warning_output]
  if (length(output) > 0) cat(output, sep = "\n")
  value
}

logit <- function(x) log(x / (1 - x))

H_LOWER <- 85
H_UPPER <- 120
bounded_logit <- function(x, lower, upper) log((x - lower) / (upper - x))

proj_years <- 2026:2040
estimation_range <- c(1997, 1, 2025, 1)

lf_model_raw <- lf_raw |>
  dplyr::arrange(year)

model_frame <- tibble::tibble(year = all_years) |>
  dplyr::left_join(lf_model_raw, by = "year") |>
  dplyr::left_join(user_cost_data, by = "year") |>
  dplyr::mutate(
    date = as.Date(paste0(year, "-01-01")),
    RY = Y / D_GDP * 100,
    D_GDP = D_GDP / 100,
    D_C = D_C / 100,
    C_REAL = C / D_C,
    C_REAL_PC = C_REAL / POP,
    P = P / 100,
    LS = dplyr::if_else(year %in% hist_years, LS * 10, NA_real_),
    E = dplyr::if_else(year %in% hist_years, E * 10, NA_real_),
    W = dplyr::if_else(year %in% hist_years, W / 100, NA_real_),
    H = dplyr::if_else(year %in% hist_years, H, NA_real_),
    L = E * H,
    MHD = L,
    MHS = LS * H,
    U = LS - E,
    PartRate = LS / POP,
    U_rate = U / LS,
    lgtPartRate = logit(PartRate),
    lgtU_rate = logit(U_rate),
    lgtH = bounded_logit(H, H_LOWER, H_UPPER),
    E_RY = E / RY,
    MHD_RY = MHD / RY,
    E_est = E,
    W_PY = W / D_GDP,
    t_ai = year - 2015,
    log_L = log(L),
    log_RY = log(RY),
    log_W_PY = log(W_PY),
    log_C_REAL_PC = log(C_REAL_PC),
    log_W_P = log(W / P),
    lgtH_lag1 = dplyr::lag(lgtH, 1),
    U_rate_lag1 = dplyr::lag(U_rate, 1),
    lgtU_rate_lag1 = dplyr::lag(lgtU_rate, 1),
    dlog_W = log(W) - dplyr::lag(log(W), 1),
    dlog_P = log(P) - dplyr::lag(log(P), 1),
    dlog_TT = log(TT) - dplyr::lag(log(TT), 1)
  )

ces_labor_for_sim <- model_frame |>
  dplyr::filter(
    year >= 1997, year <= 2025,
    is.finite(log_L), is.finite(log_RY),
    is.finite(log_W_PY)
  )

fit_labor_aug_ces_for_sim <- stats::nls(
  log_L ~ c0 + log_RY - sigma * log_W_PY + (sigma - 1) * g_a * t_ai,
  data = ces_labor_for_sim,
  start = list(c0 = 2.5, sigma = 0.5, g_a = 0.01),
  algorithm = "port",
  lower = c(c0 = -10, sigma = 0.05, g_a = -0.20),
  upper = c(c0 = 10, sigma = 5.00, g_a = 0.20),
  trace = FALSE
)

print(summary(fit_labor_aug_ces_for_sim))

coef_demand_sim <- stats::coef(fit_labor_aug_ces_for_sim)
c0_sim <- unname(coef_demand_sim["c0"])
sigma_sim <- unname(coef_demand_sim["sigma"])
g_a_sim <- unname(coef_demand_sim["g_a"])
a_labor_coef_sim <- sigma_sim - 1

model_frame <- model_frame |>
  dplyr::mutate(
    log_A_LABOR = g_a_sim * t_ai,
    A_LABOR = exp(log_A_LABOR)
  )

readr::write_csv(
  tibble::tibble(
    parameter = c("c0_hat", "sigma_hat", "g_a_hat", "a_labor_coef"),
    estimate = c(c0_sim, sigma_sim, g_a_sim, a_labor_coef_sim)
  ),
  "output/labourforce_v2_bimets_labor_demand_params.csv"
)

model_estimation_data <- model_frame |>
  dplyr::filter(year >= 1997, year <= 2025)

lfpr_fit <- stats::lm(
  lgtPartRate ~ I(W / P) + U_rate_lag1,
  data = model_estimation_data
)

lfpr_last_obs <- model_estimation_data |>
  dplyr::filter(year == max(hist_years))

lfpr_last_obs_residual <- lfpr_last_obs$lgtPartRate -
  as.numeric(stats::predict(lfpr_fit, newdata = lfpr_last_obs))

lfpr_add_factor_decay_years <- 10

model_frame <- model_frame |>
  dplyr::mutate(
    ADD_LFPR = dplyr::case_when(
      year %in% hist_years ~ 0,
      year %in% proj_years ~
        lfpr_last_obs_residual *
        pmax(0, 1 - (year - min(proj_years)) / lfpr_add_factor_decay_years),
      TRUE ~ 0
    )
  )

model_data <- lapply(
  as.list(
    xts::xts(
      model_frame |>
        dplyr::select(
          -date,
          -log_L, -log_RY, -log_W_PY, -log_A_LABOR,
          -log_C_REAL_PC, -log_W_P, -lgtH_lag1, -U_rate_lag1,
          -lgtU_rate_lag1, -dlog_W, -dlog_P, -dlog_TT,
          -UCAP_source
        ) |>
        dplyr::select(where(is.numeric)),
      order.by = model_frame$date
    )
  ),
  as.bimets
)

demand_eq_text <- sprintf(
  "EQ> L = EXP(%.12f + LOG(RY) - %.12f * LOG(W / D_GDP) + %.12f * LOG(A_LABOR))",
  c0_sim,
  sigma_sim,
  a_labor_coef_sim
)

model_text <- paste0(
  "
MODEL
COMMENT> Labour Market Simulation V2 with Labor-Augmenting CES Demand

COMMENT> Labour Supply Side: Logit-transformed Labor Force Participation Rate
BEHAVIORAL> lgtPartRate TSRANGE 1997 1 2025 1
EQ> lgtPartRate = b1 + b2 * (W / P) + b3 * TSLAG(U_rate, 1)
COEFF> b1 b2 b3

COMMENT> Household Dynamic Optimization: Hours Supply
BEHAVIORAL> lgtH TSRANGE 1997 1 2025 1
EQ> lgtH = h1 + h2 * LOG(W / P) + h3 * LOG(C_REAL_PC) + h4 * TSLAG(lgtH, 1)
COEFF> h1 h2 h3 h4

COMMENT> Labour Demand Side: Labor-augmenting CES, L = MHD
COMMENT> A_LABOR is generated from the estimated trend: LOG(A_LABOR) = g_a * (year - 2015).
IDENTITY> L
",
  demand_eq_text,
  "

COMMENT> Labour Demand and Supply Adjustment: Logit-transformed Unemployment Rate and Wage Dynamics
BEHAVIORAL> lgtU_rate TSRANGE 1997 1 2025 1
EQ> lgtU_rate = a1 + a2 * (L / MHS) + a3 * TSLAG(lgtU_rate, 1)
COEFF> a1 a2 a3

BEHAVIORAL> W TSRANGE 1997 1 2025 1
EQ> TSDELTALOG(W, 1) = d1 + d2 * U_rate + d3 * TSDELTALOG(P, 1) + d4 * TSDELTALOG(TT, 1)
COEFF> d1 d2 d3 d4

COMMENT> Identity Equations to Derive Key Labor Market Indicators
IDENTITY> PartRate
EQ> PartRate = EXP(lgtPartRate) / (1 + EXP(lgtPartRate))

IDENTITY> U_rate
EQ> U_rate = EXP(lgtU_rate) / (1 + EXP(lgtU_rate))

IDENTITY> LS
EQ> LS = POP * PartRate

IDENTITY> H
EQ> H = 85 + (120 - 85) * EXP(lgtH) / (1 + EXP(lgtH))

IDENTITY> MHS
EQ> MHS = LS * H

IDENTITY> MHD
EQ> MHD = L

IDENTITY> E
EQ> E = L / H

IDENTITY> E_RY
EQ> E_RY = E / RY

IDENTITY> MHD_RY
EQ> MHD_RY = MHD / RY

IDENTITY> E_est
EQ> E_est = LS * (1 - U_rate)

IDENTITY> U
EQ> U = LS * U_rate

END
"
)

# writeLines(
#   model_text,
#   "output/labourforce_v2_bimets_model.txt",
#   useBytes = TRUE
# )

if (exists("model")) rm(model)
model <- without_warning_output(LOAD_MODEL(modelText = model_text))
model <- without_warning_output(LOAD_MODEL_DATA(model, model_data))
summary(model)

estimate_eqs <- c("lgtPartRate", "lgtH", "lgtU_rate", "W")

for (eq_name in estimate_eqs) {
  model <- without_warning_output(ESTIMATE(
    model,
    eqList = eq_name,
    TSRANGE = estimation_range,
    forceTSRANGE = TRUE,
    estTech = "OLS"
  ))
}

lfpr_constant_adjustment <- list(
  lgtPartRate = TIMESERIES(
    model_frame$ADD_LFPR[model_frame$year %in% proj_years],
    START = c(min(proj_years), 1),
    FREQ = "A"
  )
)

model <- without_warning_output(SIMULATE(
  model,
  TSRANGE = c(min(proj_years), 1, max(proj_years), 1),
  ConstantAdjustment = lfpr_constant_adjustment,
  SimType = "FORECAST"
))

get_sim <- function(name, years = proj_years) {
  if (!(name %in% names(model$simulation))) {
    return(
      model_frame |>
        dplyr::filter(year %in% years) |>
        dplyr::pull(dplyr::all_of(name))
    )
  }

  values <- tryCatch(
    as.numeric(fromBIMETStoTS(model$simulation[[name]])),
    error = function(e) as.numeric(model$simulation[[name]])
  )

  if (length(values) > length(years)) {
    values <- tail(values, length(years))
  }
  if (length(values) < length(years)) {
    values <- c(values, rep(NA_real_, length(years) - length(values)))
  }

  if (all(is.na(values)) && name %in% names(model_frame)) {
    values <- model_frame |>
      dplyr::filter(year %in% years) |>
      dplyr::pull(dplyr::all_of(name))
  }

  values
}

simulation_vars <- c(
  "POP", "RY", "D_GDP", "D_C", "P", "PG", "PG_TFP", "A_LABOR",
  "PartRate", "ADD_LFPR", "U_rate", "W", "H", "LS", "MHS",
  "E", "L", "MHD", "E_RY", "MHD_RY", "E_est", "U"
)

actual_results <- model_frame |>
  dplyr::filter(year %in% hist_years) |>
  dplyr::transmute(
    year,
    data_type = "actual",
    dplyr::across(dplyr::all_of(simulation_vars))
  )

simulation_results <- tibble::tibble(
  year = proj_years,
  data_type = "simulation",
  POP = get_sim("POP"),
  RY = get_sim("RY"),
  D_GDP = get_sim("D_GDP"),
  D_C = get_sim("D_C"),
  P = get_sim("P"),
  PG = get_sim("PG"),
  PG_TFP = get_sim("PG_TFP"),
  A_LABOR = get_sim("A_LABOR"),
  PartRate = get_sim("PartRate"),
  ADD_LFPR = get_sim("ADD_LFPR"),
  U_rate = get_sim("U_rate"),
  W = get_sim("W"),
  H = get_sim("H"),
  LS = get_sim("LS"),
  MHS = get_sim("MHS"),
  E = get_sim("E"),
  L = get_sim("L"),
  MHD = get_sim("MHD"),
  E_RY = get_sim("E_RY"),
  MHD_RY = get_sim("MHD_RY"),
  E_est = get_sim("E_est"),
  U = get_sim("U")
)

simulation_csv <- dplyr::bind_rows(actual_results, simulation_results)

readr::write_csv(
  simulation_csv,
  "output/labourforce_v2_bimets_simulation.csv"
)

# readr::write_csv(
#   simulation_csv,
#   "output/labour_force_simulation_v2.csv"
# )

actual_plot_df <- model_frame |>
  dplyr::filter(year %in% hist_years) |>
  dplyr::transmute(
    year,
    data_type = "actual",
    POP, RY, W, H, PartRate, U_rate, LS, MHS, E, L, MHD, E_est, A_LABOR
  )

simulation_plot_df <- simulation_results |>
  dplyr::select(
    year, data_type,
    POP, RY, W, H, PartRate, U_rate, LS, MHS, E, L, MHD, E_est, A_LABOR
  )

exogenous_plot_df <- model_frame |>
  dplyr::filter(year %in% proj_years) |>
  dplyr::transmute(
    year,
    data_type = "exogenous",
    POP, RY, W, H, PartRate, U_rate, LS, MHS, E, L, MHD, E_est, A_LABOR
  )

combined_plot_df <- dplyr::bind_rows(
  actual_plot_df,
  simulation_plot_df,
  exogenous_plot_df
)

plot_line <- function(data, y_var, title, y_label) {
  ggplot2::ggplot(data, ggplot2::aes(x = year, y = .data[[y_var]], color = data_type)) +
    ggplot2::geom_line(na.rm = TRUE) +
    ggplot2::geom_point(size = 1, na.rm = TRUE) +
    ggplot2::labs(title = title, x = "Year", y = y_label, color = "data_type") +
    ggplot2::theme_minimal()
}

p1 <- plot_line(combined_plot_df, "RY", "Real GDP (RY)", "RY")
p2 <- plot_line(combined_plot_df, "W", "Wage (W)", "W")
p3 <- plot_line(combined_plot_df, "PartRate", "Labor force participation rate", "PartRate")
p4 <- plot_line(combined_plot_df, "U_rate", "Unemployment rate", "U_rate")

le_plot_df <- combined_plot_df |>
  dplyr::select(year, data_type, LS, E_est) |>
  tidyr::pivot_longer(cols = c(LS, E_est), names_to = "series", values_to = "value")

p5 <- ggplot2::ggplot(
  le_plot_df,
  ggplot2::aes(x = year, y = value, color = series, linetype = data_type)
) +
  ggplot2::geom_line(na.rm = TRUE) +
  ggplot2::geom_point(size = 1, na.rm = TRUE) +
  ggplot2::labs(
    title = "Labor force (LS) and estimated employment (E_est)",
    x = "Year",
    y = "Number of people",
    color = "series",
    linetype = "data_type"
  ) +
  ggplot2::theme_minimal()

mh_plot_df <- combined_plot_df |>
  dplyr::select(year, data_type, MHS, MHD) |>
  tidyr::pivot_longer(cols = c(MHS, MHD), names_to = "series", values_to = "value")

p6 <- ggplot2::ggplot(
  mh_plot_df,
  ggplot2::aes(x = year, y = value, color = series, linetype = data_type)
) +
  ggplot2::geom_line(na.rm = TRUE) +
  ggplot2::geom_point(size = 1, na.rm = TRUE) +
  ggplot2::labs(
    title = "Labor supply man-hours (MHS) and labor demand man-hours (MHD)",
    x = "Year",
    y = "Man-hours",
    color = "series",
    linetype = "data_type"
  ) +
  ggplot2::theme_minimal()

p7 <- plot_line(combined_plot_df, "A_LABOR", "Labor-augmenting technology trend (A_LABOR)", "A_LABOR")

suppressWarnings({
  ggplot2::ggsave(
    "output/labourforce_v2_simulation_macro.png",
    gridExtra::arrangeGrob(p1, p2, p3, p4, ncol = 2),
    width = 12,
    height = 8,
    dpi = 150
  )
  ggplot2::ggsave(
    "output/labourforce_v2_simulation_people.png",
    gridExtra::arrangeGrob(p5, p6, p7, ncol = 1),
    width = 12,
    height = 12,
    dpi = 150
  )
})

print(simulation_results |> dplyr::select(year, PartRate, U_rate, W, H, E, L) |> head(10))
