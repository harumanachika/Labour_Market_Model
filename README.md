---
title: "簡易モデルによる労働市場の将来推計"
author: "Manabu Watanabe"
date: "`r Sys.Date()`"
output:
  html_document:
    toc: true
    toc_depth: 2
    number_sections: false
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(
  echo = TRUE,
  warning = FALSE,
  message = FALSE
)
```

## アブストラクト

本リポートでは、わが国の構造的な人口減少局面における労働市場の動態を把握するため、1995年から2025年までの実績データに基づき小規模マクロ計量モデルを推計し、2026年から2040年までの将来シミュレーションを行った。

人口動態、実質GDP、物価、および交易条件を外生条件としたシミュレーションの結果、実質GDPの持続的成長を仮定した場合であっても、将来の成長パターンが「資本集約的」である（すなわち労働需要のGDP弾力性が低い）ケースにおいては、供給側の労働力率上昇と相まって、人口減少下であっても労働市場がタイト化せず、かえって失業率が上昇基調をたどるという「マクロ需給のねじれ」のシナリオが示された。この挙動は、単なるマクロ成長の追求だけでなく、雇用の吸収力（労働集約度）やミスマッチ緩和策の成否が将来の雇用安定に決定的な影響を与えることを示唆している。

なお、記載の内容は個人の見解であり、所属する組織の見解を示すものではない。

## データの準備とモデルの位置づけ

分析期間は、構造推定期間を1995年から2025年（実績値）、将来シミュレーション期間を2026年から2040年とする。

本分析で用いるモデルは、人口、実質GDP、物価、交易条件を外生変数として与え、労働力率、失業率、就業者数、賃金（時間給）を内生的に決定する動学的小規模マクロ計量モデル（構造方程式システム）である。労働力率および失業率は0から1の範囲に収まる比率であるため、確率論的境界を担保すべく、推定式ではロジット変換（Logit Transformation）を施している。

数値の単位は、人口、労働力人口、就業者数、失業者数は千人、実質GDPは10億円、賃金、物価は2020年を1とした指数である。また、交易条件は、それぞれ2020年基準の輸出物価（取引通貨建て）を輸入物価（円建て）で除すことで算出している。

```{r libraries}
library(tidyverse)
library(data.table)
library(lubridate)
library(xts)
library(bimets)
library(tseries)
library(urca)
library(ggplot2)
library(gridExtra)
```

```{r data-preparation}
hist_years <- 1995:2025
proj_years <- 2026:2040
all_years  <- 1995:2040

data <- readr::read_csv("data/data_LabourForce.csv", show_col_types = FALSE)

logit <- function(x) log(x / (1 - x))

data_obs <- tibble(year = all_years) |>
  left_join(data, by = "year") |>
  mutate(
    date  = ymd(paste0(year, "-01-01")),
    POP   = POP,
    D_GDP = D_GDP / 100,
    RY    = Y / D_GDP * 100,
    P     = P / 100,
    TT    = TT,
    Trend = seq_along(year),
    across(
      c(LS, E, W),
      ~ if_else(year %in% hist_years, .x, NA_real_)
    ),
    LS          = LS * 10,
    E           = E * 10,
    E_RY        = E / RY,
    U           = LS - E,
    PartRate    = LS / POP,
    U_rate      = U / LS,
    lgtPartRate = logit(PartRate),
    lgtU_rate   = logit(U_rate),
    E_est       = E,
    W           = W / 100
  ) |>
  select(
    date, POP, RY, D_GDP, P, TT, LS, PartRate, lgtPartRate,
    E, E_RY, U, U_rate, lgtU_rate, E_est, W, Trend
  ) |>
  as.data.table()

