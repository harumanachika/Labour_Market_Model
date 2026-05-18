# 将来推計の例：労働市場のシミュレーション
# 目的：過去のデータを基に、将来の労働市場の動向を予測する
# 使用する変数：人口（Pop）、GDP（Y）、物価（P）、労働力率（PartRate）、就業者数（E）、賃金（W）

suppressWarnings(suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(tibble)
  library(lubridate)
  library(xts)
  library(bimets)
  library(data.table)
  library(tseries)   # ADF検定（adf.test）
  library(urca)      # ADF / PP / KPSS 検定（ur.df, ur.pp, ur.kpss）
  library(DiagrammeR) # フローチャート作成用に追加
  library(htmlwidgets)
  library(webshot2)
}))

####作業ディレクトリ ---------------------------------------------------------

setwd("c:/Users/harum/GitHub/Labor_Force_Estimation/MacroModel/Sample/")
par(mfrow = c(1, 1))
# hgd()

safe_webshot <- function(...) {
  tryCatch(
    webshot2::webshot(...),
    error = function(e) warning("Skipping model_diagram.png: ", conditionMessage(e))
  )
}
webshot <- safe_webshot

# ---------------------------------------------------------
# 1. データの準備（実績 + 将来推計）
# ---------------------------------------------------------
# 過去：1995-2025、将来：2026-2040 と想定
hist_years <- 1995:2025
proj_years <- 2026:2040
all_years  <- 1995:2040

# --- 公的機関のデータ（想定）をセット ---
data <- readr::read_csv("data/data_LabourForce.csv", show_col_types = FALSE)  # 1995-2040年の実績・将来推計データ

logit <- function(x) log(x / (1 - x))

# 人口・GDP・物価は全期間、その他の実績値は過去期間のみセットする
data_obs <- tibble(year = all_years) |>
  dplyr::left_join(data, by = "year") |>
  dplyr::mutate(
    date  = lubridate::ymd(paste0(year, "-01-01")),
    POP   = POP,
    RY    = Y / D_GDP * 100,
    D_GDP = D_GDP / 100,
    P     = P / 100,
    dplyr::across(
      c(LS, E, W),
      ~ dplyr::if_else(year %in% hist_years, .x, NA_real_)
    ),
    LS       = LS * 10,                     # 労働力人口の実績値
    E        = E * 10,                      # 就業者数の実績値
    U        = LS - E,                      # 失業者数の実績値
    E_RY     = E / RY,                      # 実質GDPあたり就業者数（労働需要の投入係数）
    PartRate = LS / POP,                    # 労働力率の実績値
    U_rate   = U / LS,                      # 失業率の実績値
    lgtPartRate = logit(PartRate),          # 労働力率のロジット変換値
    lgtU_rate   = logit(U_rate),            # 失業率のロジット変換値
    E_est    = E,                           # 就業者数の実績値（推定用）
    W        = W / 100,                     # 賃金の実績値
    TT       = TT                           # 交易条件（全期間：外生変数として扱う）
  ) |>
  dplyr::select(
    date, POP, RY, D_GDP, P, LS, PartRate, lgtPartRate,
    E, E_RY, U, U_rate, lgtU_rate, E_est, W, TT
  ) |>
  data.table::as.data.table()

weak_iv_threshold <- 10
estimation_range <- c(1997, 1, 2025, 1)

