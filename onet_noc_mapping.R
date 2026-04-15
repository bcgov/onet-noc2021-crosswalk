VERSION <- "3.0.0"

# Builds weighted O*NET 2019 -> NOC 2021 mapping

# User choices-------------------------

gt_one <- 2 # power on noc weights (reduces influence of small weights)

#libraries----------------------

suppressPackageStartupMessages({
  library(tidyverse)
  library(readxl)
  library(janitor)
  library(conflicted)
  })

conflicts_prefer(
  dplyr::filter,
  dplyr::select,
  dplyr::mutate,
  dplyr::summarise,
  dplyr::arrange)

#constants--------------------------------

out_dir <- paste0("output/",VERSION)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

#functions------------------------------------

read_data <- function(file_name, category){
  read_excel(file_name)%>%
    clean_names()%>%
    select(o_net_soc_code, element_name, scale_name, data_value)%>%
    pivot_wider(names_from = scale_name, values_from = data_value)%>%
    mutate(Importance=10*(Importance-1)/4, # put level and importance on same 0-10 support
           Level=10*Level/7, # put level and importance on same 0-10 support
           score=sqrt(Importance*Level), # geometric mean of importance and level
           category=category
           )%>%
    unite(element_name, category, element_name, sep=": ")%>%
    select(-Importance, -Level)
}

calc_mapping_dispersion <- function(tbl_noc, weight, pc_cols = paste0("PC", 1:10)) {
  centroid <- tbl_noc |>
    summarise(across(all_of(pc_cols), ~ sum(.x * {{ weight }})))
  tbl_noc |>
    mutate(
      dist_to_centroid = sqrt(
        rowSums(
          (across(all_of(pc_cols)) - as.numeric(centroid[1, pc_cols]))^2
        )
      )
    ) |>
    summarise(
      weighted_avg_dist = sum({{ weight }} * dist_to_centroid)
    ) |>
    pull(weighted_avg_dist)
}


# O*NET skill, knowledge, ability, work activities-------

onet_dir <- "data-raw/onet_files"

files <- list.files(onet_dir, full.names = TRUE)

# Extract "clean" names (remove prefix up to first "_")

clean_names <- sub("^[^_]+_", "", basename(files))

# Build lookup
file_lookup <- tibble(
  path = files,
  clean = clean_names
)

# Expected files
expected <- c(
  "Skills.xlsx",
  "Abilities.xlsx",
  "Knowledge.xlsx",
  "Work Activities.xlsx"
)

# Match
matched_files <- file_lookup |>
  filter(clean %in% expected)

# Safety checks
# 1. No expected file should appear more than once after cleaning names
dup_expected <- matched_files |>
  count(clean, name = "n") |>
  filter(n > 1)

if (nrow(dup_expected) > 0) {
  stop(
    paste0(
      "Duplicate O*NET input files found after cleaning names: ",
      paste(dup_expected$clean, collapse = ", ")
    )
  )
}

# 2. All expected files must be present
missing_expected <- setdiff(expected, matched_files$clean)

if (length(missing_expected) > 0) {
  stop(
    paste0(
      "Missing required O*NET input files: ",
      paste(missing_expected, collapse = ", ")
    )
  )
}

# 3. Keep only the validated files, in the intended order
onet_files <- matched_files |>
  mutate(clean = factor(clean, levels = expected)) |>
  arrange(clean)

# read in onet data---------------------------------------------

onet_data <- onet_files|>
  mutate(category=sub("\\.xlsx$", "", clean))%>%
  mutate(data=map2(path, category, read_data))%>%
  select(-path)%>%
  unnest(data)%>%
  rename(onet_soc_code=o_net_soc_code)|>
  pivot_wider(id_cols = onet_soc_code, names_from = element_name, values_from = score)|>
  column_to_rownames("onet_soc_code")|>
  as.matrix()

data_available <- tibble(onet_soc_code=rownames(onet_data))

onet_prcomp <- onet_data|>
  prcomp(center = TRUE, scale. = TRUE)