head(data_obs)
```

データ加工後の主な内生・外生変数は以下の通りである。

| 変数 | 内容 | 資料出所 |
|---|---|---|
| `POP` | 人口（外生） | 国立社会保障・人口問題研究所「将来推計人口」（出生中位・死亡中位） |
| `RY` | 実質GDP（外生） | 内閣府「四半期別GDP統計」、 内閣府「中長期の経済財政に関する試算」（過去投影ケース） |
| `D_GDP` | GDPデフレーター（外生） | 内閣府「四半期別GDP統計」、 内閣府「中長期の経済財政に関する試算 |
| `P` | 物価（外生） | 総務省統計局「消費者物価指数」（総合）、 内閣府「中長期の経済財政に関する試算」（過去投影ケース）|
| `LS` | 労働力人口（内生） | 総務省統計局「労働力調査」 |
| `E` | 就業者数（内生） | 総務省統計局「労働力調査」 |
| `PartRate` | 労働力率（内生） | `LS / POP`から恒等式により算出 |
| `U_rate` | 失業率（内生） | `(LS - E) / LS`から恒等式により算出 |
| `W` | 賃金（内生・時間給） | 厚生労働省「毎月勤労統計調査」（現金給与総額・総実労働時間） |
| `TT` | 交易条件（内生） | 日本銀行「企業物価指数」（輸出物価指数・輸入物価指数、2026年以降は横置き仮定） |
| `Trend` | トレンド変数 | 時間トレンド（決定論的トレンドの制御用） |

サンプル期間のベンチマークとして、1995年時点の労働力率は約0.632、完全失業率は約0.031、2000年時点ではそれぞれ約0.624、約0.047である。実績値の最終年である2025年時点では、労働力率は約0.641、完全失業率は約0.022となっている。

```{r model-data}
model_data <- lapply(
  as.list(
    xts(data_obs |> select(-date), order.by = data_obs$date)
  ),
  as.bimets
)
```

モデルを構成する4本の行動方程式の推定にあたっては、同時決定バイアスや説明変数の内生性を制御するため、原則として説明変数の1期前ラグ等を操作変数に用いる操作変数法（IV）を試みる。ただし、操作変数の識別力を担保するため、第一段階回帰のF統計量が weak_iv_threshold = 10（Staiger-Stockの基準）を下回る場合は「弱操作変数（Weak Instruments）」と判定し、頑健性の観点から通常の最小二乗法（OLS）を採用する。

具体的には、各方程式について第一段階のF統計量を計算して推定手法（IV/OLS）を自動判定し、さらにDurbin-Wu-Hausman（DWH）検定によって外生性の拒絶の有無（IV推定の必要性）を確認する。ラグ構造の存在から、実際の推定期間は1997年から2025年とする。

```{r iv-setup}
weak_iv_threshold <- 10
estimation_range <- c(1997, 1, 2025, 1)

estimation_check_data <- data_obs |>
  mutate(
    W_P = W / P,
    W_P_lag1 = lag(W / P, 1),
    U_rate_lag1 = lag(U_rate, 1),
    U_rate_lag2 = lag(U_rate, 2),
    log_E = log(E),
    lgtPartRate_lag1 = lag(lgtPartRate, 1),
    lgtPartRate_lag2 = lag(lgtPartRate, 2),
    E_LS = E / LS,
    E_LS_lag1 = lag(E / LS, 1),
    lgtU_rate_lag1 = lag(lgtU_rate, 1),
    lgtU_rate_lag2 = lag(lgtU_rate, 2),
    log_E_lag1 = lag(log(E), 1),
    log_E_lag2 = lag(log(E), 2),
    log_RY = log(RY),
    log_RY_lag1 = lag(log(RY), 1),
    log_W_P = log(W / P),
    log_W_P_lag1 = lag(log(W / P), 1),
    log_W_D_GDP = log(W / D_GDP),
    log_W_D_GDP_lag1 = lag(log(W / D_GDP), 1),
    log_W_D_GDP_lag2 = lag(log(W / D_GDP), 2),
    dlog_P = log(P) - lag(log(P), 1),
    dlog_P_lag1 = lag(dlog_P, 1),
    dlog_W = log(W) - lag(log(W), 1),
    dlog_TT = log(TT) - lag(log(TT), 1),
    const = 1
  ) |>
  filter(date >= ymd("1997-01-01"), date <= ymd("2025-01-01"))

