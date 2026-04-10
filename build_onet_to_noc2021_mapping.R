# Build weighted O*NET 2019 -> NOC 2021 mapping

# ------------------------------------------------------------------
# User choices
# ------------------------------------------------------------------

cumulative_skill_weight_cutoff <- 0.8
herf_cut <- 1 / 6

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(readr)
  library(readxl)
  library(stringr)
})

out_dir <- "output"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# ------------------------------------------------------------------
# O*NET skill, knowledge, ability, work activities available
# ------------------------------------------------------------------

onet_dir <- "data-raw/onet_files/"

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
onet_paths <- file_lookup |>
  filter(clean %in% expected) |>
  arrange(match(clean, expected)) |>
  pull(path)

# Safety checks
stopifnot(!any(duplicated(file_lookup$clean[file_lookup$clean %in% expected])))
stopifnot(length(onet_paths) == length(expected))

data_available <- tibble(path = onet_paths) |>
  mutate(data = map(path, read_excel)) |>
  select(-path) |>
  unnest(data) |>
  transmute(onet_soc_code=`O*NET-SOC Code`)|>
  distinct()

# ------------------------------------------------------------------
# Step 1: O*NET 2019 -> SOC 2018
# ------------------------------------------------------------------

onet_2019_to_soc_2018_path <- list.files("data-raw/crosswalks",
                                         pattern="2019_to_SOC_Crosswalk.xlsx",
                                         full.names = TRUE)
stopifnot(length(onet_2019_to_soc_2018_path) == 1)


onet_2019_to_soc_2018 <- read_excel(onet_2019_to_soc_2018_path,
                                    skip = 3)|>
  transmute(onet_soc_code=`O*NET-SOC 2019 Code`,
            soc_2018=`2018 SOC Code`)|>
  semi_join(data_available, by = join_by(onet_soc_code))|>
  distinct()|> #make sure no duplicates
  group_by(onet_soc_code) |>
  mutate(w_1 = 1 / n_distinct(soc_2018)) |> #path weights if 1:many
  ungroup()

# ------------------------------------------------------------------
# Step 2: SOC 2018 -> NOC 2016
# ------------------------------------------------------------------

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

# ------------------------------------------------------------------
# Step 3: NOC 2016 -> NOC 2021
# ------------------------------------------------------------------

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
  unite(noc_plus_title, noc_2021, noc2021_title, sep = ": ", remove = FALSE)

# ------------------------------------------------------------------
# Input integrity checks
# ------------------------------------------------------------------
# Many-to-many joins are inherent to the crosswalk structure,
# but we do NOT allow duplicate key-pairs within any crosswalk.
# if duplicate pairs exist, joins will multiply rows for the wrong reason
# (data duplication rather than genuine branching), which will bias the
# constructed path weights.
#
# These checks ensure that all row expansion in subsequent joins reflects
# real mapping structure, not input data errors.

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

# ------------------------------------------------------------------
# All paths
# ------------------------------------------------------------------

# NOTE: a many-to-many relationship is expected:
# We keep all admissible paths and assign path weights as the product
# of equal-split weights at each stage.

onet_to_noc2021_paths <- onet_2019_to_soc_2018 |>
  left_join(soc_2018_to_noc_2016, by = "soc_2018", relationship = "many-to-many") |>
  left_join(noc_2016_to_noc_2021, by = "noc_2016", relationship = "many-to-many") |>
  mutate(path_weight = w_1 * w_2 * w_3) |>
  select(
    onet_soc_code,
    soc_2018,
    noc_2016,
    noc_2021,
    noc2021_title,
    noc_plus_title,
    w_1,
    w_2,
    w_3,
    path_weight
  )|>
  arrange(noc_plus_title, desc(path_weight))

# ------------------------------------------------------------------
# Untrimmed mapping
# ------------------------------------------------------------------

mapping_untrimmed <- onet_to_noc2021_paths |>
  group_by(onet_soc_code, noc_plus_title, noc_2021, noc2021_title) |>
  summarise(onet_weight = sum(path_weight), .groups = "drop") |>
  group_by(noc_plus_title, noc_2021, noc2021_title) |>
  mutate(noc_weight = onet_weight / sum(onet_weight)) |>
  ungroup()|>
  arrange(noc_2021, desc(noc_weight), onet_soc_code)

# ------------------------------------------------------------------
# Trim low-weight noise, and then normalize within NOC 2021:
# noc_weight reflects the relative contribution of O*NET occupations
# to each NOC (not a forward probability from O*NET to NOC).
# ------------------------------------------------------------------

mapping_trimmed <- mapping_untrimmed |>
  group_by(noc_plus_title, noc_2021, noc2021_title) |>
  arrange(desc(noc_weight), .by_group = TRUE) |>
  mutate(cum_weight = cumsum(noc_weight),
         cutoff_index = match(TRUE, cum_weight >= cumulative_skill_weight_cutoff),
         cutoff_index = if_else(is.na(cutoff_index), dplyr::n(), cutoff_index),
         cutoff_weight = noc_weight[cutoff_index]
         )|>
  select(-cutoff_index)|>
  filter(noc_weight >= cutoff_weight | row_number() == 1) |> #Ensures at least one O*NET occupation is retained
  mutate(noc_weight = noc_weight / sum(noc_weight)) |>
  ungroup()|>
  arrange(noc_2021, desc(noc_weight), onet_soc_code)

# ------------------------------------------------------------------
# Mapping strength
# ------------------------------------------------------------------

mapping_strength <- mapping_trimmed |>
  group_by(noc_plus_title, noc_2021, noc2021_title) |>
  summarise(herf_score = sum(noc_weight^2), .groups = "drop") |>
  mutate(herf_cat = if_else(herf_score < herf_cut, "weak", "strong"))|>
  arrange(noc_2021)

# ------------------------------------------------------------------
# Write outputs
# ------------------------------------------------------------------

write_csv(onet_to_noc2021_paths, file.path(out_dir, "onet_to_noc2021_paths.csv"))
write_csv(mapping_untrimmed, file.path(out_dir, "onet_to_noc2021_mapping_untrimmed.csv"))
write_csv(mapping_trimmed, file.path(out_dir, "onet_to_noc2021_mapping_trimmed.csv"))
write_csv(mapping_strength, file.path(out_dir, "onet_to_noc2021_mapping_strength.csv"))

metadata_lines <- c(
  sprintf("Run timestamp: %s", Sys.time()),
  sprintf("cumulative_skill_weight_cutoff: %s", cumulative_skill_weight_cutoff),
  sprintf("herf_cut: %s", herf_cut),
  sprintf("n_paths: %s", nrow(onet_to_noc2021_paths)),
  sprintf("n_untrimmed_rows: %s", nrow(mapping_untrimmed)),
  sprintf("n_trimmed_rows: %s", nrow(mapping_trimmed)),
  sprintf("n_noc2021: %s", n_distinct(mapping_trimmed$noc_plus_title))
)
writeLines(metadata_lines, file.path(out_dir, "run_metadata.txt"))

message("Build complete. Output files written to: ", out_dir)
