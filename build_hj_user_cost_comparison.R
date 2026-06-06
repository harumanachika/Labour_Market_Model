# Hall-Jorgenson型ユーザーコストと他統計の比較データを作成するスクリプト

setwd("c:/Users/harum/GitHub/Public/Labour_Market_Model/")
par(mfrow = c(1, 1))

# dir.create("output", showWarnings = FALSE)

#--- ユーザーコスト元データの読み込み ----------------------------------------
data <- readr::read_csv("data/data_UserCost.csv", show_col_types = FALSE)
head(data)

#--- Hall-Jorgenson型の資本ユーザーコスト ------------------------------------
# I_DEFの前年比（%）から期待資本財インフレ率を作成
# uc_hj_real = r + delta - pi_k^e
# uc_hj_nominal = Pk * uc_hj_real。ただし、Pk = I_DEF / 100
# 税制を考慮した拡張（Tau = 法人実効税率、%）:
# uc_hj_real_tax = uc_hj_real / (1 - Tau/100)
# uc_hj_nominal_tax = Pk * uc_hj_real_tax

data <- data |>
  dplyr::mutate(
    pi_k_exp = 100 * (I_DEF / dplyr::lag(I_DEF) - 1),
    # Deltaは減耗率（%）と仮定
    uc_hj_real = r + Delta - pi_k_exp,
    uc_hj_nominal = (I_DEF / 100) * uc_hj_real,
    tau_rate = Tau / 100,
    uc_hj_real_tax = dplyr::if_else(
      (1 - tau_rate) > 0,
      uc_hj_real / (1 - tau_rate),
      NA_real_
    ),
    uc_hj_nominal_tax = (I_DEF / 100) * uc_hj_real_tax
  )

print(
  data |>
    dplyr::select(
      1, r, Delta, Tau, I_DEF, pi_k_exp,
      uc_hj_real, uc_hj_nominal, uc_hj_real_tax, uc_hj_nominal_tax
    ) |>
    head(10)
)

# LabourForce_V2.rで読み込む分析用データとして保存
readr::write_csv(data, "output/data_UserCost_with_HJ.csv")

#--- HJ推計・JIP・SNAのユーザーコスト系列比較 --------------------------------
# data_UserCost.csv内のJIP_UCとSNA_UCは2015年=100の指数として扱う。
# HJ推計値も2015年=100にそろえ、系列ごとに取得可能な最新年まで表示する。
required_cols <- c("JIP_UC", "SNA_UC")
missing_cols <- setdiff(required_cols, names(data))

if (length(missing_cols) > 0) {
  stop(
    paste0(
      "data/data_UserCost.csvに必要な列がありません: ",
      paste(missing_cols, collapse = ", ")
    )
  )
}

base_year <- 2015

base_value <- function(x, year, base_year) {
  value <- x[year == base_year][1]
  if (is.na(value) || length(value) == 0) {
    stop(paste0(base_year, "年の基準値が取得できません。"))
  }
  value
}

compare_df <- data |>
  dplyr::transmute(
    year = as.integer(`...1`),
    hj_uc_index_2015 = 100 * uc_hj_nominal / base_value(uc_hj_nominal, year, base_year),
    jip_uc_index_2015 = JIP_UC,
    sna_uc_index_2015 = SNA_UC
  ) |>
  dplyr::filter(year >= 1995)

# readr::write_csv(compare_df, "output/hj_jip_sna_user_cost_comparison.csv")
# 従来の出力名でも更新しておく。
# readr::write_csv(compare_df, "output/hj_vs_jip_capital_cost.csv")

plot_df <- compare_df |>
  tidyr::pivot_longer(
    cols = c(hj_uc_index_2015, jip_uc_index_2015, sna_uc_index_2015),
    names_to = "series",
    values_to = "index_2015"
  ) |>
  dplyr::filter(!is.na(index_2015))

latest_year <- max(plot_df$year, na.rm = TRUE)
x_breaks <- sort(unique(c(seq(1995, latest_year, by = 5), latest_year)))

p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = year, y = index_2015, color = series)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::labs(
    title = "User Cost Comparison (2015 = 100)",
    x = "Year",
    y = "Index",
    color = "Series"
  ) +
  ggplot2::scale_x_continuous(
    limits = c(min(plot_df$year, na.rm = TRUE), latest_year),
    breaks = x_breaks
  ) +
  ggplot2::scale_color_manual(
    values = c(
      "hj_uc_index_2015" = "#1b9e77",
      "jip_uc_index_2015" = "#d95f02",
      "sna_uc_index_2015" = "#7570b3"
    ),
    labels = c(
      "HJ UC",
      "JIP UC",
      "SNA UC"
    )
  ) +
  ggplot2::theme_minimal(base_size = 12)

# ggplot2::ggsave(
#   filename = "output/hj_jip_sna_user_cost_comparison.png",
#   plot = p,
#   width = 10,
#   height = 6,
#   dpi = 150
# )

