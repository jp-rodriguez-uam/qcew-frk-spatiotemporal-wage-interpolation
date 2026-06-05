# Methodological appendix

This empirical application focuses on NAICS 445 (food and beverage stores), using county-quarter QCEW wage records for the contiguous United States (CONUS) from 1990 through 2025 Q3.

This appendix documents the main methodological decisions behind the workflow: the data problem, the FRK specification, the validation design, and the diagnostic figures generated after model fitting. The objective is to complete wage records suppressed for disclosure reasons while keeping observed wages and real-zero records separate. This distinction is central: the model predicts suppressed wages, but it does not convert true zero activity into missing wage observations.

## 1. Data problem

QCEW data are useful for regional labor-market research because they provide employment and wage information at fine geographic and temporal scales. The difficulty is that some wage values are not published. These suppressions are part of the disclosure-protection system, so they should not be handled as ordinary blanks in a spreadsheet.

Before modeling, the script separates the panel into three groups:

- observed wage records;
- suppressed wage records used as prediction targets;
- real-zero records, retained as zeros and excluded from interpolation.

This classification is a small step in the code, but it carries much of the methodological discipline of the project. If suppressed records and real zeros are mixed together, the model would be asked to solve the wrong problem. Suppression is not treated as a set of unrelated spreadsheet blanks. The empirical diagnostic in Figure 1 shows that missingness is spatially uneven, which motivates a spatio-temporal prediction approach.

### Data sources

The raw wage data are from the U.S. Bureau of Labor Statistics Quarterly Census of Employment and Wages (QCEW). The workflow uses QCEW CSV files classified by NAICS and filters the empirical application to NAICS 445, food and beverage stores (U.S. Bureau of Labor Statistics, n.d.-a). Nominal wages are deflated using CPI data from the BLS Consumer Price Index program (U.S. Bureau of Labor Statistics, n.d.-b). The script records the data-processing steps needed to move from raw QCEW and CPI inputs to the county-quarter modeling panel.

Disclosure suppression should not be interpreted as random missingness, and in particular should not be treated as Missing Completely at Random (MCAR). Suppression can be related to local industry structure, establishment counts, or market concentration. The FRK workflow therefore treats the missing wage cells as a structured spatio-temporal prediction problem, while preserving an indicator that distinguishes imputed values from observed QCEW records.

## 2. Spatial suppression pattern

The first diagnostic question is where suppression occurs repeatedly. Figure 1 maps cumulative suppression intensity across counties. The purpose of this figure is not only descriptive. It also checks whether the missingness problem has spatial structure, which supports treating the panel as a spatio-temporal prediction problem rather than as a set of unrelated missing cells.

<p align="center"><img src="./3_Outputs/3_Figures/Fig1_Spatial_Suppression_Intensity.png" alt="Spatial suppression intensity" width="620"></p>

<p align="center"><strong>Figure 1.</strong> Cumulative suppression intensity by county across the study period. Darker counties accumulated more suppressed quarters and therefore represent locations where the completed panel relies more heavily on model-based prediction.</p>

The map shows that suppression is spatially uneven. Some counties accumulate many suppressed quarters, while others have much more complete wage histories. This spatial concentration is methodologically important: it indicates that the missing wage cells should not be treated as independent spreadsheet blanks. Instead, the workflow treats geography and repeated observation over time as part of the information set used for prediction.

## 3. Model specification

The workflow uses Fixed Rank Kriging through the `FRK` package in R. The modeling strategy follows the logic of Spatial Random Effects models for large spatial and spatio-temporal datasets, where a full covariance approach would be computationally unattractive at this scale (Cressie & Johannesson, 2008; Zammit-Mangion & Cressie, 2021).

The model is fitted on log real weekly wages because observed wage distributions are right-skewed and strictly positive for wage records used in the FRK fit. The log transformation stabilizes scale variation and makes the Gaussian SRE specification more appropriate for the observed wage process. Real-zero records are excluded from the log-wage model and retained separately as true zero-activity records.

The observed modeling variable is the log real weekly wage used by FRK:

```math
z_i = \log\left(W^{\mathrm{real}}_{s_i,t_i}\right) = Y(s_i,t_i) + \epsilon_i .
```

The latent process is represented as:

```math
Y(s,t) = \beta_0 + \mathbf{g}(s,t)^{\top}\boldsymbol{\eta} + \xi(s,t) .
```

