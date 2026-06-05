# QCEW-FRK spatio-temporal wage interpolation

This repository documents an R workflow for completing suppressed county-quarter wage records from the U.S. Bureau of Labor Statistics Quarterly Census of Employment and Wages (QCEW). The empirical application focuses on NAICS 445, food and beverage stores, and uses spatio-temporal Fixed Rank Kriging (FRK) to predict wage values that are not published because of disclosure restrictions.

The project grew out of a practical data problem. QCEW wage series are valuable for regional labor-market research, but disclosure suppression leaves gaps in the county-quarter panel. The code builds the panel, deflates wages with CPI data, prepares county geometries, fits the FRK model, predicts the suppressed wage records, and checks the completed panel against an observed-wage holdout sample.

I have kept the structure of the repository deliberately explicit. A doctoral student or applied researcher should be able to see where the raw data enter, where the main script is located, and where the generated objects, figures, tables, and logs are written after execution.

For a more detailed view of the figures, validation design, and modelling setup, see [`Methodological_Appendix.md`](Methodological_Appendix.md).

## Problem

Some QCEW wage records are suppressed for confidentiality reasons. If those cells are simply dropped, the resulting panel becomes incomplete and less useful for spatial or regional analysis.

The workflow separates three cases before modelling:

- observed wage records;
- suppressed records used as prediction targets;
- real-zero records, which are kept as zeros and are not interpolated.

This distinction is important. The aim is not only to fill empty cells, but to complete the wage panel while keeping the data decisions visible and reproducible.

## Data

The workflow uses BLS QCEW CSV files and CPI data. The empirical unit is the county-quarter. The current application covers NAICS 445 for the contiguous United States from 1990 through 2025 Q3. Nominal weekly wages are converted to 2024 dollars before modelling.

Before model fitting, the script filters the QCEW files, checks the panel structure, classifies observed records, suppressed prediction targets, and real-zero records, prepares the county geometries, and builds the spatio-temporal objects used by FRK.

## Method

The workflow uses Fixed Rank Kriging through the R package `FRK`, which implements spatial and spatio-temporal prediction through Spatial Random Effects, basis functions, and Basic Areal Units (Cressie & Johannesson, 2008; Zammit-Mangion & Cressie, 2021). This representation is useful here because the panel is large, spatially structured, and observed repeatedly over time.

In this project, FRK is the interpolation method. The applied task is the imputation of suppressed QCEW wage records. The production specification uses a spatio-temporal Spatial Random Effects model with `z ~ 1`, `response = "gaussian"`, `K_type = "precision"`, and TMB-based estimation (Kristensen et al., 2016; Sainsbury-Dale et al., 2024). The validation run withholds a stratified sample of observed wages, re-fits the model, and compares predictions with the withheld observations.

The contribution is not a new estimator. It is a fully documented workflow that prepares QCEW wage data, preserves the distinction between observed, suppressed, and real-zero records, fits a spatio-temporal FRK model, predicts suppressed wage values, validates the predictions, and writes auditable outputs.

## Repository structure

```text
qcew-frk-spatiotemporal-wage-interpolation/
|-- 1_Data/              # Raw QCEW and CPI input data
|-- 2_Code/              # Main R workflow
|   `-- 01_main_analysis.R
|-- 3_Outputs/           # Generated outputs
|   |-- 1_Data_Processed/
|   |-- 2_Models/
|   |-- 3_Figures/
|   `-- 4_Tables/
|-- 4_Literature/        # Bibliographic references
|-- 5_Manuscript/        # Manuscript drafts and research notes
|-- 6_Presentation/      # Presentation materials
|-- Methodological_Appendix.md
|-- README.md
`-- Project 1.Rproj      # RStudio project file
```

The `3_Outputs/` folders are part of the expected workflow structure. They are populated when the script is run. Large generated objects should be treated as reproducible outputs, not as files to edit manually.

## How to run

Open the RStudio project file:

```text
Project 1.Rproj
```

Then run the main script from the project root:

```r
source("2_Code/01_main_analysis.R")
```

The script writes processed data, fitted model objects, figures, tables, and logs to:

```text
3_Outputs/
```

All generated objects, figures, tables, and logs are written under `3_Outputs/`. Package versions and run details should be checked in the generated logs before citing results.

## Validation snapshot

The current production run completed the CONUS target imputation and the observed-wage holdout validation. The values below are included as a compact audit trail, not as a substitute for the full manuscript results.

| Quantity | Value |
|---|---:|
| CONUS records used in the completed panel | 412,437 |
| Observed wage records | 358,984 |
| Suppressed target records imputed | 50,695 |
| Real-zero records | 2,758 |
| Holdout observations | 17,880 |
| RMSE, log real wage | 0.1803 |
| Bias, log real wage | -0.0017 |
| Empirical 95% interval coverage | 94.79% |

Both the main model and the validation model reported convergence code 0. Full validation details, including MAE and correlation, are reported in the methodological appendix.

## Quality checks

The script includes checks that are easy to miss in this kind of work:

- duplicate county-quarter keys;
- CPI coverage;
- FIPS consistency;
- county-geometry matching;
- separation of observed, target, and real-zero records;
- missing predictions after completion;
- model convergence;
- high-leverage or anomalous results.

These checks matter because, in a workflow like this, the largest risks are often silent data-handling errors rather than visible model failures.

## Outputs

After execution, the workflow produces processed wage panels, fitted model objects, figures, validation tables, temporal audit tables, anomaly checks, and reproducibility logs.

The main categories of outputs are:

- `3_Outputs/1_Data_Processed/`: processed data, audits, validation objects, and logs;
- `3_Outputs/2_Models/`: fitted model objects, basis functions, BAUs, and spatial objects;
- `3_Outputs/3_Figures/`: maps and validation figures;
- `3_Outputs/4_Tables/`: interpolation, validation, period-audit, and anomaly tables.

## What this repository adds

The repository offers a documented path through a problem that is common in applied work with administrative data: the data are public and useful, but not complete in the form needed for empirical analysis.

The repository is also meant to save time for other doctoral students. Much of the difficult work is in the details: identifying suppressed records, keeping real zeros separate, matching FIPS codes to geometries, checking the panel, and making sure that the final outputs can be audited.

## References

Cressie, N., & Johannesson, G. (2008). Fixed rank kriging for very large spatial data sets. *Journal of the Royal Statistical Society: Series B (Statistical Methodology), 70*(1), 209-226. https://doi.org/10.1111/j.1467-9868.2007.00633.x

Kristensen, K., Nielsen, A., Berg, C. W., Skaug, H., & Bell, B. (2016). TMB: Automatic differentiation and Laplace approximation. *Journal of Statistical Software, 70*(5), 1-21. https://doi.org/10.18637/jss.v070.i05

Sainsbury-Dale, M., Zammit-Mangion, A., & Cressie, N. (2024). Modeling big, heterogeneous, non-Gaussian spatial and spatio-temporal data using FRK. *Journal of Statistical Software, 108*(10), 1-39. https://doi.org/10.18637/jss.v108.i10

Zammit-Mangion, A., & Cressie, N. (2021). FRK: An R package for spatial and spatio-temporal prediction with large datasets. *Journal of Statistical Software, 98*(4), 1-48. https://doi.org/10.18637/jss.v098.i04

## Authors

Juan Pablo Rodriguez Paredes  
Department of Applied Economics  
Universidad Autonoma de Madrid

Research supervision: Coro Chasco Yrigoyen and Beatriz Sanchez Reyes.

## Status

This repository is under development as part of a research project on spatio-temporal interpolation and imputation of suppressed QCEW wage data.