first_stage_f <- function(x, z) {
  fs_data <- data.frame(x = x, z, check.names = FALSE)
  fs_data <- fs_data[complete.cases(fs_data), , drop = FALSE]
  z_names <- setdiff(names(fs_data), "x")
  if (length(z_names) < 2 || nrow(fs_data) <= length(z_names)) return(NA_real_)

  x_vec <- fs_data$x
  z_full <- as.matrix(fs_data[, z_names, drop = FALSE])
  z_reduced <- matrix(1, nrow = nrow(fs_data), ncol = 1)
  fit_full <- lm.fit(z_full, x_vec)
  fit_reduced <- lm.fit(z_reduced, x_vec)

  q <- fit_full$rank - fit_reduced$rank
  if (q <= 0 || fit_full$df.residual <= 0) return(NA_real_)

  rss_full <- sum(fit_full$residuals^2)
  rss_reduced <- sum(fit_reduced$residuals^2)
  ((rss_reduced - rss_full) / q) / (rss_full / fit_full$df.residual)
}

first_stage_min_f <- function(data, x_vars, z_vars) {
  z <- as.data.frame(data)[, z_vars, drop = FALSE]
  stats <- vapply(
    x_vars,
    function(x_var) first_stage_f(data[[x_var]], z),
    numeric(1)
  )
  list(stats = stats, min_f = suppressWarnings(min(stats, na.rm = TRUE)))
}

first_stage_f <- function(x, z, reduced_vars = "const") {
  fs_data <- data.frame(x = x, z, check.names = FALSE)
  fs_data <- fs_data[complete.cases(fs_data), , drop = FALSE]
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
  df <- as.data.frame(data)
  z <- df[, intersect(z_vars, names(df)), drop = FALSE]
  stats <- vapply(
    x_vars,
    function(x_var) {
      if (!x_var %in% names(df)) return(NA_real_)
      first_stage_f(df[[x_var]], z, reduced_vars)
    },
    numeric(1)
  )
  list(stats = stats, min_f = suppressWarnings(min(stats, na.rm = TRUE)))
}