estimation_check_data <- data_obs |>
  dplyr::mutate(
    W_P = W / P,
    W_P_lag1 = dplyr::lag(W / P, 1),
    U_rate_lag1 = dplyr::lag(U_rate, 1),
    U_rate_lag2 = dplyr::lag(U_rate, 2),
    E_LS = E / LS,
    E_LS_lag1 = dplyr::lag(E / LS, 1),
    lgtU_rate_lag1 = dplyr::lag(lgtU_rate, 1),
    lgtU_rate_lag2 = dplyr::lag(lgtU_rate, 2),
    log_E = log(E),
    log_E_lag1 = dplyr::lag(log(E), 1),
    log_E_lag2 = dplyr::lag(log(E), 2),
    log_RY = log(RY),
    log_RY_lag1 = dplyr::lag(log(RY), 1),
    log_W_D_GDP = log(W / D_GDP),
    log_W_D_GDP_lag1 = dplyr::lag(log(W / D_GDP), 1),
    log_W_D_GDP_lag2 = dplyr::lag(log(W / D_GDP), 2),
    dlog_W = log(W) - dplyr::lag(log(W), 1),
    dlog_P = log(P) - dplyr::lag(log(P), 1),
    dlog_P_lag1 = dplyr::lag(dlog_P, 1),
    dlog_TT = log(TT) - dplyr::lag(log(TT), 1),   # 交易条件の対数階差
    dlog_TT_lag1 = dplyr::lag(log(TT) - dplyr::lag(log(TT), 1), 1),  # 同1期ラグ（IV用）
    const = 1
  ) |>
  dplyr::filter(date >= lubridate::ymd("1997-01-01"),
                date <= lubridate::ymd("2025-01-01"))

demand_specs <- list(
  current_level = stats::lm(
    log(E) ~ log_RY + log_W_D_GDP_lag1 + log_E_lag1,
    data = estimation_check_data
  )
)

demand_spec_diagnostics <- lapply(names(demand_specs), function(spec_name) {
  fit <- demand_specs[[spec_name]]
  fit_summary <- summary(fit)
  coef_table <- stats::coef(fit_summary)
  wage_row <- coef_table[grep("log_W_D_GDP_lag1", rownames(coef_table), fixed = TRUE), , drop = FALSE]
  data.frame(
    spec = spec_name,
    real_wage_coef = wage_row[1, "Estimate"],
    real_wage_t = wage_row[1, "t value"],
    adj_r_squared = fit_summary$adj.r.squared,
    aic = stats::AIC(fit),
    dw_stat = sum(diff(stats::residuals(fit))^2) / sum(stats::residuals(fit)^2),
    stringsAsFactors = FALSE
  )
}) |>
  dplyr::bind_rows()

print(demand_spec_diagnostics)

supply_specs <- list(
  current = stats::lm(
    lgtPartRate ~ W_P + U_rate_lag1,
    data = estimation_check_data
  )
)

supply_spec_diagnostics <- lapply(names(supply_specs), function(spec_name) {
  fit <- supply_specs[[spec_name]]
  fit_summary <- summary(fit)
  coef_table <- stats::coef(fit_summary)
  wage_row <- coef_table[grep("W_P", rownames(coef_table), fixed = TRUE), , drop = FALSE]
  data.frame(
    spec = spec_name,
    real_wage_coef = wage_row[1, "Estimate"],
    real_wage_t = wage_row[1, "t value"],
    adj_r_squared = fit_summary$adj.r.squared,
    aic = stats::AIC(fit),
    dw_stat = sum(diff(stats::residuals(fit))^2) / sum(stats::residuals(fit)^2),
    stringsAsFactors = FALSE
  )
}) |>
  dplyr::bind_rows()

print(supply_spec_diagnostics)

# Supply-side add-factor -----------------------------------------------------
# Keep the supply equation without TSLAG(lgtPartRate, 1) so that the real-wage
# coefficient keeps the intended sign. ADD_LFPR connects the first projection
# year to the last observed participation-rate level, then fades out.
lfpr_add_factor_decay_years <- 10
lfpr_last_obs <- estimation_check_data |>
  dplyr::filter(date == lubridate::ymd(paste0(max(hist_years), "-01-01")))

lfpr_last_obs_fitted <- as.numeric(
  stats::predict(supply_specs[["current"]], newdata = lfpr_last_obs)
)
lfpr_last_obs_residual <- lfpr_last_obs$lgtPartRate - lfpr_last_obs_fitted

