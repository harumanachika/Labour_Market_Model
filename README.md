---
title: "簡易的なモデルによる労働市場の将来推計"
author: "Manabu Watanabe"
date: "`r Sys.Date()`"
output:
  html_document:
    toc: true
    toc_depth: 2
    number_sections: true
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(
  echo = TRUE,
  warning = FALSE,
  message = FALSE
)
```

## 分析の目的

本レポートでは、1995年から2025年までの実績データを用いて労働市場モデルを推定し、2026年から2040年までの労働力率、失業率、賃金、労働力人口、就業者数、失業者数をシミュレーションする。

## データの準備

分析期間は、実績期間を1995年から2025年、将来推計期間を2026年から2040年とする。

分析では、人口、実質GDP、物価、交易条件を外生的に与え、労働力率、失業率、就業者数、賃金を内生的に決定する簡易的なマクロ労働市場モデルを用いる。労働力率と失業率は0から1の範囲に収まる比率であるため、推定式ではロジット変換を行っている。

数値の単位は、人口、労働力人口、就業者数、失業者数は千人、実質GDPは10億円、賃金、物価は2020年を１とした指数である。また、交易条件は、それぞれ2020年基準の輸出物価（取引通貨建て）、輸入物価（円建て）を用いて算出（後者で前者を除す）。

なお、賃金は時間給を示す。

```{r libraries}
library(tidyverse)
library(data.table)
library(lubridate)
library(xts)
library(bimets)
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

データ加工後の主な変数は以下の通りである。

| 変数 | 内容 | 資料出所 |
|---|---|---|
| `POP` | 人口 | 国立社会保障・人口問題研究所「将来推計人口」（出生中位・死亡中位） |
| `RY` | 実質GDP | 内閣府「四半期別GDP統計」　内閣府「中長期の経済財政に関する試算」（過去投影ケース） |
| `P` | 物価 | 総務省統計局「消費者物価指数」（総合）　内閣府「中長期の経済財政に関する試算」（過去投影ケース）|
| `LS` | 労働力人口 | 総務省統計局「労働力調査」 |
| `PartRate` | 労働力率 | 総務省統計局「労働力調査」 |
| `U_rate` | 失業率 | 総務省統計局「労働力調査」 |
| `E` | 就業者数 | 総務省統計局「労働力調査」 |
| `W` | 賃金（時間給） | 厚生労働省「毎月勤労統計調査」（現金給与総額・総実労働時間） |
| `Trend` | トレンド変数 |

1995年時点では、労働力率は約0.632、失業率は約0.031である。2000年時点では、労働力率は約0.624、失業率は約0.047となっている。また、実績値の最終年である2025年時点では、労働力率は約0.641、失業率は約0.022となっている。

```{r model-data}
model_data <- lapply(
  as.list(
    xts(data_obs |> select(-date), order.by = data_obs$date)
  ),
  as.bimets
)
```

今回の修正では、4本の行動方程式について、原則として説明変数の1期前を操作変数に用いるIV推定を行う。ただし、操作変数が弱い場合にはIV推定を採用せず、OLS推定とする。弱操作変数の判定には第一段階回帰のF統計量を用い、本レポートでは `weak_iv_threshold = 10` を下回る場合を弱操作変数として扱う。

具体的には、各方程式について第一段階のF統計量を計算し、`iv_diagnostics` に推定方法の判定結果を保存する。その後、方程式ごとに `ESTIMATE()` を実行し、F統計量がしきい値以上であれば `estTech = "IV"`、しきい値未満であれば `estTech = "OLS"` を指定する。操作変数に2期ラグが含まれるため、推定期間は1997年から2025年までとする。

また、外生性の検定（Durbin-Wu-Hausman検定）により、IV推定とOLS推定の結果に有意な差があるかを確認し、説明変数と誤差項との間に相関がない場合には、OLS推定を採用する。

