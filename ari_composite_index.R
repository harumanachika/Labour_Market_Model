# PCAによるARP統合指標および経年変化の試算
#

library(tidyverse)
library(broom)


# Data
df <- tibble(
  read_csv("data/ARI.csv")
)

df_long <- df %>%
  pivot_longer(-c(OCP, OCP_NAME), names_to = "year", values_to = "ARI") %>%
  mutate(year = as.numeric(year))

df_wide <- df_long %>%
  pivot_wider(names_from = c(OCP, OCP_NAME), values_from = ARI) %>%
  arrange(year)


# PCA
pca <- df_wide %>%
  dplyr::select(-c(year)) %>%
  prcomp(scale. = TRUE)

scores <- as_tibble(pca$x) %>%
  dplyr::select(PC1) %>%
  dplyr::bind_cols(year = df_wide$year)


# 主成分の負荷量（ウェイト）
loadings <- pca$rotation[,1]
loadings


# 符号調整・正規化
mean_ari <- df_wide %>%
  dplyr::select(-c(year)) %>%
  rowMeans()

if(cor(scores$PC1, mean_ari) < 0){
  scores <- scores %>%
    mutate(PC1 = -PC1)
}
scores <- scores %>%
  mutate(
    ARI_index = (PC1 - min(PC1)) / (max(PC1) - min(PC1))
)


# Spline Interpolation of Logit Transformation
eps <- 1e-6

scores_aug <- scores %>%
  dplyr::select(year, ARI_index) %>%
  dplyr::add_row(year = 2018, ARI_index = 0.000001) %>%  # ← 追加
  dplyr::mutate(
    ARI_adj = pmin(pmax(ARI_index, eps), 1 - eps),
    logit_ari = log(ARI_adj / (1 - ARI_adj))
  ) %>%
  arrange(year)

# 確認（4点以上になっているはず）
print(scores_aug)

spline_fit <- smooth.spline(
  x = scores_aug$year,
  y = scores_aug$logit_ari,
  spar = 0.6
)

result <- tibble(year = 1995:2040) %>%
  mutate(
    logit_pred = predict(spline_fit, year)$y,
    ARI = exp(logit_pred) / (1 + exp(logit_pred))
  ) %>%
  mutate(
    ARI = cummax(ARI)  # 単調性
  )

write.csv(result, "output/ARI_series_1995_2040.csv", row.names = FALSE)


# Plot
ggplot(result, aes(year, ARI)) +
  geom_line(color = "blue", linewidth = 1) +
  geom_point(data = scores, aes(year, ARI_index), color = "red") +
  theme_minimal()