Here, \(z_i\) is the observed log real weekly wage used by the FRK model, \(W^{\mathrm{real}}_{s_i,t_i}\) is the CPI-deflated weekly wage for county \(s_i\) and quarter \(t_i\), \(Y(s,t)\) is the latent spatio-temporal wage process, \(\beta_0\) is the global intercept implied by the production formula `z ~ 1`, \(\mathbf{g}(s,t)\) is the vector of spatio-temporal basis functions, \(\boldsymbol{\eta}\) is the vector of random effects, \(\xi(s,t)\) captures fine-scale variation, and \(\epsilon_i\) is measurement error.

The production run uses 141 spatial bisquare basis functions and seven temporal bisquare basis functions, yielding 987 spatio-temporal basis functions. The model is fitted with `response = "gaussian"`, `f = z ~ 1`, `K_type = "precision"`, and `est_error = FALSE`. Measurement-error standard deviation is fixed at 2% of the observed standard deviation of log real wages, so measurement error is treated as small relative to process variation rather than estimated freely.

In the production run, the Spatial Random Effects model is estimated with TMB and a sparse precision-matrix parameterization. TMB is used for likelihood-based estimation with automatic differentiation and Laplace approximation (Kristensen et al., 2016). This setup makes the spatio-temporal model feasible for a large county-quarter panel without treating imputed values as if they were directly observed data. The newer FRK implementation also supports this type of large spatial and spatio-temporal modeling framework (Sainsbury-Dale et al., 2024).

## 4. Before and after completion

Figure 2 shows the practical effect of the prediction step for the quarter with the largest wage gap in the panel. This makes the display a stress test rather than a visually convenient example. The left panel represents the observed wage surface with suppressed or non-observed records unavailable. The right panel shows the same period after completing suppressed records through FRK prediction.

<p align="center"><img src="./3_Outputs/3_Figures/Fig2_Before_After_Imputation_Map.png" alt="Before and after completion" width="660"></p>

<p align="center"><strong>Figure 2.</strong> Observed and FRK-completed wage surfaces for the quarter with the largest wage gap. Panel A shows the raw observed surface with suppressed or non-observed counties unavailable; Panel B shows the completed surface after FRK prediction.</p>

The figure should be read as a diagnostic display. It shows how the completed surface restores spatial continuity under severe missingness while preserving the distinction between observed, imputed, and real-zero records. A visually coherent map does not by itself prove predictive accuracy; that role is taken by the holdout validation in Section 7.

## 5. Completed wage field

After the imputation step, the workflow produces a complete county-quarter wage field for the analyzed panel. Figure 3 presents the completed log real wage field for the latest available quarter. The figure shows the final object produced by the workflow: a spatially complete wage surface that still preserves the distinction between observed and imputed values in the underlying data.

<p align="center"><img src="./3_Outputs/3_Figures/Fig3_Completed_Field_Latest_Quarter.png" alt="Completed wage field" width="620"></p>

<p align="center"><strong>Figure 3.</strong> Completed log real wage field for the latest available quarter. Real-zero records are retained in the completed panel but omitted from the log-wage color scale.</p>

The map gives a compact view of the completed field and helps assess whether the broad spatial pattern is plausible after imputation. It should not replace county-level inspection. Counties omitted from the log-wage color scale correspond to real-zero or otherwise non-loggable records retained separately by the workflow, not to failed predictions.

## 6. Prediction uncertainty

Point predictions alone are insufficient for robust spatial analysis. Imputed wages should be accompanied by uncertainty estimates, especially when they may later be used in downstream empirical models. Figure 4 reports the prediction uncertainty produced by the FRK workflow for the latest available quarter.

<p align="center"><img src="./3_Outputs/3_Figures/Fig4_FRK_Prediction_Uncertainty.png" alt="Prediction uncertainty" width="620"></p>

<p align="center"><strong>Figure 4.</strong> FRK prediction uncertainty for the latest available quarter. Brighter counties indicate higher prediction RMSPE/SE and therefore less precise completed values.</p>

The uncertainty map is central for interpretation. Darker areas generally correspond to observed records or locations with lower prediction uncertainty, while brighter counties indicate places where imputed values are less precise. This output is important for downstream users because it identifies where completed wage values should be treated with greater caution in descriptive or econometric work.