dwh_test <- function(data, y_var, structural_vars, endog_vars, z_vars) {
  df <- as.data.frame(data)
  test_vars <- unique(c(y_var, structural_vars, endog_vars, z_vars))
  missing_vars <- setdiff(test_vars, names(df))
  if (length(missing_vars) > 0) {
    warning("dwh_test: missing variables: ", paste(missing_vars, collapse = ", "))
  }
  test_data <- df[, intersect(test_vars, names(df)), drop = FALSE]
  test_data <- test_data[complete.cases(test_data), , drop = FALSE]
  # determine which of the requested variables are actually present
  structural_present <- intersect(structural_vars, names(test_data))
  endog_present <- intersect(endog_vars, names(test_data))
  z_present <- intersect(z_vars, names(test_data))

  if (length(endog_present) == 0) {
    return(list(statistic = NA_real_, df = NA_integer_, p_value = NA_real_))
  }

  if (nrow(test_data) <= length(structural_present) + length(endog_present)) {
    return(list(statistic = NA_real_, df = NA_integer_, p_value = NA_real_))
  }

  residual_names <- paste0("fs_resid_", endog_present)
  z_mat <- as.matrix(test_data[, z_present, drop = FALSE])
  if (ncol(z_mat) == 0) z_mat <- matrix(1, nrow = nrow(test_data), ncol = 1)
  for (i in seq_along(endog_present)) {
    y_endog <- test_data[[endog_present[i]]]
    fit_first_stage <- stats::lm.fit(z_mat, y_endog)
    test_data[[residual_names[i]]] <- fit_first_stage$residuals
  }

  if (!y_var %in% names(test_data)) {
    return(list(statistic = NA_real_, df = NA_integer_, p_value = NA_real_))
  }
  y <- test_data[[y_var]]
  x_restricted <- as.matrix(test_data[, structural_present, drop = FALSE])
  x_unrestricted <- as.matrix(test_data[, c(structural_present, residual_names), drop = FALSE])
  if (ncol(x_restricted) == 0) x_restricted <- matrix(1, nrow = nrow(test_data), ncol = 1)
  if (ncol(x_unrestricted) == 0) x_unrestricted <- matrix(1, nrow = nrow(test_data), ncol = 1)
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

iv_specs <- list(
  lgtPartRate = list(
    IV = c("1", "TSLAG(W / P, 1)", "TSLAG(U_rate, 2)", "TSLAG(lgtPartRate, 2)"),
    y_var = "lgtPartRate",
    structural_vars = c("const", "W_P", "U_rate_lag1"),
    endog_vars = c("W_P", "U_rate_lag1"),
    reduced_vars = "const",
    x_vars = c("W_P", "U_rate_lag1"),
    z_vars = c("const", "W_P_lag1", "U_rate_lag2", "lgtPartRate_lag2")
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
  bind_rows()
```

## モデルの構造化と理論的背景

本構造モデルは、以下の4本の行動方程式と4本の定義上の恒等式から構成される半構造化マクロ計量システムである。

### 労働供給ブロック（労働力率方程式）

被説明変数を労働力率のロジット変換値 lgtPartRate とし、説明変数には実質賃金（W / P）および就業意欲喪失効果（Discouraged Worker Effect）を捕捉するための1期前の完全失業率（U_rate）を配する。
実質賃金の係数はプラス（代替効果が所得効果を上回る仮定）、失業率の係数はマイナスを想定している。動学構造（分布ラグ）の導入は実質賃金の符号条件に不整合をもたらしたため、本ブロックは静学方程式として特定化している。

### 労働需要ブロック（就業者数方程式）

コブ＝ダグラス型生産関数および限界生産力命題（要素価格＝限界生産力）の理論的帰結に基づき、対数線形モデル（定常状態における代替の弾力性＝1）を基本構造とする。就業者数 E の対数値を被説明変数とし、実質GDP（RY）および要素価格である実質賃金（W / D_GDP、調整ラグを考慮し1期ラグ）を配置。さらに、雇用の動学的な流動性摩擦（調整コスト）を制御するため、被説明変数の自期ラグを投入した部分調整モデル（Partial Adjustment Model）を構築している。

### 労働市場ブロック（調整メカニズム）

市場の不均衡調整および価格形成として以下の2式を特定化する。

+ 失業率動学方程式: マクロ的な労働需給バランスの代替指標として、就業者数／労働力人口比率（E / LS、すなわち雇用率）を説明変数とし、調整の持続性を制御するラグ項を加えたロジット分布ラグモデル。

+ 賃金形成方程式（マクロ・フィリップス・カーブ）: 名目賃金上昇率（TSDELTALOG(W)）を被説明変数とし、労働市場のタイトネスを示す失業率（U_rate）、インフレ期待の代理変数（物価上昇率 TSDELTALOG(P)）、および交易条件の変化率（TSDELTALOG(TT)）を説明変数とする。期待形成を含む拡張型フィリップス・カーブの系譜に属する。

```{r model-definition}
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

quiet_load <- function(expr) {
  tmp <- tempfile()
  con <- file(tmp, open = "wt")
  sink(con)
  sink(con, type = "message")

  res <- tryCatch(
    eval(substitute(expr), envir = parent.frame()),
    error = function(e) e,
    finally = {
      sink(NULL)
      sink(NULL, type = "message")
      close(con)
    }
  )

  out <- readLines(tmp, warn = FALSE)
  keep <- !grepl("^\\s*LOAD_MODEL(?:_DATA)?\\(\\): warning", out, ignore.case = TRUE, perl = TRUE)
  if (any(keep)) cat(paste(out[keep], collapse = "\n"), "\n")

  if (inherits(res, "error")) stop(res)
  invisible(res)
}

model <- quiet_load(LOAD_MODEL(modelText = model_text))
model <- quiet_load(LOAD_MODEL_DATA(model, model_data))
summary(model)
```

## 推定結果および統計的検証

```{r estimation}
## 標準出力／メッセージ／警告を抑えて `ESTIMATE()` を実行するヘルパー
run_quiet <- function(expr) {
  # Capture printed output and suppress only ESTIMATE() warning lines.
  res <- NULL
  out <- utils::capture.output({
    res <- withCallingHandlers(
      eval(substitute(expr), envir = parent.frame()),
      warning = function(w) {
        if (grepl("^\\s*ESTIMATE\\(\\): warning", conditionMessage(w),
                  ignore.case = TRUE, perl = TRUE)) {
          invokeRestart("muffleWarning")
        }
      }
    )
  }, type = "output")

  keep <- !grepl("^\\s*ESTIMATE\\(\\): warning", out, ignore.case = TRUE, perl = TRUE)
  if (any(keep)) cat(paste(out[keep], collapse = "\n"), "\n")
  invisible(res)
}

for (eq_name in names(iv_specs)) {
  spec <- iv_specs[[eq_name]]
  est_method <- iv_diagnostics$estimation[iv_diagnostics$equation == eq_name]

  if (identical(est_method, "IV")) {
    res <- run_quiet(ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "IV",
      IV = spec$IV,
      forceIV = TRUE
    ))
  } else {
    res <- run_quiet(ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "OLS"
    ))
  }
  if (!is.null(res)) model <- res
}
```

識別条件および外生性検定の判定結果、および各方程式の適合度（決定係数）は以下の通りである。

```{r iv-diagnostics-table}
iv_diagnostics
```

## 残差の定常性検証（単位根検定）

推定方程式の残差におけるスプリアス回帰（見せかけの回帰）のリスクを排除するため、ADF、PP、KPSSの3つの手法による単位根検定を実施した。

```{r unit-root-tests}
ur_eq_map <- list(
  lgtPartRate = stats::lm(
    lgtPartRate ~ const + W_P + U_rate_lag1,
    data = estimation_check_data
  ),
  E = stats::lm(
    log_E ~ const + log_RY + log_W_D_GDP_lag1 + log_E_lag1,
    data = estimation_check_data
  ),
  lgtU_rate = stats::lm(
    lgtU_rate ~ const + E_LS + lgtU_rate_lag1,
    data = estimation_check_data
  ),
  W = stats::lm(
    dlog_W ~ const + U_rate + dlog_P + dlog_TT,
    data = estimation_check_data
  )
)

run_ur_tests <- function(eq_name, fit, lags = 1) {
  resid_ts <- stats::ts(stats::residuals(fit))

  adf_obj  <- urca::ur.df(resid_ts, type = "none", lags = lags)
  adf_stat <- adf_obj@teststat[1]
  adf_cv   <- adf_obj@cval[1, ]
  adf_p    <- tryCatch(
    tseries::adf.test(resid_ts, k = lags)$p.value,
    error = function(e) NA_real_
  )

  pp_obj  <- urca::ur.pp(resid_ts, type = "Z-tau", model = "constant", use.lag = lags)
  pp_stat <- pp_obj@teststat[1]
  pp_cv   <- pp_obj@cval[1, ]

  kpss_obj  <- urca::ur.kpss(resid_ts, type = "mu", lags = "short")
  kpss_stat <- kpss_obj@teststat[1]
  kpss_cv   <- kpss_obj@cval[1, ]

  adf_stationary  <- adf_stat  < adf_cv["5pct"]
  pp_stationary   <- pp_stat   < pp_cv["5pct"]
  kpss_stationary <- kpss_stat < kpss_cv["5pct"]

  overall <- dplyr::case_when(
    adf_stationary & pp_stationary & kpss_stationary  ~ "定常（3検定とも支持）",
    adf_stationary & pp_stationary & !kpss_stationary ~ "条件付き定常（ADF・PP は支持、KPSS は非定常示唆）",
    (!adf_stationary | !pp_stationary) & kpss_stationary ~ "条件付き非定常（ADF・PPの一方が非定常示唆）",
    TRUE ~ "非定常（単位根の可能性）"
  )

  data.frame(
    equation     = eq_name,
    n_obs        = length(resid_ts),
    adf_stat     = round(adf_stat, 4),
    adf_cv_5pct  = round(adf_cv["5pct"], 4),
    adf_p        = round(adf_p, 4),
    adf_result   = ifelse(adf_stationary, "定常", "非定常"),
    pp_stat      = round(pp_stat, 4),
    pp_cv_5pct   = round(pp_cv["5pct"], 4),
    pp_result    = ifelse(pp_stationary, "定常", "非定常"),
    kpss_stat    = round(kpss_stat, 4),
    kpss_cv_5pct = round(kpss_cv["5pct"], 4),
    kpss_result  = ifelse(kpss_stationary, "定常", "非定常"),
    overall      = overall,
    stringsAsFactors = FALSE
  )
}

ur_results <- lapply(names(ur_eq_map), function(eq_name) {
  run_ur_tests(eq_name, ur_eq_map[[eq_name]], lags = 1)
}) |>
  bind_rows()

knitr::kable(ur_results, caption = "単位根検定結果（推定残差）")
```

各方程式の推計パラメータの理論的整合性は以下の通り要約される。

| 方程式 | 理論的符合・有意性 | 自由度修正済決定係数（$\bar{R}^2$） |
|---|---:|---:|
| 労働力率 `lgtPartRate` | 実質賃金：有意な正、失業率ラグ：有意な負（就業意欲喪失効果を立証） | 0.589 |
| 就業者数 `E` | 実質GDP：有意な正、実質賃金：有意な正、調整ラグの有意性高 | 0.975 |
| 失業率 `lgtU_rate` | 雇用率（E/LS）：有意な負、失業率ラグ：有意な正（動学の持続性） | 0.990 |
| 賃金 `W` | 失業率：有意な負（フィリップス曲線の成立）、物価：正（やや有意）、交易条件：正（限定的） | 0.657 |

就業者数および失業率方程式は動学ラグ項の寄与もあり極めて高い説明力を示す一方、労働力率と名目賃金（階差型）の決定係数は相対的に低く、構造的なショック（外生的な労働供給行動の変化や春闘等の制度的要因）による攪乱を内包している点に留意が必要である。

## 将来シミュレーション

以下では、実績（1995–2025年）とモデルによる将来シミュレーション（2026–2040年）を併せて示し、実質GDP（`RY`）、賃金（`W`）、労働力率（`PartRate`）、失業率（`U_rate`）、労働力人口（`LS`）及び就業者数（`E`）の動きを確認する。実績値（1995～2025年）と予測値・モデルによる将来シミュレーション（2026～2040年）をあわせて表示する。

```{r simulate, warning=TRUE}
## 警告出力を抑えるヘルパー（ログやwarningを一部除外して実行結果だけ得る）
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

# 将来シミュレーションを実行（without_warning_output で不要な警告を抑える）
model <- without_warning_output(SIMULATE(model, TSRANGE = c(2026, 1, 2040, 1), SimType = 'FORECAST'))
```

```{r projection-plots, fig.width=10, fig.height=8}
# 実績データの抽出（POP, LS, E を含め雇用率を計算可能にする）
actual_df <- data_obs |>
  dplyr::mutate(year = lubridate::year(date)) |>
  dplyr::filter(year %in% hist_years) |>
  dplyr::select(year, POP, RY, W, PartRate, U_rate, LS, E) |>
  dplyr::mutate(
    employment_rate = E / POP,
    data_type = "actual"
  )

# シミュレーション結果の整形（bimets 型か生の数値か両方に対応）
get_sim <- function(name) {
  if (!(name %in% names(model$simulation))) return(rep(NA_real_, length(proj_years)))
  v <- model$simulation[[name]]
  val <- tryCatch({
    as.numeric(fromBIMETStoTS(v))
  }, error = function(e) {
    x <- tryCatch(as.numeric(v), error = function(e2) NA_real_)
    if (is.numeric(x)) x else rep(NA_real_, length(proj_years))
  })
  if (length(val) != length(proj_years)) {
    if (length(val) > length(proj_years)) val <- tail(val, length(proj_years))
    else val <- c(val, rep(NA_real_, length(proj_years) - length(val)))
  }
  val
}

# 将来人口（POP）は data_obs に含まれているため先に抽出
proj_pop <- data_obs |>
  dplyr::mutate(year = lubridate::year(date)) |>
  dplyr::filter(year %in% proj_years) |>
  dplyr::pull(POP)

sim_df <- tibble(
  year = proj_years,
  POP = proj_pop,
  RY = get_sim("RY"),
  W = get_sim("W"),
  PartRate = get_sim("PartRate"),
  U_rate = get_sim("U_rate"),
  LS = get_sim("LS"),
  E = get_sim("E"),
  data_type = "simulation"
)

sim_df <- sim_df |>
  dplyr::mutate(
    employment_rate = ifelse(!is.na(E) & !is.na(POP), E / POP, NA_real_)
  )

# 外生の予測値（データファイルに含まれる RY）を取り出してプロットに重ねる
exog_df <- data_obs |>
  dplyr::mutate(year = lubridate::year(date)) |>
  dplyr::filter(year %in% proj_years) |>
  dplyr::select(year, POP, RY, W = W, PartRate = PartRate, U_rate = U_rate, LS = LS, E = E) |>
  dplyr::mutate(
    data_type = "exogenous"
  )

combined <- dplyr::bind_rows(actual_df, sim_df, exog_df)

p1 <- ggplot(combined, aes(x = year, y = RY, color = data_type)) +
  geom_line() + geom_point(size = 1) +
  labs(title = "実質GDP (RY)", x = "Year", y = "RY") +
  theme_minimal()

p2 <- ggplot(combined, aes(x = year, y = W, color = data_type)) +
  geom_line() + geom_point(size = 1) +
  labs(title = "賃金 (W)", x = "Year", y = "W") +
  theme_minimal()

p3 <- ggplot(combined, aes(x = year, y = PartRate, color = data_type)) +
  geom_line() + geom_point(size = 1) +
  labs(title = "労働力率 (PartRate)", x = "Year", y = "PartRate") +
  theme_minimal()

p4 <- ggplot(combined, aes(x = year, y = U_rate, color = data_type)) +
  geom_line() + geom_point(size = 1) +
  labs(title = "失業率 (U_rate)", x = "Year", y = "U_rate") +
  theme_minimal()

## 労働力人口と就業者数を同一図にプロット
le_df <- combined |>
  dplyr::select(year, data_type, LS, E) |>
  tidyr::pivot_longer(cols = c(LS, E), names_to = "series", values_to = "value")

p5 <- ggplot(le_df, aes(x = year, y = value, color = series, linetype = data_type)) +
  geom_line() + geom_point(size = 1) +
  labs(title = "労働力人口 (LS) と 就業者数 (E)", x = "Year", y = "Number of People (thousands)") +
  theme_minimal()

grid.arrange(p1, p2, p3, p4, p5, ncol = 2)
```
シミュレーション結果から、以下の特筆すべきマクロ経済的特徴が観察される。

+ 実質GDP ((`RY`) と名目賃金 ((`W`): 外生仮定に沿ってGDPが緩やかに拡大する中、タイトな足元の雇用情勢を反映して名目賃金（時間給）はシミュレーション期間を通じて漸増基調をたどる。

+ 労働力率 (PartRate) の持続的上昇: 過去のトレンドおよび実質賃金の上昇に伴うインセンティブ効果（代替効果）により、労働力率は2030年代にかけて上昇を続ける。これにより、総人口（(`POP`）減少による下押し圧力を部分的に吸収し、労働力人口（(`LS`）の急速な縮小は一定程度抑制される。

+ 完全失業率 ((`U_rate`) の上昇（マクロ需給のねじれ現象）: 最も特徴的な挙動は、実質GDPが成長し、生産年齢人口を含む総人口が減少しているにもかかわらず、シミュレーション後半にかけて完全失業率が上昇基調を示す点である。

これらの動きは、モデル推定結果（需要側の強い上方圧力、供給側では労働力率上昇）と概ね整合的であるものの、実質GDPが上昇を続ける中で失業率の推移が上昇傾向にあることや、労働力率や賃金の方程式の説明力（決定係数が相対的に小さい点）については注意が必要であり、複数シナリオでの感度分析を行うことが考えられる。

## 経済学的考察：人口減少下における「マクロ需給のねじれ」

人口減少下での実質GDP成長と失業率上昇という一見矛盾するシミュレーション結果は、本モデルが内包する資本集約的成長（Capital-Intensive Growth）のメカニズムによって理論的に説明される。

### 1.成長パターンと労働需要のGDP弾力性

実質GDPが増加しても、その成長が自動化、AI・DX投資、ロボティクスといった資本深化（Capital Deepening）に依存する「資本集約的成長」である場合、生産の拡大に対して必要な労働投入量の比率（労働投入係数 `E / RY`）は低下を続ける。特定化された就業者数方程式（E）において、GDPの増加がもたらす雇用の拡大効果よりも、実質賃金の上昇に伴う労働から資本への代替効果、あるいは過去のトレンド（構造変化）による下押し圧力が勝る場合、経済が成長していてもマクロの労働需要（就業者数 `E`）は十分に拡大しない。

### 2. 供給側の維持（労働参加率の上昇）と需給ギャップの拡大

一方で、総人口（`POP`）が減少しているものの、シミュレーション上は実質賃金の上昇が労働力率（`PartRate`）を押し上げる。この結果、供給サイドである労働力人口（`LS`）の減少スピードは、人口減少のペースに比べて緩慢にとどまる。すなわち、「資本集約化によって労働需要（`E`）が伸び悩む」一方で、「労働参加の進展によって労働供給（`LS`）が維持される」という不均衡が発生し、結果としてマクロ需給ギャップ（`E / LS` の低下）が広がり、失業率（`U_rate`）の上昇へと結びつく。

### 3. 賃金調整メカニズムの硬直性

フィリップス・カーブ（賃金方程式）の説明力が限定的（$\bar{R}^2 = 0.657$）であり、不均衡を急速に解消するほどの価格（賃金）の伸縮的な下方調整、あるいは過度な労働需要の喚起が十分に働かない。この動学的な調整遅れ（価格の粘着性）が、失業という「数量調整」の形で市場に残存する論拠となる。

したがって、政策的な含意として、人口減少社会＝人手不足（労働市場のタイト化）という一画一的な前提は必ずしも成立しない。成長の質（資本集約度）やシニア・女性の労働参加率の動向によっては、構造的失業やミスマッチによる「ゆとりある失業」が並存する可能性を示唆しており、労働移動支援やスキル・マッチングインフラの整備が不可欠であることを示している。

## 今後の改善点

本モデルの提示したインサイトの頑健性をより高めるため、以下の拡張が求められる。

+ 労働需給ブロックの異質性（Heterogeneity）の導入: 労働供給を性・年齢階級別（シニア・女性の参入障壁の明示化）、労働需要を産業別（製造業の資本集約化とサービス業の労働集約化の対比）に分節化し、産業間労働移動コスト（ミスマッチ）を内生化する。

+ 期待形成の明示化とミクロ的基礎づけ: フォワードルッキングな期待（フォワード・インフレ期待等）を導入し、Lucas批判をクリアする動学的最適化モデル（DSGE等）へのアプローチを試みる。

+ 労働市場の摩擦のモデル化: サーチ・マッチング（Search and Matching）理論（Mortensen-Pissarides型）を取り入れ、UV曲線（ベバリッジ曲線）のシフトとして構造的失業を精緻に捉える。

+ 資本コストと代替弾力性の推計: 生産関数アプローチを明示化し、CES（Cobb-Douglas型に限定しない）生産関数等から資本・労働の代替の弾力性を直接推計する。

+ 複数外生シナリオ（感度分析）の拡充: 内閣府の成長実現ケース／ベースラインケースに準拠した複数成長シナリオを構築し、予測値のバンド（確信区間）を提示する。

## 総括

本分析は、1995年から2025年の構造変化を踏まえたマクロ計量モデルにより、2040年までのわが国労働市場の長期展望を試みた。

本モデルが示した最も重要な視点は、人口減少下にあっても成長の資本集約化が進む局面においては、市場は必ずしもタイト化せず、完全失業率が上昇基調をたどるシナリオが論理的に成立し得るという点である。実務的・政策的な含意として、将来の雇用政策は単純な人手不足対策（労働供給の量的確保）にとどまらず、成長のモダリティ（資本深化の度合い）を凝視しつつ、セクター間の円滑な労働移動と「雇用の質」の確保、および賃金形成の柔軟性を担保する多面的なアプローチが必要となる。

なお、本モデルは構造的な制約を残すものであり、あくまで、マクロ経済ショックや成長パターンの変化が労働市場に与える初期微動（First-round effects）を俯瞰するためのベンチマーク（出発点）を提供するものである。

## 参考文献

- 労働政策研究・研修機構『2023年度版 労働力需給の推計―労働力需給モデルによるシミュレーション―』（資料シリーズ No.284 2024.8） [Link](https://www.jil.go.jp/institute/siryo/2024/284.html)

- 村尾博『Rスクリプト集： Rパッケージ「bimets」の使い方』 [Link](https://kyoto25.web.fc2.com/study_room/R_bimets/R_bimets.html)

- 伴金美『マクロ計量モデル分析 モデル分析の有効性と評価』（有斐閣）