# D_full_vec <- scale(onet_data, center = onet_prcomp$center, scale = onet_prcomp$scale)|>
#   dist()|>
#   as.vector()
# max_k <- ncol(onet_prcomp$x)
# 
# k_vs_spearman <- map_dfr(1:max_k, function(k) {
#   X_k <- onet_prcomp$x[, 1:k, drop = FALSE] #keep as a matrix even if k=1
#   D_k <- dist(X_k)
#   D_k_vec <- as.vector(D_k)
#   
#   tibble(
#     k = k,
#     spearman = cor(D_full_vec, D_k_vec, method = "spearman")
#   )
# }
# )
# 
# ggplot(k_vs_spearman, aes(x = k, y = spearman)) +
#   geom_hline(yintercept = .99, lty=2)+
#   geom_line() +
#   geom_point() +
#   scale_x_continuous(trans="log10")+
#   labs(title="We retain the minimum number of PCs (10) required to achieve ≥0.99 rank preservation of pairwise distances.",
#        y = "Spearman correlation (distance ranks)",
#        x = "Number of PCs")

onet_prcomp10 <- onet_prcomp$x[,1:10]|>
  as.data.frame()|>
  rownames_to_column("onet_soc_code")


# Step 1: O*NET 2019 -> SOC 2018--------------------------------------


onet_2019_to_soc_2018_path <- list.files("data-raw/crosswalks",
                                         pattern="2019_to_SOC_Crosswalk.xlsx",
                                         full.names = TRUE)
stopifnot(length(onet_2019_to_soc_2018_path) == 1)


onet_2019_to_soc_2018 <- read_excel(onet_2019_to_soc_2018_path,
                                    skip = 3)|>
  transmute(onet_soc_code=`O*NET-SOC 2019 Code`,
            onet_title=`O*NET-SOC 2019 Title`,
            soc_2018=`2018 SOC Code`)|>
  semi_join(data_available, by = join_by(onet_soc_code))|>
  unite(onet_plus_title, onet_soc_code, onet_title, sep=": ", remove = FALSE)|>
  distinct()|> #make sure no duplicates
  group_by(onet_soc_code, onet_plus_title)|>
  mutate(w_1 = 1 / n_distinct(soc_2018)) |> #path weights if 1:many
  ungroup()|>
  select(-onet_title)

# Step 2: SOC 2018 -> NOC 2016----------------------------------------

soc_2018_to_noc_2016_path <- list.files("data-raw/crosswalks",
                                         pattern="noc2016v1_3-soc2018us-eng.csv",
                                         full.names = TRUE)
stopifnot(length(soc_2018_to_noc_2016_path) == 1)

soc_2018_to_noc_2016 <- read_csv(soc_2018_to_noc_2016_path)|>
  transmute(
    soc_2018 = `SOC 2018 (US) Code`,
    noc_2016 = str_pad(`NOC 2016  Version 1.3 Code`, width = 4, pad = "0"))|>
  distinct() |> #make sure no duplicates
  group_by(soc_2018) |>
  mutate(w_2 = 1 / n_distinct(noc_2016)) |> #path weights for 1:many
  ungroup()

# Step 3: NOC 2016 -> NOC 2021-----------------------------------------

noc_2016_to_noc_2021_path <- list.files("data-raw/crosswalks",
                                        pattern="noc2016v1_3-noc2021v1_0-eng.csv",
                                        full.names = TRUE)
stopifnot(length(noc_2016_to_noc_2021_path) == 1)

noc_2016_to_noc_2021 <- read_csv(noc_2016_to_noc_2021_path)|>
  transmute(
    noc_2016 = str_pad(`NOC 2016 V1.3 Code`, width = 4, pad = "0"),
    noc_2021 = str_pad(`NOC 2021 V1.0 Code`, width = 5, pad = "0"),
    noc2021_title = `NOC 2021 V1.0 Title`) |>
  mutate(
    noc2021_title = if_else(
      noc_2021 %in% c("00011", "00012", "00013", "00014", "00015"),
      "Senior managers - public and private sector",
      noc2021_title
    ),
    noc_2021 = if_else(
      noc_2021 %in% c("00011", "00012", "00013", "00014", "00015"),
      "00018",
      noc_2021
    )
  ) |>
  distinct() |>  #make sure no duplicates
  group_by(noc_2016) |>
  mutate(w_3 = 1 / n_distinct(noc_2021)) |> #path weights for 1:many
  ungroup() |>
  unite(noc_plus_title, noc_2021, noc2021_title, sep = ": ", remove = FALSE)|>
  select(-noc2021_title)


# Input integrity checks------------------------------------

#' Many-to-many joins are inherent to the crosswalk structure,
#' but we do NOT allow duplicate key-pairs within any crosswalk.
#' if duplicate pairs exist, joins will multiply rows for the wrong reason
#' (data duplication rather than genuine branching), which will bias the
#' constructed path weights.
#' 
#' These checks ensure that all row expansion in subsequent joins reflects
#' real mapping structure, not input data errors.