```{r iv-setup}
weak_iv_threshold <- 10
estimation_range <- c(1997, 1, 2025, 1)

estimation_check_data <- data_obs |>
  mutate(
    W_P = W / P,
    W_P_lag1 = lag(W / P, 1),
    U_rate_lag1 = lag(U_rate, 1),
    U_rate_lag2 = lag(U_rate, 2),
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
    dlog_P = log(P) - lag(log(P), 1),
    dlog_P_lag1 = lag(dlog_P, 1),
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

iv_specs <- list(
  lgtPartRate = list(
    IV = c("1", "TSLAG(W / P, 1)", "TSLAG(U_rate, 2)", "TSLAG(lgtPartRate, 2)"),
    x_vars = c("W_P", "U_rate_lag1", "lgtPartRate_lag1"),
    z_vars = c("const", "W_P_lag1", "U_rate_lag2", "lgtPartRate_lag2")
  ),
  lgtU_rate = list(
    IV = c("1", "TSLAG(E / LS, 1)", "TSLAG(lgtU_rate, 2)"),
    x_vars = c("E_LS", "lgtU_rate_lag1"),
    z_vars = c("const", "E_LS_lag1", "lgtU_rate_lag2")
  ),
  E = list(
    IV = c("1", "TSLAG(LOG(RY), 1)", "TSLAG(LOG(W / P), 1)", "TSLAG(LOG(E), 2)"),
    x_vars = c("log_RY", "log_W_P", "log_E_lag1"),
    z_vars = c("const", "log_RY_lag1", "log_W_P_lag1", "log_E_lag2")
  ),
  W = list(
    IV = c("1", "TSLAG(U_rate, 1)", "TSLAG(TSDELTALOG(P, 1), 1)"),
    x_vars = c("U_rate", "dlog_P"),
    z_vars = c("const", "U_rate_lag1", "dlog_P_lag1")
  )
)

iv_diagnostics <- lapply(names(iv_specs), function(eq_name) {
  spec <- iv_specs[[eq_name]]
  fs <- first_stage_min_f(estimation_check_data, spec$x_vars, spec$z_vars)
  data.frame(
    equation = eq_name,
    min_first_stage_F = fs$min_f,
    estimation = ifelse(
      is.finite(fs$min_f) && fs$min_f >= weak_iv_threshold,
      "IV",
      "OLS"
    ),
    stringsAsFactors = FALSE
  )
}) |>
  bind_rows()

iv_diagnostics
```

## モデルの定義

本分析では、以下の4本の行動方程式と4本の恒等式からなるモデルを用いる。

行動方程式では、労働力率、就業者数、失業率、賃金を推定対象とする。労働力率と失業率はロジット変換した値を被説明変数として用いる。

### 労働力率方程式
労働力率のロジット変換値 `lgtPartRate` は、分布ラグモデルを基本として、実質賃金（`W / D_GDP`）の水準、失業率の1期前の値を説明変数とする。

### 就業者数方程式
就業者数 `E` は、対数変換の分布ラグモデルを基本として、実質GDP（`RY`）の水準、実質賃金（`W / P`）の水準（１期ラグ）を説明変数とする。

### 失業率方程式
失業率のロジット変換値 `lgtU_rate` は、分布ラグモデルを基本として、就業者数/労働力人口(`E / LS`)を説明変数とする。

### 賃金増減率方程式
賃金 `W` は増減率（対数階差）とし、フィリップスカーブの想定から、失業率の水準、物価増減率、交易条件増減率を説明変数とする。

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