data_obs <- data_obs |>
  dplyr::mutate(
    ADD_LFPR = dplyr::case_when(
      lubridate::year(date) %in% hist_years ~ 0,
      lubridate::year(date) %in% proj_years ~
        lfpr_last_obs_residual *
        pmax(0, 1 - (lubridate::year(date) - min(proj_years)) /
                 lfpr_add_factor_decay_years),
      TRUE ~ 0
    )
  ) |>
  data.table::as.data.table()

lfpr_add_factor_diagnostics <- data.frame(
  year = lubridate::year(data_obs$date),
  ADD_LFPR = data_obs$ADD_LFPR
) |>
  dplyr::filter(year %in% c(max(hist_years), proj_years))

print(lfpr_add_factor_diagnostics)

model_data <- lapply(
  as.list(
    xts(data_obs |> dplyr::select(-date),
        order.by = data_obs$date)
  ),
  as.bimets
)

first_stage_f <- function(x, z, reduced_vars = "const") {
  fs_data <- data.frame(x = x, z, check.names = FALSE)
  fs_data <- fs_data[stats::complete.cases(fs_data), , drop = FALSE]
  z_names <- setdiff(names(fs_data), "x")
  reduced_vars <- intersect(reduced_vars, z_names)
  if (length(z_names) < 2 || length(reduced_vars) == 0 ||
      nrow(fs_data) <= length(z_names)) return(NA_real_)

  x_vec <- fs_data$x
  z_full <- as.matrix(fs_data[, z_names, drop = FALSE])
  z_reduced <- as.matrix(fs_data[, reduced_vars, drop = FALSE])
  fit_full <- stats::lm.fit(z_full, x_vec)
  fit_reduced <- stats::lm.fit(z_reduced, x_vec)

  q <- fit_full$rank - fit_reduced$rank
  if (q <= 0 || fit_full$df.residual <= 0) return(NA_real_)

  rss_full <- sum(fit_full$residuals^2)
  rss_reduced <- sum(fit_reduced$residuals^2)
  ((rss_reduced - rss_full) / q) / (rss_full / fit_full$df.residual)
}

first_stage_min_f <- function(data, x_vars, z_vars, reduced_vars = "const") {
  z <- as.data.frame(data)[, z_vars, drop = FALSE]
  stats <- vapply(
    x_vars,
    function(x_var) first_stage_f(data[[x_var]], z, reduced_vars),
    numeric(1)
  )
  list(stats = stats, min_f = suppressWarnings(min(stats, na.rm = TRUE)))
}

dwh_test <- function(data, y_var, structural_vars, endog_vars, z_vars) {
  test_vars <- unique(c(y_var, structural_vars, endog_vars, z_vars))
  test_data <- as.data.frame(data)[, test_vars, drop = FALSE]
  test_data <- test_data[stats::complete.cases(test_data), , drop = FALSE]

  if (nrow(test_data) <= length(structural_vars) + length(endog_vars)) {
    return(list(statistic = NA_real_, df = NA_integer_, p_value = NA_real_))
  }

  residual_names <- paste0("fs_resid_", endog_vars)
  z <- as.matrix(test_data[, z_vars, drop = FALSE])
  for (i in seq_along(endog_vars)) {
    fit_first_stage <- stats::lm.fit(z, test_data[[endog_vars[i]]])
    test_data[[residual_names[i]]] <- fit_first_stage$residuals
  }

  y <- test_data[[y_var]]
  x_restricted <- as.matrix(test_data[, structural_vars, drop = FALSE])
  x_unrestricted <- as.matrix(test_data[, c(structural_vars, residual_names), drop = FALSE])
  fit_restricted <- stats::lm.fit(x_restricted, y)
  fit_unrestricted <- stats::lm.fit(x_unrestricted, y)

  q <- fit_unrestricted$rank - fit_restricted$rank
  if (q <= 0 || fit_unrestricted$df.residual <= 0) {
    return(list(statistic = NA_real_, df = q, p_value = NA_real_))
  }

  rss_restricted <- sum(fit_restricted$residuals^2)
  rss_unrestricted <- sum(fit_unrestricted$residuals^2)
  statistic <- ((rss_restricted - rss_unrestricted) / q) /
    (rss_unrestricted / fit_unrestricted$df.residual)
  p_value <- stats::pf(
    statistic,
    df1 = q,
    df2 = fit_unrestricted$df.residual,
    lower.tail = FALSE
  )

  list(statistic = statistic, df = q, p_value = p_value)
}

