# O*NET 2019 → NOC 2021 Crosswalk V3.0.0

A reproducible mapping from O\*NET-SOC 2019 occupations to NOC 2021 that:

- assigns weights to many-to-many mappings  
- downweights low-weight occupations (noise reduction)  
- provides measures of mapping quality (concentration, dispersion, and sensitivity)

This is a data product, not an R package.

---

## Why not “just use OaSIS”?

OaSIS provides a high-quality, curated mapping between occupations and skill descriptors, and is an important resource for applied labour market analysis in Canada.

This project is not intended to replace OaSIS. Instead, it addresses a different problem.

> It represents each NOC as a distribution over O*NET occupations, and makes mapping uncertainty explicit.

### Different objective

OaSIS is designed as a general-purpose, expert-informed mapping.

In contrast, this project is designed for applications where:

- occupations must be embedded in a continuous skill space, and  
- distances between occupations play a central role (e.g., modeling mobility or substitution)

These use cases place particular demands on the mapping that are not the primary focus of OaSIS.

---

### Many-to-many mappings and hidden uncertainty

Mapping between O*NET occupations and NOC occupations is inherently many-to-many.

In such settings, a single point mapping can obscure important structure:

- Some NOCs map to a small number of very similar O*NET occupations  
- Others map to many occupations with diverse skill profiles

These cases are qualitatively different, but are often treated identically in standard mappings.

This project makes that distinction explicit.

---

### Comparison

| Dimension      | OaSIS                         | This project                            |
|:----------------|:-------------------------------|:-----------------------------------------|
| Representation | Single profile per NOC        | Distribution over O*NET occupations     |
| Construction   | Expert-informed              | Algorithmic, reproducible               |
| Transparency   | Limited                      | Full                                    |
| Uncertainty    | Not reported                 | Explicitly quantified                   |
| Tunability     | Fixed                        | User-adjustable                         |

OaSIS effectively resolves mapping internally.

This project exposes the mapping and measures its ambiguity.

---

## What this repository provides

Running the build script produces:

- `onet_to_noc2021_paths.csv`  
  All admissible mapping paths with path weights

- `onet_to_noc2021_mapping.csv`  
  Aggregated NOC-level weights over O*NET occupations

- `diagnostics.csv`  
  Measures of mapping quality for each NOC, including:
  - concentration (Herfindahl index)
  - dispersion in skill space
  - sensitivity to down-weighting

---

## Key idea

The mapping answers:

> For a given NOC 2021 occupation, which O*NET occupations contribute skill content, and with what weights?

This allows each NOC to be evaluated not just by its mapped skill profile, but by how reliably that profile represents the underlying occupations.

---

## Method (short version)

Mapping chain:

1. O*NET 2019 → SOC 2018  
2. SOC 2018 → NOC 2016  
3. NOC 2016 → NOC 2021  

### Weighting

Each one-to-many mapping is split evenly:

w = 1 / n_targets

Path weights are the product of weights across stages:

path_weight = w1 × w2 × w3

---

## Down-weighting

Base weights are raised to a power (default = 2) and renormalized.

This reduces the influence of small-weight (noisy) mappings.

---

## Mapping quality

### 1. Herfindahl index (concentration)

H = Σ w_i²

Higher values indicate more concentrated mappings.

---

### 2. Dispersion in skill space

Dispersion measures how tightly the mapped O*NET occupations cluster in skill space.

- Low dispersion → occupations are similar → a single skill profile is representative  
- High dispersion → occupations are heterogeneous → a single profile is misleading  

---

### 3. Share of weights reallocated

Measures how much the mapping changes under down-weighting.

---

## How to use

```r
mapping <- readr::read_csv(
  "https://raw.githubusercontent.com/bcgov/onet-noc2021-crosswalk/main/output/3.0.0/onet_to_noc2021_mapping.csv"
)
```

---

## Citation

> "Transparent O*NET (2019) to NOC (2021) mapping", Martin, Richard. 2026.