dup_onet_soc <- onet_2019_to_soc_2018 |>
  count(onet_soc_code, soc_2018) |>
  filter(n > 1)

dup_soc_noc2016 <- soc_2018_to_noc_2016 |>
  count(soc_2018, noc_2016) |>
  filter(n > 1)

dup_noc2016_noc2021 <- noc_2016_to_noc_2021 |>
  count(noc_2016, noc_2021) |>
  filter(n > 1)

if (nrow(dup_onet_soc) > 0) stop("Duplicate onet_soc_code-soc_2018 pairs found.")
if (nrow(dup_soc_noc2016) > 0) stop("Duplicate soc_2018-noc_2016 pairs found.")
if (nrow(dup_noc2016_noc2021) > 0) stop("Duplicate noc_2016-noc_2021 pairs found.")


# All paths---------------------------------------

#' NOTE: a many-to-many relationship is expected:
#'  We keep all admissible paths and assign path weights as the product
#'  of equal-split weights at each stage.

onet_to_noc2021_paths <- onet_2019_to_soc_2018 |>
  left_join(soc_2018_to_noc_2016, by = "soc_2018", relationship = "many-to-many") |>
  left_join(noc_2016_to_noc_2021, by = "noc_2016", relationship = "many-to-many") |>
  group_by(noc_plus_title)|>
  mutate(path_weight = w_1 * w_2 * w_3,
         equal_weight=1/n()
         ) |>
  select(
    onet_soc_code,
    onet_plus_title,
    soc_2018,
    noc_2016,
    noc_2021,
    noc_plus_title,
    w_1,
    w_2,
    w_3,
    path_weight,
    equal_weight
  )|>
  arrange(noc_plus_title, desc(path_weight))

# mapping----------------------------------------

mapping <- onet_to_noc2021_paths |>
  group_by(onet_soc_code, onet_plus_title, noc_2021, noc_plus_title) |>
  summarise(path_weight = sum(path_weight),
            equal_weight= sum(equal_weight),
            )|>
  group_by(noc_plus_title, noc_2021) |>
  mutate(base_weight = path_weight / sum(path_weight),
         down_weight = base_weight^gt_one,
         down_weight = down_weight/ sum(down_weight)
         )|>
  ungroup()|>
  arrange(noc_2021, desc(down_weight), onet_soc_code)|>
  select(onet_soc_code, onet_plus_title, noc_2021, noc_plus_title, equal_weight, path_weight, base_weight, down_weight)

# average distance (in 10D pca) between ONET occupations and NOC (weighted) centroid-------------

mapping_with_diagnostics <- mapping|>
  select(onet_soc_code, onet_plus_title, noc_2021, noc_plus_title, equal_weight, base_weight, down_weight)|>
  left_join(onet_prcomp10, by = join_by(onet_soc_code))|>
  group_by(noc_plus_title, noc_2021)|>
  mutate(down_herf = sum(down_weight^2)
         )|>
  nest()|>
  mutate(down_dispersion = map_dbl(data, ~ calc_mapping_dispersion(.x, down_weight)))|>
  unnest(data)|>
  mutate(weight_shift=.5* sum(abs(base_weight - down_weight))) # total variation distance between base and down-weighted mappings

 
diagnostics <- mapping_with_diagnostics |>
  group_by(noc_2021, noc_plus_title) |>
  summarise(
    `Herfindahl Index` = first(down_herf),
    `Distance from centroid` = first(down_dispersion),
    `Share of weights reallocated` = first(weight_shift),
    .groups = "drop"
  )|>
  mutate(
   `Scaled Similarity` = 1.05-percent_rank(`Distance from centroid`),
    sort_score = `Scaled Similarity`*`Herfindahl Index`
  )|>
  arrange(sort_score)


# Write outputs-----------------------------

write_csv(onet_to_noc2021_paths, file.path(out_dir, "onet_to_noc2021_paths.csv"))
write_csv(mapping, file.path(out_dir, "onet_to_noc2021_mapping.csv"))
write_csv(diagnostics, file.path(out_dir, "diagnostics.csv"))

metadata_lines <- c(
  sprintf("Run timestamp: %s", Sys.time()),
  sprintf("n_mapping_rows: %s", nrow(mapping)),
  sprintf("n_noc2021: %s", n_distinct(mapping$noc_plus_title)),
  sprintf("version: %s", VERSION)
)
writeLines(metadata_lines, file.path(out_dir, "run_metadata.txt"))

message("Build complete. Output files written to: ", out_dir)