without_warning_output <- function(expr) {
  value <- NULL
  output <- utils::capture.output(
    value <- suppressWarnings(force(expr)),
    type = "output"
  )
  warning_output <- grepl("warning", output, ignore.case = TRUE) |
    grepl("Simulation will continue", output, fixed = TRUE) |
    grepl('Use the "FORECAST" option', output, fixed = TRUE)
  output <- output[!warning_output]
  if (length(output) > 0) cat(output, sep = "\n")
  value
}

iv_specs <- list(
  lgtPartRate = list(
    IV = c("1", "TSLAG(W / P, 1)", "TSLAG(U_rate, 2)"),
    y_var = "lgtPartRate",
    structural_vars = c("const", "W_P", "U_rate_lag1"),
    endog_vars = c("W_P", "U_rate_lag1"),
    reduced_vars = "const",
    x_vars = c("W_P", "U_rate_lag1"),
    z_vars = c("const", "W_P_lag1", "U_rate_lag2")
  ),
  E = list(
    IV = c("1", "LOG(RY)", "TSLAG(LOG(W / D_GDP), 2)", "TSLAG(LOG(E), 2)"),
    y_var = "log_E",
    structural_vars = c("const", "log_RY", "log_W_D_GDP_lag1", "log_E_lag1"),
    endog_vars = c("log_W_D_GDP_lag1", "log_E_lag1"),
    reduced_vars = c("const", "log_RY"),
    x_vars = c("log_W_D_GDP_lag1", "log_E_lag1"),
    z_vars = c("const", "log_RY", "log_W_D_GDP_lag2", "log_E_lag2")
  ),
  lgtU_rate = list(
    IV = c("1", "TSLAG(E / LS, 1)", "TSLAG(lgtU_rate, 2)"),
    y_var = "lgtU_rate",
    structural_vars = c("const", "E_LS", "lgtU_rate_lag1"),
    endog_vars = c("E_LS", "lgtU_rate_lag1"),
    reduced_vars = "const",
    x_vars = c("E_LS", "lgtU_rate_lag1"),
    z_vars = c("const", "E_LS_lag1", "lgtU_rate_lag2")
  ),
  W = list(
    IV = c("1", "TSLAG(U_rate, 1)", "TSLAG(TSDELTALOG(P, 1), 1)", "TSLAG(TSDELTALOG(TT, 1), 1)"),
    y_var = "dlog_W",
    structural_vars = c("const", "U_rate", "dlog_P", "dlog_TT"),
    endog_vars = c("U_rate", "dlog_P", "dlog_TT"),
    reduced_vars = "const",
    x_vars = c("U_rate", "dlog_P", "dlog_TT"),
    z_vars = c("const", "U_rate_lag1", "dlog_P_lag1", "dlog_TT_lag1")
  )
)

