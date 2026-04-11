# O*NET 2019 → NOC 2021 Crosswalk V2.0.0

A reproducible mapping from **O*NET-SOC 2019** occupations to **NOC 2021** that:

- assigns **weights** to many-to-many mappings  
- **downweights low-weight occupations** (noise reduction)  
- provides a **measure of mapping quality** (Herfindahl index)

This is a **data product**, not an R package.

---

## Why not “just use OaSIS”?

OaSIS provides a **single curated skill profile per NOC**.

This project does something different:

> It represents each NOC as a distribution over O*NET occupations, and tells you how reliable that mapping is.

### Comparison

| Feature | OaSIS | This project |
|--------|------|-------------|
| Output | One skill profile per NOC | Distribution over O*NET occupations |
| Mapping | Internal / opaque | Explicit and reproducible |
| Uncertainty | Not reported | Quantified (Herfindahl index) |
| Flexibility | Fixed | Tunable  |

OaSIS effectively **resolves mapping internally**.

This project **exposes the mapping and measures its ambiguity**.

---

## What this repository provides

Running the build script produces:

- **`onet_to_noc2021_paths.csv`**  
  All admissible mapping paths and weights

- **`onet_to_noc2021_mapping.csv`**  
  Full mapping (can be noisy)

- **`onet_to_noc2021_mapping_strength.csv`** 
  Mapping quality (Herfindahl index)
  
- **`onet_data.csv`**
  Rescaled ONET skills, abilities, knowledge, and work activities

---

## Key idea

The mapping answers:

> For a given NOC 2021 occupation, which O*NET occupations contribute skill content, and with what weights?

---

## Method (short version)

Mapping chain:

1. O*NET 2019 → SOC 2018  
2. SOC 2018 → NOC 2016  
3. NOC 2016 → NOC 2021  

### Weighting

At each step, one-to-many splits receive equal weight:

```
w = 1 / n_targets
```

Path weights are multiplied:

```
path_weight = w1 × w2 × w3
```

Then aggregated to O*NET–NOC pairs.

---

## Down weighting

Base weights are squared (the default) and then renormalized to downweight small
contributors.

---

## Mapping quality

For each NOC:

```
H = Σ noc_weight²
```

- **High H** → concentrated (clean mapping)  
- **Low H** → diffuse (ambiguous mapping)

This lets you:

- filter unreliable mappings  
- run sensitivity checks  
- interpret results more cautiously  

---

## How to use

```r

mapping <- readr::read_csv("https://raw.githubusercontent.com/bcgov/onet-noc2021-crosswalk/main/output/2.0.0/onet_to_noc2021_mapping.csv")

strength <- readr::read_csv("https://raw.githubusercontent.com/bcgov/onet-noc2021-crosswalk/main/output/2.0.0/onet_to_noc2021_mapping_strength.csv")

```

Note: above URLs point to version 2.0.0. (future changes likely)

---

## Build from scratch

Clone from github and 

```r
source("onet_noc_mapping.R")
```

which allows you to choose tuning parameters

```r
gt_one = 2
```

- `gt_one`: the power to raise base weights (should be greater than 1)

---

## Key assumptions

- equal weighting within one-to-many links  
- weights reflect **structure of concordances**, not observed flows  
- senior manager NOCs are collapsed (`00011–00015 → 00018`)  

---

## Caveats

- constructed concordance (not official)  
- equal weights are mechanical  
- depends on crosswalk chain quality  
- choice of `gt_one` requires judgement   

---

## Validation and use in practice

The Herfindahl index provides a simple diagnostic of mapping quality.

- High values indicate that a NOC is largely associated with a small number of O*NET occupations  
- Low values indicate diffuse mappings and greater ambiguity  

In practice, this matters:

- Low-H occupations tend to behave like noisy measurements  
- High-H occupations behave more like well-measured constructs  

This makes it straightforward to:

- filter weak mappings  
- check robustness across mapping quality  
- identify where crosswalk-based skill measures are likely to break down  

---

## Repository structure

```
onet-to-noc2021-crosswalk/
├── onet_noc_mapping.R
├── data-raw/
├── output/
└── README.md
```

---

## Citation

> Martin, Richard. 2026. *O*NET 2019 to NOC 2021 Crosswalk*. GitHub.

---

## License

Apache