# 従来の出力名でも更新しておく。
# ggplot2::ggsave(
#   filename = "output/hj_vs_jip_capital_cost.png",
#   plot = p,
#   width = 10,
#   height = 6,
#   dpi = 150
# )

print(p)

print(compare_df |> head(10))

#--- JIP・SNA合成指標とHJ系列による足許延長 ----------------------------------
# JIP_UCとSNA_UCが同程度の情報量を持つとみなし、両方がある年は等ウェイト平均を使う。
# 片方だけがある年は利用可能な公的統計系列を使い、公的統計が途切れた後は
# HJ UCの前年比伸び率で合成指標を延長する。
composite_df <- compare_df |>
  dplyr::arrange(year) |>
  dplyr::mutate(
    official_composite_index_2015 = rowMeans(
      cbind(jip_uc_index_2015, sna_uc_index_2015),
      na.rm = TRUE
    ),
    official_composite_index_2015 = dplyr::if_else(
      is.nan(official_composite_index_2015),
      NA_real_,
      official_composite_index_2015
    )
  )

latest_official_year <- max(
  composite_df$year[!is.na(composite_df$official_composite_index_2015)],
  na.rm = TRUE
)

if (!is.finite(latest_official_year)) {
  stop("JIP_UCまたはSNA_UCから合成指標の基準系列を作成できません。")
}

composite_extended <- composite_df$official_composite_index_2015

for (i in seq_len(nrow(composite_df))) {
  if (
    composite_df$year[i] > latest_official_year &&
      is.na(composite_extended[i]) &&
      i > 1
  ) {
    hj_growth <- composite_df$hj_uc_index_2015[i] / composite_df$hj_uc_index_2015[i - 1]

    if (is.finite(composite_extended[i - 1]) && is.finite(hj_growth)) {
      composite_extended[i] <- composite_extended[i - 1] * hj_growth
    }
  }
}

composite_df <- composite_df |>
  dplyr::mutate(
    composite_uc_index_2015 = composite_extended,
    composite_source = dplyr::case_when(
      !is.na(jip_uc_index_2015) & !is.na(sna_uc_index_2015) ~ "JIP_SNA_equal_weight",
      !is.na(jip_uc_index_2015) ~ "JIP_only",
      !is.na(sna_uc_index_2015) ~ "SNA_only",
      !is.na(composite_uc_index_2015) ~ "HJ_growth_extension",
      TRUE ~ NA_character_
    )
  )

readr::write_csv(
  composite_df,
  "output/hj_jip_sna_user_cost_composite.csv"
)

composite_plot_df <- composite_df |>
  dplyr::select(
    year,
    hj_uc_index_2015,
    jip_uc_index_2015,
    sna_uc_index_2015,
    composite_uc_index_2015
  ) |>
  tidyr::pivot_longer(
    cols = -year,
    names_to = "series",
    values_to = "index_2015"
  ) |>
  dplyr::filter(!is.na(index_2015))

composite_latest_year <- max(composite_plot_df$year, na.rm = TRUE)
composite_x_breaks <- sort(unique(c(seq(1995, composite_latest_year, by = 5), composite_latest_year)))

p_composite <- ggplot2::ggplot(
  composite_plot_df,
  ggplot2::aes(x = year, y = index_2015, color = series, linewidth = series)
) +
  ggplot2::geom_line() +
  ggplot2::labs(
    title = "Composite User Cost Index (2015 = 100)",
    x = "Year",
    y = "Index",
    color = "Series",
    linewidth = "Series"
  ) +
  ggplot2::scale_x_continuous(
    limits = c(min(composite_plot_df$year, na.rm = TRUE), composite_latest_year),
    breaks = composite_x_breaks
  ) +
  ggplot2::scale_color_manual(
    values = c(
      "hj_uc_index_2015" = "#1b9e77",
      "jip_uc_index_2015" = "#d95f02",
      "sna_uc_index_2015" = "#7570b3",
      "composite_uc_index_2015" = "#111111"
    ),
    labels = c(
      "hj_uc_index_2015" = "HJ UC",
      "jip_uc_index_2015" = "JIP UC",
      "sna_uc_index_2015" = "SNA UC",
      "composite_uc_index_2015" = "Composite UC"
    )
  ) +
  ggplot2::scale_linewidth_manual(
    values = c(
      "hj_uc_index_2015" = 0.8,
      "jip_uc_index_2015" = 0.8,
      "sna_uc_index_2015" = 0.8,
      "composite_uc_index_2015" = 1.3
    ),
    labels = c(
      "hj_uc_index_2015" = "HJ UC",
      "jip_uc_index_2015" = "JIP UC",
      "sna_uc_index_2015" = "SNA UC",
      "composite_uc_index_2015" = "Composite UC"
    )
  ) +
  ggplot2::theme_minimal(base_size = 12)

ggplot2::ggsave(
  filename = "output/hj_jip_sna_user_cost_composite.png",
  plot = p_composite,
  width = 10,
  height = 6,
  dpi = 150
)

print(p_composite)

print(composite_df |> dplyr::select(year, composite_uc_index_2015, composite_source) |> tail(10))