iv_diagnostics <- lapply(names(iv_specs), function(eq_name) {
  spec <- iv_specs[[eq_name]]
  fs <- first_stage_min_f(
    estimation_check_data,
    spec$endog_vars,
    spec$z_vars,
    spec$reduced_vars
  )
  dwh <- dwh_test(
    estimation_check_data,
    spec$y_var,
    spec$structural_vars,
    spec$endog_vars,
    spec$z_vars
  )
  has_strong_iv <- is.finite(fs$min_f) && fs$min_f >= weak_iv_threshold
  has_endogeneity <- has_strong_iv &&
    is.finite(dwh$p_value) &&
    dwh$p_value < 0.05
  data.frame(
    equation = eq_name,
    min_first_stage_F = fs$min_f,
    dwh_F = dwh$statistic,
    dwh_df = dwh$df,
    dwh_p_value = dwh$p_value,
    estimation = ifelse(has_endogeneity, "IV", "OLS"),
    note = dplyr::case_when(
      !has_strong_iv ~ "OLS selected because the excluded instruments are weak.",
      !is.finite(dwh$p_value) ~ "OLS selected because the DWH test could not be computed.",
      dwh$p_value >= 0.05 ~ "OLS selected because DWH does not reject exogeneity.",
      TRUE ~ "IV selected because DWH rejects exogeneity."
    ),
    stringsAsFactors = FALSE
  )
}) |>
  dplyr::bind_rows()

print(iv_diagnostics)

# ---------------------------------------------------------
# 2. モデルの定義（労働市場にフォーカス）
# ---------------------------------------------------------
# ※ lag(lgtPartRate) がかなり強く効いており、賃金の水準効果を吸収している可能性。自己ラグを外すと供給の賃金係数は正。構造変化要因としてトレンド項を入れた場合、係数はマイナス。
model_text <- "
MODEL
COMMENT> Future Labor Market Simulation with Logit Transformation

COMMENT> Labour Supply Side: Logit-transformed Labor Force Participation Rate
BEHAVIORAL> lgtPartRate TSRANGE 1996 1 2025 1
EQ> lgtPartRate = b1 + b2 * (W / P) + b3 * TSLAG(U_rate, 1)
COEFF> b1 b2 b3

COMMENT> Labour Demand Side: Employment
BEHAVIORAL> E TSRANGE 1996 1 2025 1
EQ> LOG(E) = c1 + c2 * LOG(RY) + c3 * TSLAG(LOG(W / D_GDP), 1) + c4 * TSLAG(LOG(E), 1)
COEFF> c1 c2 c3 c4

COMMENT> Labour Demand and Supply Adjustment: Logit-transformed Unemployment Rate and Wage Dynamics
BEHAVIORAL> lgtU_rate TSRANGE 1996 1 2025 1
EQ> lgtU_rate = a1 + a2 * (E / LS) + a3 * TSLAG(lgtU_rate, 1)
COEFF> a1 a2 a3

BEHAVIORAL> W TSRANGE 1996 1 2025 1
EQ> TSDELTALOG(W, 1) = d1 + d2 * U_rate + d3 * TSDELTALOG(P, 1) + d4 * TSDELTALOG(TT, 1)
COEFF> d1 d2 d3 d4

COMMENT> Identity Equations to Derive Key Labor Market Indicators
IDENTITY> PartRate
EQ> PartRate = EXP(lgtPartRate) / (1 + EXP(lgtPartRate))

IDENTITY> U_rate
EQ> U_rate = EXP(lgtU_rate) / (1 + EXP(lgtU_rate))

IDENTITY> LS
EQ> LS = POP * PartRate

IDENTITY> E_RY
EQ> E_RY = E / RY

IDENTITY> E_est
EQ> E_est = LS * (1 - U_rate)

IDENTITY> U
EQ> U = LS * U_rate

END
"