## 7. Holdout validation

Point predictions alone do not establish whether the uncertainty surface is well calibrated. The holdout exercise addresses this question by withholding a stratified sample of observed wages, refitting the model, and comparing predictions with held-out observations. Figure 5 summarizes this comparison with a hexbin density plot, which is more readable than a raw scatter plot for a large validation sample.

<p align="center"><img src="./3_Outputs/3_Figures/Fig5_Holdout_Validation_Hexbin.png" alt="Holdout validation" width="560"></p>

<p align="center"><strong>Figure 5.</strong> Observed versus FRK-predicted log real wages in the holdout sample (hexbin density plot, n = 17,880 county-quarter observations). The dashed line denotes perfect prediction.</p>

The validation results are summarized in Table 1. These statistics should be read as a validation audit for the imputation workflow, not as a final substantive result about the wage structure of the sector. The corresponding generated tables are written to `3_Outputs/4_Tables/`.

**Table 1. Summary of the completed CONUS panel and holdout validation results.**

| Quantity | Value |
|:---|---:|
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

The RMSE of 0.1803 is measured on the log real-wage scale. As a rough interpretation, this corresponds to an average prediction error on the order of 18 log points, roughly 20% on the original wage scale. The small mean bias and empirical 95% interval coverage close to the nominal level (94.79%) support the calibration of the workflow for imputation. The moderate holdout correlation of 0.6344 reflects the difficulty of county-quarter wage prediction in a heterogeneous national panel and underscores the importance of carrying imputation uncertainty into downstream analyses.

Both the main model and the validation model reported convergence code 0 with the `nlminb` message `relative convergence (4)`: 55 iterations for the main model and 65 iterations for the validation model.

The corresponding elapsed times in the production log were approximately 4,821 seconds for the main fit and 5,175 seconds for the validation fit. These timings should be read as machine-dependent, but they make clear that the full workflow is a multi-hour computation rather than a short interactive example.

## 8. State-year overview

Once the panel is completed, it can be aggregated to inspect broader temporal patterns. Figure 6 provides a state-year overview of completed real weekly wages. The purpose of this display is diagnostic: it helps identify aggregate patterns and high-leverage state-year cells, but it is not by itself a substantive analysis of state wage dynamics.

<p align="center"><img src="./3_Outputs/3_Figures/Fig6_Hovmoller_State_Year_Wages.png" alt="State-year wage heatmap" width="580"></p>

<p align="center"><strong>Figure 6.</strong> State-year overview of completed real weekly wages. The heatmap is used as an aggregate diagnostic to identify broad temporal patterns and state-year observations requiring audit.</p>

### Arizona 2022 audit

The state-year overview in Figure 6 identifies Arizona in 2022 as a high-leverage observation. A post-run audit shows that this pattern is driven by Greenlee County, Arizona (FIPS 04011), where the completed real weekly wage is unusually high in 2022 Q1-Q3. The corresponding generated audit tables are written to `3_Outputs/4_Tables/`.

| County | Year | Quarter | Completed real weekly wage | Record status |
|---|---:|---:|---:|---|
| Greenlee County, AZ | 2022 | Q1 | 4,652.51 | Observed |
| Greenlee County, AZ | 2022 | Q2 | 3,546.76 | Observed |
| Greenlee County, AZ | 2022 | Q3 | 3,773.77 | Observed |

The Arizona 2022 audit is not a validation exercise in itself. It is a source-data integrity check. The high Greenlee County values enter the completed panel as observed QCEW records, not as FRK-imputed targets. The workflow therefore preserves high-leverage observed data rather than smoothing them away.

This distinction matters for interpretation. The outlier affects the unweighted Arizona state-year average shown in Figure 6, but it does not indicate a failure of the FRK imputation procedure. Users working with state-level aggregates should treat Arizona 2022 with caution and may consider median aggregation, winsorized means, or sensitivity checks excluding high-leverage observed county-year records.

## 9. Reproducibility checks

The script includes checks before and after model fitting:

- column-count checks during import;
- duplicate key checks for county-quarter records;
- CPI coverage checks before deflation;
- observed, target, and real-zero classification checks;
- FIPS remapping and geometry matching checks;
- BAU and basis-function coverage checks;
- model convergence checks;
- missing prediction checks after imputation;
- validation by year and by quarter.

