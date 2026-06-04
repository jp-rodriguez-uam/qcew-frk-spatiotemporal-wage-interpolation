# Methodological Appendix

This appendix gives a more detailed view of the workflow behind the repository. The main `README.md` is meant to be the entry point. This file is for readers who want to see the modelling logic, the validation design, and the main figures without opening the R script first.

The application uses county-quarter QCEW wage records for NAICS 445, food and beverage stores. The goal is to complete wage records that are suppressed for disclosure reasons, while keeping observed wages and real-zero records separate.

## 1. Data Problem

QCEW data are useful for regional labor-market research because they provide detailed employment and wage information at fine geographic and temporal scales. The difficulty is that some wage values are not published. These suppressions are not random blanks in a spreadsheet; they are part of the disclosure-protection system and need to be treated carefully.

The workflow separates the panel into three groups:

- observed wage records;
- suppressed records used as prediction targets;
- real-zero records, which are kept as zeros and are not interpolated.

This separation is one of the main data decisions in the project. It prevents the model from treating true zero economic activity as a missing wage value.

## 2. Spatial Suppression Pattern

The first diagnostic step is to inspect where suppression appears repeatedly across counties. This matters because suppression is not only a technical problem. It can also reflect spatial and sectoral structure in the data.

![Spatial suppression intensity](3_Outputs/3_Figures/Fig1_Spatial_Suppression_Intensity.png)

**Figure 1.** Cumulative suppression intensity by county across the study period.

## 3. Modelling Setup

The workflow uses Fixed Rank Kriging through the `FRK` package in R. The basic idea is to model the wage field as a mean component plus a structured spatio-temporal random component and an error term.

In simplified form, the observed process can be written as:

```math
Y(s,t) = \mu(s,t) + S(s,t) + e(s,t)
```

where `s` indexes space, `t` indexes time, `mu(s,t)` is the large-scale mean structure, `S(s,t)` is the latent spatio-temporal process, and `e(s,t)` is an error term.

Fixed Rank Kriging represents the latent process with a finite set of basis functions:

```math
S(s,t) = G(s,t)\eta + \xi(s,t)
```

Here, `G(s,t)` contains the spatio-temporal basis functions, `eta` is the vector of random effects, and `xi(s,t)` captures remaining fine-scale variation.

This low-rank representation is useful because the panel is too large for a naive full-covariance kriging approach. In the production run, the model is estimated with TMB and a sparse precision-matrix parameterization.

## 4. Before and After Completion

The figure below shows the practical effect of the workflow. Suppressed wage values are first left as unavailable in the observed surface and then completed through the FRK prediction step.

![Before and after imputation](3_Outputs/3_Figures/Fig2_Before_After_Imputation_Map.png)

**Figure 2.** Before and after comparison for the quarter with the largest wage gap.

## 5. Completed Wage Field

After the prediction step, the workflow produces a completed wage field for the available county-quarter panel.

![Completed wage field](3_Outputs/3_Figures/Fig3_Completed_Field_Latest_Quarter.png)

**Figure 3.** Completed log real wage field for the latest available quarter.

## 6. Prediction Uncertainty

The workflow does not only generate point predictions. It also stores prediction uncertainty through the FRK output. This is important because imputed values should not be treated as if they had the same status as directly observed records.

![Prediction uncertainty](3_Outputs/3_Figures/Fig4_FRK_Prediction_Uncertainty.png)

**Figure 4.** FRK prediction uncertainty for the latest available quarter.

## 7. Holdout Validation

To check predictive performance, the workflow withholds a stratified sample of observed wage records and then predicts them using a model fitted on the remaining observations. This gives a direct out-of-sample check because the withheld values are known.

![Holdout validation](3_Outputs/3_Figures/Fig5_Holdout_Validation_Hexbin.png)

**Figure 5.** Observed versus predicted log real wages in the holdout sample.

The current production run produced the following validation summary:

| Quantity | Value |
|---|---:|
| CONUS records used in the completed panel | 412,437 |
| Observed wage records | 358,984 |
| Suppressed target records imputed | 50,695 |
| Real-zero records | 2,758 |
| Holdout observations | 17,880 |
| RMSE, log real wage | 0.1803 |
| MAE, log real wage | 0.1364 |
| Bias, log real wage | -0.0017 |
| Correlation, log real wage | 0.6344 |
| Empirical 95% interval coverage | 94.79% |

These results should be read as a validation audit rather than as a final empirical claim. The full interpretation belongs in the manuscript.

## 8. State-Year Overview

Once the panel is completed, it can be aggregated to inspect broader temporal patterns. The Hovmoller-style figure gives a compact view of state-year wage levels after completion.

![State-year wage heatmap](3_Outputs/3_Figures/Fig6_Hovmoller_State_Year_Wages.png)

**Figure 6.** State-year overview of completed real weekly wages.

The Arizona 2022 anomaly was audited separately. The audit indicates that the high value is driven by observed QCEW records, not by FRK-imputed target records.

## 9. Reproducibility Checks

The script includes several checks before and after model fitting:

- column-count checks during import;
- duplicate key checks for county-quarter records;
- CPI coverage checks before deflation;
- observed, target, and real-zero classification checks;
- FIPS remapping and geometry matching checks;
- BAU and basis-function coverage checks;
- model convergence checks;
- missing prediction checks after imputation;
- validation by year and by quarter.

These checks are included because small data-handling errors can become difficult to detect once the model has been fitted.

## 10. Relation to the README and Manuscript

This file is meant to sit between the short repository README and the eventual manuscript. The README explains the project quickly. This appendix gives enough detail for a reader to understand what the workflow does and why the main outputs matter. The manuscript can then carry the full literature review, econometric discussion, robustness checks, and interpretation.

## References

Cressie, N., & Johannesson, G. (2008). Fixed rank kriging for very large spatial data sets. *Journal of the Royal Statistical Society: Series B (Statistical Methodology), 70*(1), 209-226. https://doi.org/10.1111/j.1467-9868.2007.00633.x

Kristensen, K., Nielsen, A., Berg, C. W., Skaug, H., & Bell, B. (2016). TMB: Automatic differentiation and Laplace approximation. *Journal of Statistical Software, 70*(5), 1-21. https://doi.org/10.18637/jss.v070.i05

Sainsbury-Dale, M., Zammit-Mangion, A., & Cressie, N. (2024). Modeling big, heterogeneous, non-Gaussian spatial and spatio-temporal data using FRK. *Journal of Statistical Software, 108*(10), 1-39. https://doi.org/10.18637/jss.v108.i10

Zammit-Mangion, A., & Cressie, N. (2021). FRK: An R package for spatial and spatio-temporal prediction with large datasets. *Journal of Statistical Software, 98*(4), 1-48. https://doi.org/10.18637/jss.v098.i04