# フローチャートでモデル構造を可視化
m <- mermaid("
graph TD
    %% --- 上段：3つのグループを横並びに配置 ---
    
    subgraph 'Demand Side'
        E[就業者需要: E]
        E_est[推定就業者数: E_est]
    end

    subgraph 'Adjustment Side'
        UR[失業率: U_rate]
        W[賃金: W]
    end

    subgraph 'Supply Side'
        PR[労働力率: PartRate]
        LS[労働力人口: LS]
    end

    %% --- 下段：外生変数 ---
    
    subgraph 'Exogenous'
        POP[人口: POP]
        RY[実質GDP: RY]
        D_GDP[GDPデフレータ: D_GDP]
        P[物価: P]
        TT[交易条件: TT]
    end

    %% --- 矢印の定義（関係性の確認） ---

    %% 外生変数からの入力
    POP --> LS
    RY --> E
    D_GDP --> E
    P --> W
    P --> PR
    TT --> W

    %% 調整サイド（賃金・失業率）の相互作用
    W --> E
    W --> PR
    UR --> W
    
    %% 需給から失業率への流れ
    E --> UR
    LS --> UR
    
    %% 供給サイド内部の流れ
    PR --> LS
    
    %% 最終出力への流れ
    UR --> E_est
    LS --> E_est

    %% 見栄えの調整（外生変数を下に押し下げるための非表示接続は使わず、
    %% 接続の方向性で自然に配置されるようにしています）
")

# 一旦、一時的なHTMLファイルとして保存
saveWidget(m, "temp.html", selfcontained = TRUE)

# そのHTMLを画像（PNG）として撮影
webshot("temp.html", file = "model_diagram.png", delay = 2) # delayで描画待ち時間を指定

# ---------------------------------------------------------
# 3. 推定とシミュレーション
# ---------------------------------------------------------
if (exists("model")) rm(model) # 既存のmodelがあれば削除
model <- LOAD_MODEL(modelText = model_text)
model <- without_warning_output(LOAD_MODEL_DATA(model, model_data))
summary(model)

# 過去データ(2025年まで)で係数を推定
for (eq_name in names(iv_specs)) {
  spec <- iv_specs[[eq_name]]
  est_method <- iv_diagnostics$estimation[iv_diagnostics$equation == eq_name]

  if (identical(est_method, "IV")) {
    model <- without_warning_output(ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "IV",
      IV = spec$IV,
      forceIV = TRUE
    ))
  } else {
    model <- without_warning_output(ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "OLS"
    ))
  }
}

# ---------------------------------------------------------
# 3b. 単位根検定（残差の定常性検定）
# ---------------------------------------------------------
# 各方程式の残差を取得し、ADF・PP・KPSS 検定を実施する
# ・ADF / PP: H0「単位根あり（非定常）」→ p < 0.05 で棄却 ⇒ 定常
# ・KPSS    : H0「定常」              → p < 0.05 で棄却 ⇒ 非定常
#
# 方程式名と対応する lm オブジェクトの対応
ur_eq_map <- list(
  lgtPartRate = supply_specs[["current"]],   # 労働供給：労働参加率（ロジット）
  E           = demand_specs[["current_level"]],  # 労働需要：就業者数
  lgtU_rate   = stats::lm(                 # 失業率（ロジット）：IV診断用 OLS 近似
    lgtU_rate ~ I(E / LS) + lgtU_rate_lag1,
    data = estimation_check_data
  ),
  W           = stats::lm(                 # 賃金方程式：OLS 近似
    dlog_W ~ U_rate + dlog_P + dlog_TT,
    data = estimation_check_data
  )
)