model <- LOAD_MODEL(modelText = model_text)
model <- LOAD_MODEL_DATA(model, model_data)
summary(model)
```

## 推定結果

1997年から2025年までの実績データを用いて、モデルの係数を推定する。推定方法は、上で計算した第一段階F統計量に基づき、方程式ごとにIVまたはOLSを選択する。

```{r estimation}
for (eq_name in names(iv_specs)) {
  spec <- iv_specs[[eq_name]]
  est_method <- iv_diagnostics$estimation[iv_diagnostics$equation == eq_name]

  if (identical(est_method, "IV")) {
    model <- ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "IV",
      IV = spec$IV,
      forceIV = TRUE
    )
  } else {
    model <- ESTIMATE(
      model,
      eqList = eq_name,
      TSRANGE = estimation_range,
      forceTSRANGE = TRUE,
      estTech = "OLS"
    )
  }
}
```

推定方法の判定結果は以下のとおりである。`min_first_stage_F` は、各方程式に含まれる説明変数について計算した第一段階F統計量の最小値である。

```{r iv-diagnostics-table}
iv_diagnostics
```

推定結果の概要は以下の通りである。

| 方程式 | 主な結果 | 決定係数 |
|---|---:|---:|
| 労働力率 `lgtPartRate` | 失業率のラグが有意にマイナス、労働力率のラグが有意にプラス | 0.978 |
| 失業率 `lgtU_rate` | 就業者数/労働力人口が有意にマイナス、失業率のラグが有意にプラス | 0.992 |
| 就業者数 `E` | 実質GDP、実質賃金、就業者数のラグがいずれも有意にプラス | 0.974 |
| 賃金 `W` | 物価上昇率が有意にプラス、失業率はマイナス方向だが有意水準は限定的 | 0.567 |

労働力率、失業率、就業者数の方程式は高い説明力を示している。一方、賃金方程式の決定係数は相対的に低く、賃金変化の説明には追加的な要因を検討する余地がある。


## 将来シミュレーションと図示

以下では、実績（1995–2025年）とモデルによる将来シミュレーション（2026–2040年）を併せて示し、実質GDP（`RY`）、賃金（`W`）、労働力率（`PartRate`）、失業率（`U_rate`）の動きを図示する。

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
library(ggplot2)
library(gridExtra)

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

図を確認すると、以下の特徴が読み取れる。

- 実質GDP (`RY`): 実績期間では増加トレンドを示し、将来シミュレーションでは緩やかな上昇が継続する想定になっている。
- 賃金 (`W`): 実績では変動があるが、シミュレーションでは漸増する傾向が見られる。これは需要側の強まりや低失業率の影響を反映していると考えられる。
- 労働力率 (`PartRate`): 実績から将来にかけて上昇する見通しであり、特に2030年代にかけて上昇幅が目立つ。
- 失業率 (`U_rate`): 実績での変動を経て、将来シミュレーションでは低下が続き、2040年には非常に低い水準となる見込みである。

- 労働力人口 (`LS`): 実績・将来の推移を比較すると、人口減少に伴い絶対水準の伸びは限定的であるが、労働力率の上昇が補完的に働けば労働力人口は一定程度維持されるシナリオが見られる。
- 就業者数 (`E`): 就業者数は賃金・需要の動向と密接に関連する。シミュレーションでは賃金上昇や参加率改善が同時に進む場合に就業者数が増加する一方、需要側の労働投入の弱さが残る場合は就業者数の伸びが抑えられる可能性がある。

これらの動きは、モデル推定結果（需要側の強い上方圧力、供給側では労働力率上昇）と整合的である。ただし、失業率が極端に低下する点や賃金上昇の説明力（賃金方程式の決定係数が相対的に小さい点）については注意が必要であり、複数シナリオでの感度分析を行うことを推奨する。

## 考察

本モデルのシミュレーションでは、実質GDP（`RY`）が増加し、人口（`POP`）が減少する状況においても、シナリオ次第では失業率（`U_rate`）が増加する結果となる可能性が示された。これは以下の点に起因すると考えられる。

- 需要側の性質: 実質GDP が増加しても、成長が資本集約的（労働の投入係数 `E_RY` が低下）であれば、同じ成長率でも労働需要は十分に増えない。モデルの就業者数方程式は `E` を `RY` と実質賃金の関数としているため、`E_RY` の低下が進めば失業率が上昇しうる。
- 供給側・参加率の変化: 人口が減少しても労働参加率 `PartRate` が低下すれば労働力人口 `LS` が想定以上に縮小し、短期的なミスマッチで失業率が上がる場合がある（年齢構成や参加意欲の構造変化をモデル化していないため、その影響が反映されにくい）。
- ミスマッチ・構造変化: モデルはセクター横断の集約モデルであり、産業間の需要移動やスキルミスマッチを捉えられない。GDP 成長が特定のセクターに偏れば、雇用の増加が実現しにくく、失業が残る可能性がある。
- 賃金調整の限定性: 本モデルの賃金方程式は説明力が相対的に低く、賃金が十分に調整されない、あるいは調整が遅れると、雇用調整が生じやすくなる。

これらはモデルの構造的な特徴（集約モデル、限られた説明変数、恒等式による供給側の制約）に起因する挙動である。政策含意としては、単に実質GDPの成長を追求するだけでなく、成長の質（労働集約性）、労働参加率の向上、スキル・マッチング改善、賃金形成メカニズムの把握が重要であることが示唆される。

## 今後の改善点

今後の改善点として、以下が挙げられる。

1. モデルを動学的最適化問題から定式化し、期待形成のメカニズムを明示的に取り入れる。
2. 資本とその使用コスト、代替の弾力性を明示的に取り扱う。
3. 人口、GDP、物価について複数シナリオを設定し、ベースライン、楽観、悲観ケースを比較する。
4. 推定期間を変えた場合の感応度分析を行い、予測結果の頑健性を確認する。

## まとめ

本分析では、1995年から2025年までの実績データを用いて労働市場モデルを推定し、2026年から2040年までの将来推計を行った。

補足のまとめ:

- 本モデルは実質GDP の増加を必ずしも失業率の低下に直結させない。特に、成長が資本集約的である、あるいは参加率が低下する場合、失業率が上昇するシナリオがあり得る。
- モデルの制約（集約化、限定的な賃金方程式、セクター間ミスマッチ不在）により、実際の政策評価にはシナリオ分析やセクター別モデル、労働参加の決定要因を追加した拡張が望ましい。
- 実務的には、人口動態・参加率・スキル供給の変化を反映した複数シナリオを作成し、雇用創出の質と分布を分析することを推奨する。

以上より、本モデルは労働市場の将来動向を簡易的に確認するための出発点として有用であるが、政策分析や正式な将来推計に用いるには、モデル構造の整合性とシナリオ設定の精緻化が必要である。