These checks are included because small data-handling errors can become difficult to detect after model fitting. The objective is to make the workflow auditable: a reader should be able to trace how the raw QCEW files become a completed wage panel.

The workflow also writes `session_info.txt` and `session_info.rds` to document the R version and package versions used in the completed run. For a formal replication package, these logs should be complemented with a committed `renv.lock` file, so that the same package environment can be restored on a new machine.

## 10. Methodological limits

The workflow should be understood as a reproducible imputation procedure, not as a causal inference model. It completes suppressed wage records by borrowing information across space and time under the structural assumptions of the FRK specification. The completed panel can support later empirical work, but those downstream analyses still require their own causal identification strategy, diagnostics, and robustness checks.

Three limitations are especially relevant:

1. The workflow is designed for NAICS 445 and the contiguous United States. Applying it to other sectors or geographies requires checking the filters, panel structure, and spatial support again.
2. The FRK specification imposes a structured spatio-temporal dependence model. This is useful for scalability, but it remains a modeling assumption.
3. Imputed values should be documented as imputed in downstream use. They should not be silently treated as original QCEW observations.

The holdout validation documents predictive performance for the FRK workflow, but it is not a full model-comparison exercise. A journal manuscript should compare the FRK specification with simpler temporal, spatial, and non-spatial benchmarks before making claims about relative predictive superiority.

Downstream analyses using the completed panel should retain an imputation indicator and, where feasible, assess sensitivity to prediction uncertainty. Imputed wage values should not be silently treated as original QCEW observations. These limits do not weaken the workflow; they make its scope explicit.

## Code and data availability

The complete R workflow is maintained in this repository. Raw QCEW and CPI inputs are obtained from official BLS sources and are not manually edited inside the repository. The script writes processed data, fitted model objects, figures, validation tables, audit tables, reproducibility logs, and the output manifest to `3_Outputs/`. For journal submission, the repository should be frozen as a versioned release and archived with a persistent identifier, such as a Zenodo DOI. Any data that cannot be redistributed directly should be documented with exact access instructions, source URLs, processing scripts, and any limitations on redistribution.

## Reference map

The citations in this appendix are used for specific claims rather than as decorative bibliography. Cressie and Johannesson (2008) support the fixed-rank representation with a fixed set of basis functions for very large spatial datasets. Zammit-Mangion and Cressie (2021) support the implementation of FRK in R, including BAUs, Spatial Random Effects models, and spatial or spatio-temporal prediction with large datasets. Kristensen et al. (2016) support the use of TMB for automatic differentiation and Laplace-approximation-based likelihood computation. Sainsbury-Dale et al. (2024) support the newer FRK framework for large, heterogeneous spatial and spatio-temporal data and document the TMB-based extension used in modern FRK workflows. The BLS references document the QCEW wage files and CPI data sources; they are data-source citations, not methodological claims.

## References

Cressie, N., & Johannesson, G. (2008). Fixed rank kriging for very large spatial data sets. *Journal of the Royal Statistical Society: Series B (Statistical Methodology), 70*(1), 209-226. https://doi.org/10.1111/j.1467-9868.2007.00633.x

Kristensen, K., Nielsen, A., Berg, C. W., Skaug, H., & Bell, B. (2016). TMB: Automatic differentiation and Laplace approximation. *Journal of Statistical Software, 70*(5), 1-21. https://doi.org/10.18637/jss.v070.i05

Sainsbury-Dale, M., Zammit-Mangion, A., & Cressie, N. (2024). Modeling big, heterogeneous, non-Gaussian spatial and spatio-temporal data using FRK. *Journal of Statistical Software, 108*(10), 1-39. https://doi.org/10.18637/jss.v108.i10

U.S. Bureau of Labor Statistics. (n.d.-a). *Quarterly Census of Employment and Wages: QCEW data files*. Retrieved June 5, 2026, from https://www.bls.gov/cew/downloadable-data-files.htm

U.S. Bureau of Labor Statistics. (n.d.-b). *Consumer Price Index databases*. Retrieved June 5, 2026, from https://www.bls.gov/cpi/data.htm

Zammit-Mangion, A., & Cressie, N. (2021). FRK: An R package for spatial and spatio-temporal prediction with large datasets. *Journal of Statistical Software, 98*(4), 1-48. https://doi.org/10.18637/jss.v098.i04