# 単位根検定の結果を格納する関数 -------------------------------------------
run_ur_tests <- function(eq_name, fit, lags = 1) {
  resid_vec <- stats::residuals(fit)
  resid_ts  <- stats::ts(resid_vec)
  n         <- length(resid_ts)

  # ---------- ADF 検定（urca::ur.df） ----------
  adf_obj  <- urca::ur.df(resid_ts, type = "none", lags = lags)
  adf_stat <- adf_obj@teststat[1]           # tau 統計量
  adf_cv   <- adf_obj@cval[1, ]            # 1%, 5%, 10% 臨界値
  # urca は p 値を直接返さないため tseries::adf.test で補完
  adf_p    <- tryCatch(
    tseries::adf.test(resid_ts, k = lags)$p.value,
    error = function(e) NA_real_
  )

  # ---------- PP 検定（urca::ur.pp） ----------
  pp_obj   <- urca::ur.pp(resid_ts, type = "Z-tau", model = "constant",
                           use.lag = lags)
  pp_stat  <- pp_obj@teststat[1]
  pp_cv    <- pp_obj@cval[1, ]

  # ---------- KPSS 検定（urca::ur.kpss） ----------
  kpss_obj  <- urca::ur.kpss(resid_ts, type = "mu", lags = "short")
  kpss_stat <- kpss_obj@teststat[1]
  kpss_cv   <- kpss_obj@cval[1, ]

  # ---------- 判定：ADF と PP の両方が定常 & KPSS が非棄却 ----------
  adf_stationary  <- adf_stat  < adf_cv["5pct"]   # 臨界値を下回れば単位根棄却
  pp_stationary   <- pp_stat   < pp_cv["5pct"]
  kpss_stationary <- kpss_stat < kpss_cv["5pct"]  # 臨界値を下回れば定常維持

  overall <- dplyr::case_when(
    adf_stationary & pp_stationary & kpss_stationary  ~ "定常（3検定とも支持）",
    adf_stationary & pp_stationary & !kpss_stationary ~ "条件付き定常（ADF・PP は支持、KPSS は非定常示唆）",
    (!adf_stationary | !pp_stationary) & kpss_stationary ~ "条件付き非定常（ADF・PPの一方が非定常示唆）",
    TRUE ~ "非定常（単位根の可能性）"
  )

  data.frame(
    equation     = eq_name,
    n_obs        = n,
    # ADF
    adf_stat     = round(adf_stat, 4),
    adf_cv_5pct  = round(adf_cv["5pct"], 4),
    adf_p        = round(adf_p, 4),
    adf_result   = ifelse(adf_stationary, "定常", "非定常"),
    # PP
    pp_stat      = round(pp_stat, 4),
    pp_cv_5pct   = round(pp_cv["5pct"], 4),
    pp_result    = ifelse(pp_stationary, "定常", "非定常"),
    # KPSS
    kpss_stat    = round(kpss_stat, 4),
    kpss_cv_5pct = round(kpss_cv["5pct"], 4),
    kpss_result  = ifelse(kpss_stationary, "定常", "非定常"),
    # 総合判定
    overall      = overall,
    stringsAsFactors = FALSE
  )
}

ur_results <- lapply(names(ur_eq_map), function(eq_name) {
  run_ur_tests(eq_name, ur_eq_map[[eq_name]], lags = 1)
}) |>
  dplyr::bind_rows()

# 結果の表示 ---------------------------------------------------------------
cat("\n", strrep("=", 72), "\n")
cat("  単位根検定結果（推定残差）\n")
cat("  検定: ADF（H0: 単位根あり）/ PP（H0: 単位根あり）/ KPSS（H0: 定常）\n")
cat("  有意水準 5%  |  ラグ次数: 1\n")
cat(strrep("=", 72), "\n\n")

for (i in seq_len(nrow(ur_results))) {
  r <- ur_results[i, ]
  cat(sprintf("【方程式: %-12s】  観測数: %d\n", r$equation, r$n_obs))
  cat(sprintf("  ADF  : 統計量 = %7.4f  臨界値(5%%) = %7.4f  → %s  (p = %.4f)\n",
              r$adf_stat, r$adf_cv_5pct, r$adf_result, r$adf_p))
  cat(sprintf("  PP   : 統計量 = %7.4f  臨界値(5%%) = %7.4f  → %s\n",
              r$pp_stat,  r$pp_cv_5pct,  r$pp_result))
  cat(sprintf("  KPSS : 統計量 = %7.4f  臨界値(5%%) = %7.4f  → %s\n",
              r$kpss_stat, r$kpss_cv_5pct, r$kpss_result))
  cat(sprintf("  総合判定: %s\n\n", r$overall))
}

cat(strrep("-", 72), "\n")
cat("※ ADF・PP で単位根が棄却され、KPSS で定常が維持される場合を\n")
cat("   「定常な残差」と判断します。残差が非定常の場合は、方程式の\n")
cat("   再定式化（変数変換・共和分関係の確認）を検討してください。\n")
cat(strrep("=", 72), "\n\n")

# 将来期間(2026-2040年)のシミュレーションを実行
# ここで POP と Y はデータとして与えられた値が使われます
lfpr_constant_adjustment <- list(
  lgtPartRate = TIMESERIES(
    data_obs$ADD_LFPR[lubridate::year(data_obs$date) %in% proj_years],
    START = c(min(proj_years), 1),
    FREQ = "A"
  )
)

model <- without_warning_output(SIMULATE(model,
                     TSRANGE = c(2026, 1, 2040, 1), 
                     # SimType = 'DYNAMIC')
                     ConstantAdjustment = lfpr_constant_adjustment,
                     SimType = 'FORECAST')) # 将来推計では、過去の動向を基に将来を予測するため、FORECASTモードも選択可能 

# ---------------------------------------------------------
# 4. 結果の確認
# ---------------------------------------------------------
TABIT(model$simulation$PartRate) # 労働力率の予測値
TABIT(model$simulation$U_rate) # 失業率の予測値
TABIT(model$simulation$W) # 賃金の予測値
TABIT(model$simulation$LS) # 労働力人口の予測値
TABIT(model$simulation$E) # 就業者数の予測値
TABIT(model$simulation$E_est) # 推定就業者数の予測値
TABIT(model$simulation$U) # 推定失業者数の予測値

# 予測された就業者数と労働力人口をプロット
main_res <- model$simulation
plot(main_res$LS, col="blue", lwd=2, ylim=c(min(main_res$E_est), max(main_res$LS)),
     xlab="Year", ylab="Number of People",
     main="Future Projection: Labor Force (LS) vs Employment (E)")
lines(main_res$E_est, col="red", lwd=2)
legend("bottomright", legend=c("Labor Force (LS)", "Employment (E)"), col=c("blue", "red"), lwd=2)

# ---------------------------------------------------------
# 5. 実績値とシミュレーション結果のCSV出力
# ---------------------------------------------------------
simulation_vars <- c("POP", "RY", "D_GDP", "P", "PartRate", "ADD_LFPR", "U_rate",
                     "W", "LS", "E", "E_RY", "E_est", "U")

simulation_to_df <- function(simulation, years, vars, fallback_data) {
  out <- fallback_data |>
    dplyr::filter(lubridate::year(date) %in% years) |>
    dplyr::transmute(
      year = lubridate::year(date),
      dplyr::across(dplyr::all_of(vars))
    ) |>
    as.data.frame()

  for (var in vars) {
    if (var %in% names(simulation) && length(simulation[[var]]) > 0) {
      values <- as.numeric(simulation[[var]])
      if (length(values) != length(years)) {
        values <- tail(values, length(years))
      }
      out[[var]] <- values
    }
  }
  out
}

actual_results <- data_obs |>
  dplyr::filter(lubridate::year(date) %in% hist_years) |>
  dplyr::transmute(
    year = lubridate::year(date),
    dplyr::across(dplyr::all_of(simulation_vars)),
    data_type = "actual"
  )

simulation_results <- simulation_to_df(
  model$simulation,
  years = proj_years,
  vars = simulation_vars,
  fallback_data = data_obs
) |>
  dplyr::mutate(data_type = "simulation")

simulation_csv <- dplyr::bind_rows(actual_results, simulation_results) |>
  dplyr::select(year, data_type, dplyr::all_of(simulation_vars))

dir.create("output", showWarnings = FALSE, recursive = TRUE)
readr::write_csv(simulation_csv, "output/labour_force_simulation.csv")
