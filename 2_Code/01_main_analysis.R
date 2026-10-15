# ==============================================================================
# Title: Supplementary Methodological Appendix: Spatio-Temporal Interpolation of QCEW Wage Data
#
# Author: 
#   - Juan Pablo Rodríguez Paredes (PhD Candidate, UAM)
#
# Research Supervision & Academic Direction:
#   - Dra. Coro Chasco Yrigoyen (Directora de tesis, UAM)
#   - Dra. Beatriz Sánchez Reyes (Codirectora de tesis, UAM)
#
# Affiliations:
#   1. Department of Applied Economics, Universidad Autónoma de Madrid, Spain
#      Email: jpablo.rodriguez@estudiante.uam.es
#   2. Department of Applied Economics, Universidad Autónoma de Madrid, Spain
#      Email: coro.chasco@uam.es
#   3. Department of Applied Economics, Universidad Autónoma de Madrid, Spain
#      Email: beatriz.sanchez@uam.es
#
# Date: June 2026
# Version: 1.0
# Description:
#   This script constructs a county-quarter QCEW wage panel, deflates wages using CPI,
#   prepares CONUS county geometries, fits a spatio-temporal FRK model, predicts
#   suppressed wage values, and validates predictions using an observed-wage holdout.
#
# Reproducibility: Scripted workflow.
# ==============================================================================

# 1. Install and load packages.
pkgs <- c("here", "fs", "readr", "purrr", "dplyr", "tibble")

miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]

if (length(miss) > 0) {
  install.packages(miss, repos = "https://cloud.r-project.org")
}

invisible(lapply(pkgs, library, character.only = TRUE))

# 2. Define QCEW column names.
bls_cols <- c(
  "area_fips",
  "own_code",
  "industry_code",
  "agglvl_code",
  "size_code",
  "year",
  "qtr",
  "disclosure_code",
  "area_title",
  "own_title",
  "industry_title",
  "agglvl_title",
  "size_title",
  "qtrly_estabs_count",
  "month1_emplvl",
  "month2_emplvl",
  "month3_emplvl",
  "total_qtrly_wages",
  "taxable_qtrly_wages",
  "qtrly_contributions",
  "avg_wkly_wage",
  "lq_disclosure_code",
  "lq_qtrly_estabs_count",
  "lq_month1_emplvl",
  "lq_month2_emplvl",
  "lq_month3_emplvl",
  "lq_total_qtrly_wages",
  "lq_taxable_qtrly_wages",
  "lq_qtrly_contributions",
  "lq_avg_wkly_wage",
  "oty_disclosure_code",
  "oty_qtrly_estabs_count_chg",
  "oty_qtrly_estabs_count_pct_chg",
  "oty_month1_emplvl_chg",
  "oty_month1_emplvl_pct_chg",
  "oty_month2_emplvl_chg",
  "oty_month2_emplvl_pct_chg",
  "oty_month3_emplvl_chg",
  "oty_month3_emplvl_pct_chg",
  "oty_total_qtrly_wages_chg",
  "oty_total_qtrly_wages_pct_chg",
  "oty_taxable_qtrly_wages_chg",
  "oty_taxable_qtrly_wages_pct_chg",
  "oty_qtrly_contributions_chg",
  "oty_qtrly_contributions_pct_chg",
  "oty_avg_wkly_wage_chg",
  "oty_avg_wkly_wage_pct_chg"
)

# 3. Set data path.
data_path <- here::here("1_Data")

if (!fs::dir_exists(data_path)) {
  stop("Directory not found: ", data_path)
}

# 4. List CSV files.
csv_files <- fs::dir_ls(path = data_path,regexp = "\\.csv$",recurse = FALSE,type = "file")

if (length(csv_files) == 0) {
  stop("No CSV files found: ", data_path)
}

# 5. Import source files.
qcew_raw <- csv_files |>purrr::map(\(f) readr::read_csv(file = f,col_names = bls_cols,skip = 1,col_types = readr::cols(.default = readr::col_character()),show_col_types = FALSE,progress = FALSE)) |>purrr::list_rbind()

# 6. Validate source column count.
if (ncol(qcew_raw) != 47) {
  stop("Invalid source columns: ", ncol(qcew_raw))
}

# 7. Report import.
message(
  "Import complete: ",
  format(nrow(qcew_raw), big.mark = ","),
  " rows × ",
  ncol(qcew_raw),
  " columns"
)

message("Files imported: ", length(csv_files))

# 8. Build county-quarter panel.
panel_cty_qtr <- qcew_raw |>
  dplyr::filter(
    industry_code == "445",
    agglvl_code == "75",
    own_code == "5",
    size_code == "0",
    grepl("^[0-9]{5}$", area_fips),
    substr(area_fips, 3, 5) != "999"
  ) |>
  dplyr::arrange(year, qtr, area_fips)

if (nrow(panel_cty_qtr) == 0) {
  stop("Zero panel rows found.")
}

# 9. Validate panel column count.
if (ncol(panel_cty_qtr) != 47) {
  stop("Invalid panel columns: ", ncol(panel_cty_qtr))
}

# 10. Audit panel.
audit_cty_qtr <- panel_cty_qtr |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    rows = dplyr::n(),
    counties = dplyr::n_distinct(area_fips),
    quarters = paste(sort(unique(qtr)), collapse = ", "),
    four_qtrs = setequal(sort(unique(qtr)), c("1", "2", "3", "4")),
    agglvl_codes = paste(sort(unique(agglvl_code)), collapse = ", "),
    own_codes = paste(sort(unique(own_code)), collapse = ", "),
    size_codes = paste(sort(unique(size_code)), collapse = ", "),
    industry_codes = paste(sort(unique(industry_code)), collapse = ", "),
    .groups = "drop"
  ) |>
  dplyr::arrange(year)

# 11. Detect duplicate keys.
dups_cty_qtr <- panel_cty_qtr |>
  dplyr::count(year, qtr, area_fips, name = "n") |>
  dplyr::filter(n > 1) |>
  dplyr::arrange(year, qtr, area_fips)

# 12. List unique counties.
unique_cty <- panel_cty_qtr |>
  dplyr::distinct(area_fips, area_title) |>
  dplyr::arrange(area_fips)

# 13. Report panel.
message("Panel created: panel_cty_qtr")

message(
  "Rows × columns: ",
  format(nrow(panel_cty_qtr), big.mark = ","),
  " × ",
  ncol(panel_cty_qtr)
)

message(
  "Unique counties: ",
  format(dplyr::n_distinct(panel_cty_qtr$area_fips), big.mark = ",")
)

message(
  "Years: ",
  paste(sort(unique(panel_cty_qtr$year)), collapse = ", ")
)

message(
  "Quarters: ",
  paste(sort(unique(panel_cty_qtr$qtr)), collapse = ", ")
)

message(
  "Duplicate keys: ",
  format(nrow(dups_cty_qtr), big.mark = ",")
)

message("Annual audit:")
print(audit_cty_qtr, n = Inf)

if (nrow(dups_cty_qtr) > 0) {
  warning("Duplicate panel keys found.")
}

message("Objects created:")
message("1. panel_cty_qtr")
message("2. audit_cty_qtr")
message("3. dups_cty_qtr")
message("4. unique_cty")

# 14. Count suppressed rows.
supp_ann <- panel_cty_qtr |>
  dplyr::mutate(suppressed = disclosure_code == "N") |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    gaps = sum(suppressed, na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(year) |>
  (\(x) dplyr::bind_rows(
    x,
    tibble::tibble(
      year = "TOTAL",
      gaps = sum(x$gaps)
    )
  ))()

print(supp_ann, n = Inf)

# 15. Measure suppression rates.
supp_rate <- panel_cty_qtr |>
  dplyr::mutate(suppressed = disclosure_code == "N") |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    rows = dplyr::n(),
    gaps = sum(suppressed, na.rm = TRUE),
    pct = round(100 * gaps / rows, 2),
    .groups = "drop"
  ) |>
  dplyr::arrange(year) |>
  (\(x) dplyr::bind_rows(
    x,
    tibble::tibble(
      year = "TOTAL",
      rows = sum(x$rows),
      gaps = sum(x$gaps),
      pct = round(100 * sum(x$gaps) / sum(x$rows), 2)
    )
  ))()

print(supp_rate, n = Inf)

# 16. Compute mean counties per quarter.
mean_cty_qtr <- panel_cty_qtr |>
  dplyr::group_by(year, qtr) |>
  dplyr::summarise(
    counties = dplyr::n_distinct(area_fips),
    .groups = "drop"
  ) |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    mean_cty_qtr = round(mean(counties), 1),
    .groups = "drop"
  ) |>
  dplyr::arrange(year) |>
  (\(x) dplyr::bind_rows(
    x,
    tibble::tibble(
      year = "TOTAL",
      mean_cty_qtr = round(mean(x$mean_cty_qtr), 1)
    )
  ))()

print(mean_cty_qtr, n = Inf)

# 17. Define numeric parser.
to_num <- function(x) {
  suppressWarnings(
    readr::parse_number(
      as.character(x),
      locale = readr::locale(grouping_mark = ",", decimal_mark = ".")
    )
  )
}

# 18. Prepare numeric panel.
panel_num <- panel_cty_qtr |>
  dplyr::mutate(
    month1_emp = to_num(month1_emplvl),
    month2_emp = to_num(month2_emplvl),
    month3_emp = to_num(month3_emplvl),
    wk_wage = to_num(avg_wkly_wage),
    gap_emp = is.na(month1_emp) | month1_emp == 0 |
      is.na(month2_emp) | month2_emp == 0 |
      is.na(month3_emp) | month3_emp == 0,
    gap_wage = is.na(wk_wage) | wk_wage == 0,
    gap_any = gap_emp | gap_wage,
    log_wage = dplyr::if_else(
      !gap_wage,
      log(wk_wage),
      NA_real_
    )
  )

# 19. Measure analytical gaps.
gaps_ann <- panel_num |>
  dplyr::group_by(year) |>
  dplyr::summarise(
    rows_cty_qtr = dplyr::n(),
    counties_total = dplyr::n_distinct(area_fips),
    rows_gap_emp = sum(gap_emp, na.rm = TRUE),
    counties_gap_emp = dplyr::n_distinct(area_fips[gap_emp]),
    rows_gap_wage = sum(gap_wage, na.rm = TRUE),
    counties_gap_wage = dplyr::n_distinct(area_fips[gap_wage]),
    rows_gap_any = sum(gap_any, na.rm = TRUE),
    counties_gap_any = dplyr::n_distinct(area_fips[gap_any]),
    pct_gap_emp = round(100 * rows_gap_emp / rows_cty_qtr, 2),
    pct_gap_wage = round(100 * rows_gap_wage / rows_cty_qtr, 2),
    pct_gap_any = round(100 * rows_gap_any / rows_cty_qtr, 2),
    mean_wage = round(mean(wk_wage[!gap_wage], na.rm = TRUE), 2),
    cv_wage = round(
      100 * stats::sd(wk_wage[!gap_wage], na.rm = TRUE) /
        mean(wk_wage[!gap_wage], na.rm = TRUE),
      2
    ),
    .groups = "drop"
  ) |>
  dplyr::arrange(year) |>
  (\(x) dplyr::bind_rows(
    x,
    tibble::tibble(
      year = "TOTAL",
      rows_cty_qtr = sum(x$rows_cty_qtr),
      counties_total = dplyr::n_distinct(panel_num$area_fips),
      rows_gap_emp = sum(x$rows_gap_emp),
      counties_gap_emp = dplyr::n_distinct(panel_num$area_fips[panel_num$gap_emp]),
      rows_gap_wage = sum(x$rows_gap_wage),
      counties_gap_wage = dplyr::n_distinct(panel_num$area_fips[panel_num$gap_wage]),
      rows_gap_any = sum(x$rows_gap_any),
      counties_gap_any = dplyr::n_distinct(panel_num$area_fips[panel_num$gap_any]),
      pct_gap_emp = round(100 * sum(x$rows_gap_emp) / sum(x$rows_cty_qtr), 2),
      pct_gap_wage = round(100 * sum(x$rows_gap_wage) / sum(x$rows_cty_qtr), 2),
      pct_gap_any = round(100 * sum(x$rows_gap_any) / sum(x$rows_cty_qtr), 2),
      mean_wage = round(mean(panel_num$wk_wage[!panel_num$gap_wage], na.rm = TRUE), 2),
      cv_wage = round(
        100 * stats::sd(panel_num$wk_wage[!panel_num$gap_wage], na.rm = TRUE) /
          mean(panel_num$wk_wage[!panel_num$gap_wage], na.rm = TRUE),
        2
      )
    )
  ))()

# 20. Print analytical-gap table.
gaps_ann |>
  dplyr::select(
    year,
    rows_cty_qtr,
    counties_total,
    rows_gap_emp,
    counties_gap_emp,
    rows_gap_wage,
    counties_gap_wage,
    rows_gap_any,
    counties_gap_any,
    pct_gap_emp,
    pct_gap_wage,
    pct_gap_any,
    mean_wage,
    cv_wage
  ) |>
  print(n = Inf, width = Inf)

# 21. Build wage panel.
krig_dat <- panel_num |>
  dplyr::filter(
    qtr %in% c("1", "2", "3", "4")
  ) |>
  dplyr::mutate(
    year_id = as.integer(year),
    qtr_id = as.integer(qtr),
    time_id = (year_id - min(year_id, na.rm = TRUE)) * 4L + qtr_id,
    obs_wage = !gap_wage,
    target_wage = gap_wage
  ) |>
  dplyr::select(
    area_fips,
    area_title,
    year,
    qtr,
    year_id,
    qtr_id,
    time_id,
    disclosure_code,
    month1_emp,
    month2_emp,
    month3_emp,
    wk_wage,
    log_wage,
    gap_emp,
    gap_wage,
    gap_any,
    obs_wage,
    target_wage
  ) |>
  dplyr::arrange(time_id, area_fips)

# 22. Check time-index sequence.
time_check <- krig_dat |>
  dplyr::distinct(time_id, year, qtr) |>
  dplyr::arrange(time_id)

missing_time <- tibble::tibble(
  time_id = seq(min(time_check$time_id), max(time_check$time_id))
) |>
  dplyr::anti_join(time_check, by = "time_id")

if (nrow(missing_time) > 0) {
  stop("Nonconsecutive time index detected.")
}

# 23. Check duplicate keys.
dups_krig <- krig_dat |>
  dplyr::count(area_fips, time_id, name = "n") |>
  dplyr::filter(n > 1)

if (nrow(dups_krig) > 0) {
  stop("Duplicate kriging keys detected.")
}

# 24. Report wage panel.
message(
  "krig_dat: ",
  format(nrow(krig_dat), big.mark = ","),
  " rows × ",
  ncol(krig_dat),
  " columns"
)

message(
  "Counties: ",
  format(dplyr::n_distinct(krig_dat$area_fips), big.mark = ",")
)

message(
  "Time index: ",
  min(krig_dat$time_id),
  " to ",
  max(krig_dat$time_id)
)

message(
  "Observed log_wage: ",
  format(sum(krig_dat$obs_wage), big.mark = ",")
)

message(
  "Target log_wage: ",
  format(sum(krig_dat$target_wage), big.mark = ","),
  " (",
  round(100 * mean(krig_dat$target_wage), 2),
  "%)"
)

# 25. Load CPI processing packages.
pkgs_extra <- c("readxl", "tidyr")

miss_extra <- pkgs_extra[!vapply(pkgs_extra, requireNamespace, logical(1), quietly = TRUE)]

if (length(miss_extra) > 0) {
  install.packages(miss_extra, repos = "https://cloud.r-project.org")
}

invisible(lapply(pkgs_extra, library, character.only = TRUE))

# 26. Set official CPI file path.
cpi_file <- fs::path(
  data_path,
  "SeriesReport-20260510042325_50b325.xlsx"
)

if (!fs::file_exists(cpi_file)) {
  stop("CPI file not found: ", cpi_file)
}

# 27. Import official CPI data table.
cpi_xlsx <- readxl::read_excel(
  path = cpi_file,
  sheet = "BLS Data Series",
  skip = 11,
  col_types = "text",
  na = c("", "NA", "N/A", "-(X)", "X")
)

required_cpi_cols <- c(
  "Year",
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec"
)

missing_cpi_cols <- setdiff(required_cpi_cols, names(cpi_xlsx))

if (length(missing_cpi_cols) > 0) {
  stop(
    "Missing CPI columns: ",
    paste(missing_cpi_cols, collapse = ", ")
  )
}

# 28. Build monthly CPI series table.
month_lookup <- tibble::tibble(
  month_name = c(
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec"
  ),
  month_id = 1:12
)

cpi_monthly <- cpi_xlsx |>
  dplyr::select(dplyr::all_of(required_cpi_cols)) |>
  tidyr::pivot_longer(
    cols = -Year,
    names_to = "month_name",
    values_to = "cpi_raw"
  ) |>
  dplyr::left_join(month_lookup, by = "month_name") |>
  dplyr::mutate(
    year = as.character(as.integer(readr::parse_number(as.character(Year)))),
    cpi_value = readr::parse_number(
      as.character(cpi_raw),
      locale = readr::locale(grouping_mark = ",", decimal_mark = ".")
    ),
    qtr = as.character(((month_id - 1L) %/% 3L) + 1L)
  ) |>
  dplyr::filter(
    !is.na(year),
    !is.na(month_id),
    !is.na(cpi_value)
  ) |>
  dplyr::select(
    year,
    month_id,
    month_name,
    qtr,
    cpi_value
  ) |>
  dplyr::arrange(year, month_id)

# 29. Build quarterly CPI series table.
cpi_qtr <- cpi_monthly |>
  dplyr::group_by(year, qtr) |>
  dplyr::summarise(
    cpi_qtr = mean(cpi_value, na.rm = TRUE),
    n_months = dplyr::n(),
    .groups = "drop"
  ) |>
  dplyr::filter(n_months == 3L) |>
  dplyr::arrange(year, qtr)

# 30. Set constant-dollar base year.
base_year <- "2024"

cpi_base_tbl <- cpi_monthly |>
  dplyr::filter(year == base_year) |>
  dplyr::summarise(
    n_months = dplyr::n(),
    cpi_base = mean(cpi_value, na.rm = TRUE)
  )

if (cpi_base_tbl$n_months != 12L) {
  stop("Base year has incomplete CPI data: ", base_year)
}

cpi_base <- cpi_base_tbl$cpi_base

message(
  "CPI base year: ",
  base_year,
  " | CPI annual mean: ",
  round(cpi_base, 6)
)

# 31. Check CPI coverage for panel.
missing_cpi_panel <- krig_dat |>
  dplyr::distinct(year, qtr) |>
  dplyr::anti_join(
    cpi_qtr,
    by = c("year", "qtr")
  ) |>
  dplyr::arrange(year, qtr)

if (nrow(missing_cpi_panel) > 0) {
  print(missing_cpi_panel, n = Inf)
  stop("Missing CPI values for panel quarters.")
}

# 32. Deflate analytical wage panel values.
if (any(c(
  "wk_wage_nominal",
  "log_wage_nominal",
  "wk_wage_real",
  "log_wage_real",
  "krig_value"
) %in% names(panel_num))) {
  stop("Deflated wage columns already exist in panel_num.")
}

panel_num <- panel_num |>
  dplyr::left_join(
    cpi_qtr |>
      dplyr::select(year, qtr, cpi_qtr),
    by = c("year", "qtr")
  ) |>
  dplyr::mutate(
    cpi_base_year = base_year,
    cpi_base = cpi_base,
    deflator_to_base = cpi_base / cpi_qtr,
    wk_wage_nominal = wk_wage,
    log_wage_nominal = log_wage,
    wk_wage_real = dplyr::if_else(
      !gap_wage & !is.na(wk_wage_nominal) & !is.na(deflator_to_base),
      wk_wage_nominal * deflator_to_base,
      NA_real_
    ),
    log_wage_real = dplyr::if_else(
      !is.na(wk_wage_real) & wk_wage_real > 0,
      log(wk_wage_real),
      NA_real_
    )
  )

if (any(is.na(panel_num$cpi_qtr))) {
  stop("Missing CPI in panel_num.")
}

if (any(!panel_num$gap_wage & is.na(panel_num$log_wage_real))) {
  stop("Observed wages with missing real log wage.")
}

# 33. Build deflated modeling panel.
krig_dat <- panel_num |>
  dplyr::filter(
    qtr %in% c("1", "2", "3", "4")
  ) |>
  dplyr::mutate(
    year_id = as.integer(year),
    qtr_id = as.integer(qtr),
    time_id = (year_id - min(year_id, na.rm = TRUE)) * 4L + qtr_id,
    qtrly_estabs = to_num(qtrly_estabs_count),
    qtrly_wages = to_num(total_qtrly_wages),
    real_zero = (
      gap_wage &
        (is.na(disclosure_code) | disclosure_code != "N") &
        (is.na(month1_emp) | month1_emp == 0) &
        (is.na(month2_emp) | month2_emp == 0) &
        (is.na(month3_emp) | month3_emp == 0) &
        (is.na(qtrly_estabs) | qtrly_estabs == 0) &
        (is.na(qtrly_wages) | qtrly_wages == 0)
    ),
    obs_wage = !gap_wage,
    target_wage = gap_wage & !is.na(disclosure_code) & disclosure_code == "N",
    krig_value = log_wage_real
  ) |>
  dplyr::select(
    area_fips,
    area_title,
    year,
    qtr,
    year_id,
    qtr_id,
    time_id,
    disclosure_code,
    month1_emp,
    month2_emp,
    month3_emp,
    qtrly_estabs,
    qtrly_wages,
    wk_wage_nominal,
    log_wage_nominal,
    cpi_qtr,
    cpi_base_year,
    cpi_base,
    deflator_to_base,
    wk_wage_real,
    log_wage_real,
    krig_value,
    gap_emp,
    gap_wage,
    gap_any,
    real_zero,
    obs_wage,
    target_wage
  ) |>
  dplyr::arrange(time_id, area_fips)

# 34. Validate deflated panel keys and classifications.
time_check <- krig_dat |>
  dplyr::distinct(time_id, year, qtr) |>
  dplyr::arrange(time_id)

missing_time <- tibble::tibble(
  time_id = seq(min(time_check$time_id), max(time_check$time_id))
) |>
  dplyr::anti_join(time_check, by = "time_id")

if (nrow(missing_time) > 0) {
  stop("Nonconsecutive time index detected.")
}

dups_krig <- krig_dat |>
  dplyr::count(area_fips, time_id, name = "n") |>
  dplyr::filter(n > 1)

if (nrow(dups_krig) > 0) {
  stop("Duplicate kriging keys detected.")
}

if (any(krig_dat$obs_wage & is.na(krig_dat$krig_value))) {
  stop("Observed kriging values missing.")
}

if (any(krig_dat$real_zero & krig_dat$target_wage)) {
  stop("Real zero wages selected as targets.")
}

if (any(krig_dat$real_zero & krig_dat$obs_wage)) {
  stop("Real zero wages selected as observations.")
}

if (sum(krig_dat$obs_wage | krig_dat$target_wage | krig_dat$real_zero) != nrow(krig_dat)) {
  stop("Unclassified wage records found.")
}

# 35. Report deflated panel status.
deflator_audit <- krig_dat |>
  dplyr::summarise(
    rows = dplyr::n(),
    counties = dplyr::n_distinct(area_fips),
    time_periods = dplyr::n_distinct(time_id),
    observed_wage_n = sum(obs_wage, na.rm = TRUE),
    target_wage_n = sum(target_wage, na.rm = TRUE),
    real_zero_n = sum(real_zero, na.rm = TRUE),
    pct_target_wage = round(100 * target_wage_n / rows, 2),
    pct_real_zero = round(100 * real_zero_n / rows, 2)
  )

print(deflator_audit, width = Inf)

message("Deflated pre-kriging panel created: krig_dat")
message("Kriging variable: krig_value")
message(
  "Target values: ",
  format(sum(krig_dat$target_wage), big.mark = ","),
  " (",
  round(100 * mean(krig_dat$target_wage), 2),
  "%)"
)
message(
  "Real zero values: ",
  format(sum(krig_dat$real_zero), big.mark = ","),
  " (",
  round(100 * mean(krig_dat$real_zero), 2),
  "%)"
)

# 36. Load spatial packages.
pkgs_geo <- c(
  "sf",
  "tigris",
  "sp",
  "spacetime",
  "FRK",
  "dplyr",
  "tidyr",
  "here"
)

miss_geo <- pkgs_geo[
  !vapply(pkgs_geo, requireNamespace, logical(1), quietly = TRUE)
]

if (length(miss_geo) > 0) {
  install.packages(miss_geo, repos = "https://cloud.r-project.org")
}

invisible(lapply(pkgs_geo, library, character.only = TRUE))

options(tigris_use_cache = TRUE)

# 37. Filter to the contiguous United States.
conus_state_fips <- c(
  "01", "04", "05", "06", "08", "09", "10", "11", "12", "13",
  "16", "17", "18", "19", "20", "21", "22", "23", "24", "25",
  "26", "27", "28", "29", "30", "31", "32", "33", "34", "35",
  "36", "37", "38", "39", "40", "41", "42", "44", "45", "46",
  "47", "48", "49", "50", "51", "53", "54", "55", "56"
)

krig_base <- krig_dat |>
  dplyr::filter(
    substr(area_fips, 1L, 2L) %in% conus_state_fips
  ) |>
  dplyr::arrange(time_id, area_fips)

message(
  "krig_base after CONUS filter: ",
  format(nrow(krig_base), big.mark = ","),
  " rows | ",
  format(dplyr::n_distinct(krig_base$area_fips), big.mark = ","),
  " counties | years: ",
  paste(sort(unique(krig_base$year)), collapse = ", ")
)

if (nrow(krig_base) == 0) {
  stop("krig_base has zero rows after CONUS filter.")
}

# 38. Remap legacy county FIPS codes.
fips_remap <- tibble::tibble(
  area_fips_old = c(
    "46113",
    "51515", "51560"
  ),
  area_fips_new = c(
    "46102",
    "51019", "51005"
  )
)

n_remap <- sum(krig_base$area_fips %in% fips_remap$area_fips_old)

message(
  "Legacy CONUS FIPS remapped: ",
  n_remap,
  " records across ",
  dplyr::n_distinct(
    krig_base$area_fips[krig_base$area_fips %in% fips_remap$area_fips_old]
  ),
  " legacy FIPS codes."
)

krig_base <- krig_base |>
  dplyr::mutate(
    area_fips_original = area_fips
  ) |>
  dplyr::left_join(fips_remap, by = c("area_fips" = "area_fips_old")) |>
  dplyr::mutate(
    geom_fips = dplyr::if_else(
      !is.na(area_fips_new),
      area_fips_new,
      area_fips
    )
  ) |>
  dplyr::select(-area_fips_new)

if (any(is.na(krig_base$geom_fips))) {
  stop("NA values in geom_fips after FIPS remap.")
}

# 39. Download county geometries.
message("Downloading county polygons...")
counties_2024 <- tigris::counties(
  cb = TRUE,
  year = 2024,
  class = "sf"
) |>
  dplyr::select(
    area_fips = GEOID,
    state_fips = STATEFP,
    county_name = NAME,
    geometry
  )

ct_legacy_2020 <- tigris::counties(
  state = "CT",
  cb = TRUE,
  year = 2020,
  class = "sf"
) |>
  dplyr::select(
    area_fips = GEOID,
    state_fips = STATEFP,
    county_name = NAME,
    geometry
  ) |>
  dplyr::filter(
    area_fips %in% c(
      "09001", "09003", "09005", "09007",
      "09009", "09011", "09013", "09015"
    )
  )

counties_raw <- dplyr::bind_rows(
  counties_2024,
  ct_legacy_2020
) |>
  dplyr::filter(
    substr(area_fips, 1L, 2L) %in% conus_state_fips
  ) |>
  dplyr::distinct(area_fips, .keep_all = TRUE)

# 40. Project county geometries to a metric CRS.
counties_proj <- counties_raw |>
  sf::st_transform(5070)

# 41. Create representative county points.
county_pts <- counties_proj |>
  sf::st_point_on_surface() |>
  dplyr::mutate(
    x = sf::st_coordinates(geometry)[, 1],
    y = sf::st_coordinates(geometry)[, 2]
  ) |>
  sf::st_drop_geometry() |>
  dplyr::select(
    area_fips,
    x,
    y
  )

# 42. Audit FIPS-to-geometry coverage.
fips_no_geom <- krig_base |>
  dplyr::distinct(area_fips, geom_fips, area_title) |>
  dplyr::anti_join(
    counties_proj |>
      sf::st_drop_geometry() |>
      dplyr::transmute(geom_fips = area_fips),
    by = "geom_fips"
  ) |>
  dplyr::arrange(geom_fips, area_fips)

message(
  "FIPS in krig_base without county geometry: ",
  nrow(fips_no_geom)
)

if (nrow(fips_no_geom) > 0) {
  print(fips_no_geom, n = Inf)
  stop(
    "Some QCEW FIPS do not match the county geometry file. ",
    "Resolve these before modelling; do not silently drop them."
  )
}

# 43. Build full spatial panel.
krig_sf <- counties_proj |>
  dplyr::rename(geom_fips = area_fips) |>
  dplyr::inner_join(krig_base, by = "geom_fips") |>
  dplyr::left_join(
    county_pts |>
      dplyr::rename(geom_fips = area_fips),
    by = "geom_fips"
  ) |>
  dplyr::mutate(
    date = as.Date(paste0(
      year_id,
      "-",
      formatC((qtr_id - 1L) * 3L + 2L, width = 2, flag = "0"),
      "-15"
    ))
  ) |>
  sf::st_as_sf() |>
  dplyr::arrange(time_id, area_fips)

# 44. Validate spatial join.
if (any(is.na(krig_sf$x))) {
  stop(
    "Missing x coordinates for ",
    dplyr::n_distinct(krig_sf$area_fips[is.na(krig_sf$x)]),
    " counties."
  )
}

if (any(is.na(krig_sf$y))) {
  stop(
    "Missing y coordinates for ",
    dplyr::n_distinct(krig_sf$area_fips[is.na(krig_sf$y)]),
    " counties."
  )
}

if (any(is.na(krig_sf$date))) {
  stop("Missing quarterly date values.")
}

if (any(krig_sf$target_wage & krig_sf$real_zero)) {
  stop("A record is both target_wage and real_zero. Classification failed.")
}

if (any(krig_sf$obs_wage & krig_sf$real_zero)) {
  stop("A record is both obs_wage and real_zero. Classification failed.")
}

# 45. Create spatial panel table.
krig_xy <- krig_sf |>
  sf::st_drop_geometry() |>
  dplyr::select(
    area_fips,
    area_title,
    state_fips,
    county_name,
    year,
    qtr,
    year_id,
    qtr_id,
    time_id,
    date,
    x,
    y,
    disclosure_code,
    wk_wage_nominal,
    log_wage_nominal,
    wk_wage_real,
    log_wage_real,
    krig_value,
    gap_emp,
    gap_wage,
    gap_any,
    real_zero,
    obs_wage,
    target_wage,
    cpi_qtr,
    cpi_base_year,
    cpi_base,
    deflator_to_base
  ) |>
  dplyr::arrange(time_id, area_fips)

# 46. Split wage-record subsets.
krig_obs_sf <- krig_sf |>
  dplyr::filter(obs_wage) |>
  dplyr::arrange(time_id, area_fips)

krig_target_sf <- krig_sf |>
  dplyr::filter(target_wage) |>
  dplyr::arrange(time_id, area_fips)

krig_zero_sf <- krig_sf |>
  dplyr::filter(real_zero) |>
  dplyr::arrange(time_id, area_fips)

# 47. Build spatial BAUs.
BAUs_sf <- counties_proj |>
  dplyr::semi_join(
    krig_sf |>
      sf::st_drop_geometry() |>
      dplyr::distinct(geom_fips),
    by = c("area_fips" = "geom_fips")
  ) |>
  dplyr::left_join(county_pts, by = "area_fips") |>
  dplyr::mutate(
    fs = 1
  ) |>
  dplyr::arrange(area_fips)

BAUs_sp <- as(BAUs_sf, "Spatial")

# 48. Build spatio-temporal BAU grid.
BAU_times <- sort(unique(krig_sf$date))

BAU_data_ST <- tidyr::expand_grid(
  date = BAU_times,
  area_fips = BAUs_sf$area_fips
) |>
  dplyr::left_join(
    BAUs_sf |>
      sf::st_drop_geometry() |>
      dplyr::select(area_fips, x, y, fs),
    by = "area_fips"
  ) |>
  dplyr::arrange(date, area_fips)

if (nrow(BAU_data_ST) != nrow(BAUs_sp@data) * length(BAU_times)) {
  stop("BAU_data_ST does not match spatial BAUs × time periods.")
}

BAUs_ST <- spacetime::STFDF(
  sp = BAUs_sp,
  time = BAU_times,
  data = data.frame(
    st_row_id = seq_len(nrow(BAUs_sp@data) * length(BAU_times))
  )
)

# 49. Generate spatial basis functions.
basis_sp <- FRK::auto_basis(
  manifold = FRK::plane(),
  data = BAUs_sp,
  nres = 3,
  type = "bisquare",
  max_basis = 1500
)

# 50. Report spatial preparation.
message("=====================================================")
message("Spatial preparation complete.")
message("krig_sf rows: ", format(nrow(krig_sf), big.mark = ","))
message("krig_xy rows: ", format(nrow(krig_xy), big.mark = ","))
message("Observed rows: ", format(nrow(krig_obs_sf), big.mark = ","))
message("Target rows: ", format(nrow(krig_target_sf), big.mark = ","))
message("Real-zero rows: ", format(nrow(krig_zero_sf), big.mark = ","))
message("Spatial BAUs: ", format(nrow(BAUs_sp@data), big.mark = ","))
message("Time periods: ", length(BAU_times))
message("ST BAU rows: ", format(nrow(BAUs_ST@data), big.mark = ","))
message("Basis functions: ", FRK::nbasis(basis_sp))
message("CRS: EPSG:5070, units in metres")
message("Objects created:")
message("1. krig_sf")
message("2. krig_xy")
message("3. krig_obs_sf")
message("4. krig_target_sf")
message("5. krig_zero_sf")
message("6. BAUs_sp")
message("7. BAUs_ST")
message("8. basis_sp")
message("=====================================================")

# 51. Audit interpolation sample.
audit_interp <- tibble::tibble(
  scope = c(
    "Full analytical panel before CONUS geometry filter",
    "Final CONUS spatial panel used for kriging"
  ),
  rows = c(
    nrow(krig_dat),
    nrow(krig_sf)
  ),
  observed_rows = c(
    sum(krig_dat$obs_wage, na.rm = TRUE),
    nrow(krig_obs_sf)
  ),
  target_rows_to_interpolate = c(
    sum(krig_dat$target_wage, na.rm = TRUE),
    nrow(krig_target_sf)
  ),
  real_zero_rows_not_interpolated = c(
    sum(krig_dat$real_zero, na.rm = TRUE),
    nrow(krig_zero_sf)
  )
) |>
  dplyr::mutate(
    pct_observed = round(100 * observed_rows / rows, 2),
    pct_to_interpolate = round(100 * target_rows_to_interpolate / rows, 2),
    pct_real_zero_not_interpolated = round(
      100 * real_zero_rows_not_interpolated / rows,
      2
    ),
    row_check = observed_rows + target_rows_to_interpolate +
      real_zero_rows_not_interpolated
  )

print(audit_interp, width = Inf)

message("Final interpolation audit completed.")

# 52. Validate final consistency.
if (nrow(fips_no_geom) != 0) {
  stop("Some QCEW FIPS still do not have geometry.")
}

if (nrow(krig_sf) != nrow(krig_obs_sf) + nrow(krig_target_sf) + nrow(krig_zero_sf)) {
  stop("krig_sf does not partition exactly into observed, target, and real_zero records.")
}

if (any(krig_sf$target_wage & krig_sf$real_zero)) {
  stop("Some real-zero records are still classified as kriging targets.")
}

if (any(krig_sf$obs_wage & krig_sf$real_zero)) {
  stop("Some real-zero records are still classified as observed wages.")
}

if (nrow(BAUs_ST@data) != nrow(BAUs_sp@data) * length(BAU_times)) {
  stop("BAUs_ST does not equal spatial BAUs times time periods.")
}

if (!all(c("x", "y", "fs") %in% names(BAUs_sp@data))) {
  stop("BAUs_sp@data is missing required fields.")
}

message("Final audit checks passed.")

# 53. Fit FRK wage model.
{
  message("Step 53: fitting spatio-temporal FRK model...")
  
  pkgs_53 <- c("FRK", "sp", "spacetime", "sf", "dplyr", "tibble", "Matrix")
  miss_53 <- pkgs_53[
    !vapply(pkgs_53, requireNamespace, logical(1), quietly = TRUE)
  ]
  
  if (length(miss_53) > 0L) {
    stop("Missing packages required for Step 53: ", paste(miss_53, collapse = ", "))
  }

  frk_run_profile <- Sys.getenv("FRK_RUN_PROFILE", unset = "production")
  
  if (!frk_run_profile %in% c("production", "smoke")) {
    stop("FRK_RUN_PROFILE must be either 'production' or 'smoke'.")
  }
  
  frk_fit_method <- toupper(Sys.getenv("FRK_FIT_METHOD", unset = "TMB"))
  
  if (!frk_fit_method %in% c("TMB", "EM")) {
    stop("FRK_FIT_METHOD must be either 'TMB' or 'EM'.")
  }
  
  message(
    "To run a short diagnostic fit, set FRK_RUN_PROFILE='smoke' and FRK_FIT_METHOD='EM' before Step 53."
  )

  frk_spatial_nres <- if (frk_run_profile == "smoke") 1L else 2L
  frk_spatial_max_basis <- if (frk_run_profile == "smoke") 150L else 500L
  frk_temporal_n_basis <- if (frk_run_profile == "smoke") 5L else 7L
  frk_k_type <- if (frk_fit_method == "TMB") "precision" else "block-exponential"

  fit_sre <- function(model) {
    if (frk_fit_method == "TMB") {
      message("Using TMB; likelihood progress may not be printed during optimisation.")
      return(FRK::SRE.fit(model, method = "TMB"))
    }

    FRK::SRE.fit(
      model,
      n_EM = 100L,
      tol = 0.01,
      method = "EM",
      print_lik = TRUE
    )
  }

  message(
    "FRK run profile: ", frk_run_profile,
    " | method: ", frk_fit_method,
    " | K_type: ", frk_k_type,
    " | spatial nres/max_basis: ", frk_spatial_nres, "/", frk_spatial_max_basis,
    " | temporal bases: ", frk_temporal_n_basis
  )
  
  dup_geom_time <- krig_base |>
    dplyr::count(geom_fips, time_id, name = "n_dup") |>
    dplyr::filter(n_dup > 1L) |>
    dplyr::arrange(geom_fips, time_id)
  
  if (nrow(dup_geom_time) > 0L) {
    message(
      "Note: ",
      nrow(dup_geom_time),
      " duplicated geom_fips/time_id pairs found. ",
      "Observed duplicates will be averaged within BAU."
    )
  }
  
  BAU_times_posix <- as.POSIXct(BAU_times, tz = "UTC")
  
  if (length(BAU_times_posix) == 0L || any(is.na(BAU_times_posix))) {
    stop("BAU_times_posix is empty or contains NA values.")
  }
  
  bau_key <- BAUs_sp@data |>
    as.data.frame() |>
    tibble::as_tibble() |>
    dplyr::mutate(bau_sp_id = dplyr::row_number())
  
  required_bau_cols <- c("area_fips", "x", "y", "fs")
  missing_bau_cols <- setdiff(required_bau_cols, names(bau_key))
  
  if (length(missing_bau_cols) > 0L) {
    stop(
      "BAUs_sp@data is missing required columns: ",
      paste(missing_bau_cols, collapse = ", ")
    )
  }
  
  bau_key <- bau_key |>
    dplyr::select(bau_sp_id, area_fips, x, y, fs)
  
  if (any(is.na(bau_key$x)) || any(is.na(bau_key$y))) {
    stop("Missing x/y representative coordinates in bau_key.")
  }
  
  if (any(is.na(bau_key$fs)) || any(bau_key$fs < 0, na.rm = TRUE)) {
    stop("Invalid fs values in bau_key.")
  }
  
  n_sp <- nrow(bau_key)
  n_t <- length(BAU_times_posix)
  
  if (n_sp == 0L || n_t == 0L) {
    stop("No spatial or temporal BAUs found.")
  }
  
  BAUs_sp_FRK <- BAUs_sp
  sp::coordnames(BAUs_sp_FRK) <- c("x", "y")
  
  BAUs_sp_FRK@data <- data.frame(
    bau_sp_id = bau_key$bau_sp_id,
    area_fips = bau_key$area_fips,
    row.names = row.names(BAUs_sp@data)
  )
  
  BAU_data_ST <- tibble::tibble(
    n = seq_len(n_sp * n_t),
    t = rep(seq_len(n_t), each = n_sp),
    x = rep(bau_key$x, times = n_t),
    y = rep(bau_key$y, times = n_t),
    fs = rep(bau_key$fs, times = n_t)
  )
  
  BAUs_ST <- spacetime::STFDF(
    sp = BAUs_sp_FRK,
    time = BAU_times_posix,
    data = as.data.frame(BAU_data_ST)
  )
  
  stopifnot(all(c("n", "t", "x", "y", "fs") %in% names(BAUs_ST@data)))
  stopifnot(!any(names(BAUs_ST@data) %in% names(BAUs_ST@sp@data)))
  stopifnot(nrow(BAUs_ST@data) == n_sp * n_t)
  stopifnot(identical(sp::coordnames(BAUs_ST@sp), c("x", "y")))
  
  message(
    "BAUs_ST built: ",
    format(n_sp, big.mark = ","),
    " spatial BAUs x ",
    n_t,
    " time periods = ",
    format(nrow(BAUs_ST@data), big.mark = ","),
    " rows."
  )
  
  meas_err_frac <- 0.02
  
  wage_sd_obs <- sd(krig_xy$krig_value[krig_xy$obs_wage],na.rm = TRUE)
  
  if (is.na(wage_sd_obs) || wage_sd_obs <= 0) {stop("Invalid observed wage standard deviation.")}
  
  meas_err_sd <- wage_sd_obs * meas_err_frac
  
  if (is.na(meas_err_sd) || meas_err_sd <= 0) {
    stop("Invalid measurement-error standard deviation.")
  }
  
  
  
  obs_tab <- krig_xy |>
    dplyr::filter(obs_wage) |>
    dplyr::mutate(
      date_posix = as.POSIXct(date, tz = "UTC"),
      t = as.integer(match(date_posix, BAU_times_posix)),
      z = krig_value,
      std = meas_err_sd
    ) |>
    dplyr::group_by(date_posix, t, x, y) |>
    dplyr::summarise(
      z = mean(z, na.rm = TRUE),
      std = mean(std, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(t, x, y)
  
  if (nrow(obs_tab) == 0L) {
    stop("obs_tab has zero rows.")
  }
  
  if (any(is.na(obs_tab$t))) {
    stop("Some observed records do not match BAU_times_posix.")
  }
  
  if (any(is.na(obs_tab$x)) || any(is.na(obs_tab$y))) {
    stop("Missing observed x/y coordinates.")
  }
  
  if (any(is.na(obs_tab$z))) {
    stop("Missing observed kriging values in obs_tab.")
  }
  
  if (any(obs_tab$std < 0, na.rm = TRUE)) {
    stop("Negative measurement-error standard deviations in obs_tab.")
  }
  
  obs_pts <- sp::SpatialPoints(
    coords = as.matrix(obs_tab[, c("x", "y")]),
    proj4string = sp::CRS(SRS_string = sf::st_crs(5070)$wkt)
  )
  
  sp::coordnames(obs_pts) <- c("x", "y")
  
  obs_ST <- spacetime::STIDF(
    sp = obs_pts,
    time = obs_tab$date_posix,
    data = data.frame(
      z = obs_tab$z,
      std = obs_tab$std
    )
  )
  
  stopifnot(all(c("z", "std") %in% names(obs_ST@data)))
  stopifnot(!any(names(obs_ST@data) %in% names(BAUs_ST@data)))
  
  
  
  message("obs_ST rows: ", format(nrow(obs_ST@data), big.mark = ","))
  
  n_t_basis <- frk_temporal_n_basis
  
  temporal_scale <- max(
    1,
    ceiling((max(BAU_data_ST$t) - min(BAU_data_ST$t)) / (n_t_basis - 1L))
  )
  
  basis_sp_main <- FRK::auto_basis(
    manifold = FRK::plane(),
    data = BAUs_sp_FRK,
    nres = frk_spatial_nres,
    type = "bisquare",
    max_basis = frk_spatial_max_basis
  )
  
  
  basis_t <- FRK::local_basis(
    manifold = FRK::real_line(),
    loc = matrix(
      seq(min(BAU_data_ST$t), max(BAU_data_ST$t), length.out = n_t_basis),
      ncol = 1
    ),
    scale = rep(temporal_scale, n_t_basis),
    type = "bisquare"
  )
  
  S_t_bau <- FRK::eval_basis(
    basis_t,
    matrix(BAU_data_ST$t, ncol = 1)
  )
  
  S_t_obs <- FRK::eval_basis(
    basis_t,
    matrix(obs_tab$t, ncol = 1)
  )
  
  if (any(Matrix::rowSums(S_t_bau) == 0)) {
    stop("Some BAU time rows are not covered by the temporal basis.")
  }
  
  if (any(Matrix::rowSums(S_t_obs) == 0)) {
    stop("Some observed time rows are not covered by the temporal basis.")
  }
  
  basis_st <- FRK::TensorP(basis_sp_main, basis_t)
  
  if (FRK::nbasis(basis_st) > 4000L) {
    
    stop("Too many spatio-temporal basis functions: ", FRK::nbasis(basis_st))
  }
  
  S_bau_test <- FRK::eval_basis(basis_st, BAUs_ST)
  
  if (any(Matrix::rowSums(S_bau_test) == 0)) {
    stop("Some BAU rows are not covered by the spatio-temporal basis.")
  }
  
  rm(S_bau_test, S_t_bau, S_t_obs)
  
  message("Spatial basis functions : ", FRK::nbasis(basis_sp_main))
  message("Temporal basis functions: ", FRK::nbasis(basis_t))
  
  message("Spatio-temporal total   : ", FRK::nbasis(basis_st))
  message(
    "Temporal index scale      : ",
    min(BAU_data_ST$t),
    " to ",
    max(BAU_data_ST$t),
    " | basis scale: ",
    temporal_scale
  )
  
  message("Constructing SRE model.")
  
  set.seed(20260511)
  
  SRE_model <- FRK::SRE(
    f = z ~ 1,
    data = list(obs_ST),
    basis = basis_st,
    BAUs = BAUs_ST,
    est_error = FALSE,
    average_in_BAU = TRUE,
    K_type = frk_k_type,
    response = "gaussian"
  )
  
  message("Fitting SRE model with documented FRK defaults.")
  
  SRE_fit_main <- fit_sre(SRE_model)
  
  
  
  message("Step 53 complete. Object created: SRE_fit_main")
  
}

# 54. Predict suppressed wage values.
{
  message("Step 54: predicting over spatio-temporal BAUs...")
  
  pred_obj <- FRK::predict(SRE_fit_main,obs_fs = FALSE,type = c("link", "mean"))
  
  pred_BAUs_ST <- if (is.list(pred_obj) && "newdata" %in% names(pred_obj)) {
    pred_obj$newdata
  } else {
    pred_obj
  }
  
  pred_data <- pred_BAUs_ST@data |>
    tibble::as_tibble()
  
  message("Prediction columns: ", paste(names(pred_data), collapse = ", "))
  
  pred_link_col <- intersect(c("p_Y", "Y", "link", "mu", "mean", "pred", "prediction"),names(pred_data))[1]
  
  pred_mean_col <- intersect(c("p_mu", "mu", "mean", "pred", "prediction"),names(pred_data))[1]
  
  sd_link_col <- intersect(c("RMSPE_Y", "sd_Y", "se_Y", "sd", "se", "stderr", "std"),names(pred_data))[1]
  
  sd_mean_col <- intersect(c("RMSPE_mu", "sd_mu", "se_mu", "sd", "se", "stderr", "std"),names(pred_data))[1]
  
  if (is.na(pred_mean_col)) {stop("Could not identify mean-process prediction column. Inspect names(pred_BAUs_ST@data).")}
  
  get_st_time <- function(x) {
    time_raw <- tryCatch(
      time(x),
      error = function(e) NULL
    )
    
    if (is.null(time_raw)) {
      time_raw <- x@time
    }
    
    if (inherits(time_raw, c("xts", "zoo"))) {
      if (!requireNamespace("zoo", quietly = TRUE)) {
        stop("Package zoo is required to extract the prediction time index.")
      }
      
      time_raw <- zoo::index(time_raw)
    }
    
    if (inherits(time_raw, "POSIXt")) {
      return(as.POSIXct(time_raw, tz = "UTC"))
    }
    
    if (inherits(time_raw, "Date")) {
      return(as.POSIXct(time_raw, tz = "UTC"))
    }
    
    if (is.numeric(time_raw)) {
      return(as.POSIXct(time_raw, origin = "1970-01-01", tz = "UTC"))
    }
    
    out <- suppressWarnings(
      as.POSIXct(as.character(time_raw), tz = "UTC")
    )
    
    if (any(is.na(out))) {
      stop("Could not convert prediction time index to POSIXct.")
    }
    
    out
  }
  
  pred_dates <- get_st_time(pred_BAUs_ST)
  
  if (length(pred_dates) == 0L) {
    stop("Prediction time index has length zero.")
  }
  
  if (any(is.na(pred_dates))) {
    stop("Some extracted prediction dates are NA.")
  }
  
  n_sp_pred <- nrow(pred_BAUs_ST@sp@data)
  n_t_pred <- length(pred_dates)
  
  if (nrow(pred_data) != n_sp_pred * n_t_pred) {
    stop("Prediction data rows do not equal spatial BAUs times time periods.")
  }
  
  if ("area_fips" %in% names(pred_BAUs_ST@sp@data)) {
    pred_geom_fips <- as.character(pred_BAUs_ST@sp@data$area_fips)
  } else if (exists("bau_key") && "area_fips" %in% names(bau_key)) {
    pred_geom_fips <- as.character(bau_key$area_fips)
  } else if (exists("BAUs_sp") && "area_fips" %in% names(BAUs_sp@data)) {
    pred_geom_fips <- as.character(BAUs_sp@data$area_fips)
  } else {
    stop("Could not recover BAU area_fips / geom_fips key.")
  }
  
  if (length(pred_geom_fips) != n_sp_pred) {
    stop("BAU geom_fips key length does not match spatial BAUs.")
  }
  
  pred_n <- if ("n" %in% names(pred_data)) {
    as.integer(pred_data$n)
  } else {
    seq_len(nrow(pred_data))
  }
  
  if (any(is.na(pred_n)) || any(pred_n < 1L) || any(pred_n > n_sp_pred * n_t_pred)) {
    stop("Invalid prediction row index.")
  }
  
  pred_sp_id <- ((pred_n - 1L) %% n_sp_pred) + 1L
  pred_t_from_n <- ((pred_n - 1L) %/% n_sp_pred) + 1L
  
  pred_t <- if ("t" %in% names(pred_data)) {
    as.integer(pred_data$t)
  } else {
    pred_t_from_n
  }
  
  if (any(is.na(pred_t)) || any(pred_t < 1L) || any(pred_t > n_t_pred)) {
    stop("Invalid temporal index in prediction table.")
  }
  
  if ("t" %in% names(pred_data) && any(pred_t != pred_t_from_n)) {
    stop("Prediction temporal index does not match prediction row index.")
  }
  
  if (any(is.na(pred_sp_id)) || any(pred_sp_id < 1L) || any(pred_sp_id > n_sp_pred)) {
    stop("Invalid spatial index in prediction table.")
  }
  
  pred_key <- tibble::tibble(
    t = pred_t,
    date_posix = pred_dates[pred_t],
    date = as.Date(date_posix, tz = "UTC"),
    geom_fips = pred_geom_fips[pred_sp_id]
  )
  
  pred_values <- pred_data |>
    dplyr::select(
      -dplyr::any_of(c("n", "t", "x", "y", "fs", "wts"))
    )
  
  pred_bau_tbl <- dplyr::bind_cols(pred_key,pred_values) |>dplyr::transmute(geom_fips,date,t,pred_log_wage_real = if (!is.na(pred_link_col)) {.data[[pred_link_col]]} else {.data[[pred_mean_col]]},pred_log_wage_real_se = if (!is.na(sd_link_col)) {.data[[sd_link_col]]} else if (!is.na(sd_mean_col)) {.data[[sd_mean_col]]} else {NA_real_},pred_wk_wage_real = exp(pred_log_wage_real + dplyr::if_else(!is.na(pred_log_wage_real_se),0.5 * pred_log_wage_real_se^2,0)),pred_wk_wage_real_lo95 = dplyr::if_else(!is.na(pred_log_wage_real_se),exp(pred_log_wage_real - 1.96 * pred_log_wage_real_se),NA_real_),pred_wk_wage_real_hi95 = dplyr::if_else(!is.na(pred_log_wage_real_se),exp(pred_log_wage_real + 1.96 * pred_log_wage_real_se),NA_real_))
  
  pred_dups <- pred_bau_tbl |>
    dplyr::count(geom_fips, date, name = "n") |>
    dplyr::filter(n > 1L)
  
  if (nrow(pred_dups) > 0L) {
    stop("Duplicate prediction keys detected.")
  }
  
  target_imputed <- krig_sf |>sf::st_drop_geometry() |>dplyr::filter(target_wage) |>dplyr::mutate(geom_fips = as.character(geom_fips),date = as.Date(date)) |>dplyr::left_join(pred_bau_tbl,by = c("geom_fips", "date")) |>dplyr::mutate(log_wage_real_imputed = pred_log_wage_real,wk_wage_real_imputed = pred_wk_wage_real,wk_wage_nominal_imputed = wk_wage_real_imputed / deflator_to_base,wk_wage_real_imputed_lo95 = pred_wk_wage_real_lo95,wk_wage_real_imputed_hi95 = pred_wk_wage_real_hi95)
  
  if (nrow(target_imputed) != nrow(krig_target_sf)) {
    stop("target_imputed row count does not match krig_target_sf.")
  }
  
  if (any(is.na(target_imputed$log_wage_real_imputed))) {
    n_miss <- sum(is.na(target_imputed$log_wage_real_imputed))
    stop(n_miss, " target rows are missing FRK predictions.")
  }
  
  krig_xy_completed <- krig_sf |>sf::st_drop_geometry() |>dplyr::mutate(geom_fips = as.character(geom_fips),date = as.Date(date)) |>dplyr::left_join(pred_bau_tbl,by = c("geom_fips", "date")) |>dplyr::mutate(imputed_by_frk = target_wage,log_wage_real_completed = dplyr::case_when(obs_wage ~ log_wage_real,target_wage ~ pred_log_wage_real,real_zero ~ NA_real_,TRUE ~ NA_real_),wk_wage_real_completed = dplyr::case_when(obs_wage ~ wk_wage_real,target_wage ~ pred_wk_wage_real,real_zero ~ 0,TRUE ~ NA_real_),wk_wage_nominal_completed = dplyr::case_when(obs_wage ~ wk_wage_nominal,target_wage ~ pred_wk_wage_real / deflator_to_base,real_zero ~ 0,TRUE ~ NA_real_))
  
  imputation_audit <- tibble::tibble(
    rows_completed = nrow(krig_xy_completed),
    observed_rows = sum(krig_xy_completed$obs_wage, na.rm = TRUE),
    target_rows_imputed = sum(krig_xy_completed$target_wage, na.rm = TRUE),
    real_zero_rows = sum(krig_xy_completed$real_zero, na.rm = TRUE),
    missing_completed_targets = sum(
      krig_xy_completed$target_wage &
        is.na(krig_xy_completed$log_wage_real_completed),
      na.rm = TRUE
    )
  )
  
  print(imputation_audit, width = Inf)
  
  message("Step 54 complete.")
  message("Objects created:")
  message("1. pred_BAUs_ST")
  message("2. pred_bau_tbl")
  message("3. target_imputed")
  message("4. krig_xy_completed")
}

# 55. Validate holdout predictions.
{
  message("Step 55: validating FRK with observed-wage holdout...")
  
  
  pkgs_55 <- c("FRK", "sp", "spacetime", "sf", "dplyr", "tibble", "Matrix")
  miss_55 <- pkgs_55[
    !vapply(pkgs_55, requireNamespace, logical(1), quietly = TRUE)
  ]
  
  if (length(miss_55) > 0L) {
    stop("Missing packages required for Step 55: ", paste(miss_55, collapse = ", "))
  }
  
  set.seed(20260511)
  
  holdout_frac <- 0.05
  holdout_max <- 20000L
  
  
  obs_validation_frame <- krig_sf |>
    sf::st_drop_geometry() |>
    dplyr::filter(obs_wage, !is.na(krig_value)) |>
    dplyr::mutate(
      geom_fips = as.character(geom_fips),
      date = as.Date(date)
    ) |>
    dplyr::arrange(time_id, area_fips)
  
  if (nrow(obs_validation_frame) == 0L) {
    stop("No observed wage records available for validation.")
  }
  
  holdout_keys <- obs_validation_frame |>
    dplyr::group_by(year, qtr) |>
    dplyr::slice_sample(prop = holdout_frac) |>
    dplyr::ungroup()
  
  if (nrow(holdout_keys) > holdout_max) {
    holdout_keys <- holdout_keys |>
      dplyr::slice_sample(n = holdout_max)
  }
  
  holdout_keys <- holdout_keys |>
    dplyr::select(area_fips, geom_fips, date, year, qtr, time_id)
  
  if (nrow(holdout_keys) == 0L) {
    stop("Holdout sample has zero rows.")
  }
  
  message(
    "Holdout records: ",
    format(nrow(holdout_keys), big.mark = ","),
    " from ",
    format(nrow(obs_validation_frame), big.mark = ","),
    " observed records."
  )
  
  krig_xy_val <- krig_sf |>
    sf::st_drop_geometry() |>
    dplyr::mutate(
      geom_fips = as.character(geom_fips),
      date = as.Date(date)
    ) |>
    dplyr::left_join(
      holdout_keys |>
        dplyr::mutate(frk_holdout = TRUE) |>
        dplyr::select(area_fips, geom_fips, date, frk_holdout),
      by = c("area_fips", "geom_fips", "date")
    ) |>
    dplyr::mutate(
      frk_holdout = dplyr::coalesce(frk_holdout, FALSE),
      obs_wage_train = obs_wage & !frk_holdout
    )
  
  if (sum(krig_xy_val$obs_wage_train, na.rm = TRUE) == 0L) {
    stop("No training observations remain after holdout.")
  }
  
  BAU_times_posix_val <- as.POSIXct(BAU_times, tz = "UTC")
  
  if (length(BAU_times_posix_val) == 0L || any(is.na(BAU_times_posix_val))) {
    stop("BAU_times_posix_val is empty or contains NA values.")
  }
  
  bau_key_val <- BAUs_sp@data |>
    as.data.frame() |>
    tibble::as_tibble() |>
    dplyr::mutate(bau_sp_id = dplyr::row_number())
  
  required_bau_cols_val <- c("area_fips", "x", "y", "fs")
  missing_bau_cols_val <- setdiff(required_bau_cols_val, names(bau_key_val))
  
  if (length(missing_bau_cols_val) > 0L) {
    stop(
      "BAUs_sp@data is missing required columns: ",
      paste(missing_bau_cols_val, collapse = ", ")
    )
  }
  
  bau_key_val <- bau_key_val |>
    dplyr::select(bau_sp_id, area_fips, x, y, fs)
  
  if (any(is.na(bau_key_val$x)) || any(is.na(bau_key_val$y))) {
    stop("Missing x/y representative coordinates in bau_key_val.")
  }
  
  if (any(is.na(bau_key_val$fs)) || any(bau_key_val$fs < 0, na.rm = TRUE)) {
    stop("Invalid fs values in bau_key_val.")
  }
  
  n_sp_val <- nrow(bau_key_val)
  n_t_val <- length(BAU_times_posix_val)
  
  if (n_sp_val == 0L || n_t_val == 0L) {
    stop("No spatial or temporal BAUs found for validation.")
  }
  
  BAUs_sp_val <- BAUs_sp
  sp::coordnames(BAUs_sp_val) <- c("x", "y")
  
  BAUs_sp_val@data <- data.frame(
    bau_sp_id = bau_key_val$bau_sp_id,
    area_fips = bau_key_val$area_fips,
    row.names = row.names(BAUs_sp@data)
  )
  
  BAU_data_ST_val <- tibble::tibble(
    n = seq_len(n_sp_val * n_t_val),
    t = rep(seq_len(n_t_val), each = n_sp_val),
    x = rep(bau_key_val$x, times = n_t_val),
    y = rep(bau_key_val$y, times = n_t_val),
    fs = rep(bau_key_val$fs, times = n_t_val)
  )
  
  BAUs_ST_val <- spacetime::STFDF(
    sp = BAUs_sp_val,
    time = BAU_times_posix_val,
    data = as.data.frame(BAU_data_ST_val)
  )
  
  stopifnot(all(c("n", "t", "x", "y", "fs") %in% names(BAUs_ST_val@data)))
  stopifnot(!any(names(BAUs_ST_val@data) %in% names(BAUs_ST_val@sp@data)))
  stopifnot(nrow(BAUs_ST_val@data) == n_sp_val * n_t_val)
  stopifnot(identical(sp::coordnames(BAUs_ST_val@sp), c("x", "y")))
  
  wage_sd_obs_val <- stats::sd(krig_xy_val$krig_value[krig_xy_val$obs_wage_train],na.rm = TRUE)
  
  if (is.na(wage_sd_obs_val) || wage_sd_obs_val <= 0) {stop("Invalid observed wage standard deviation for validation.")}
  
  meas_err_sd_val <- wage_sd_obs_val * meas_err_frac
  
  
  obs_tab_val <- krig_xy_val |>
    dplyr::filter(obs_wage_train) |>
    dplyr::mutate(
      date_posix = as.POSIXct(date, tz = "UTC"),
      t = as.integer(match(date_posix, BAU_times_posix_val)),
      z = krig_value,
      std = meas_err_sd_val
    ) |>
    dplyr::group_by(date_posix, t, x, y) |>
    dplyr::summarise(
      z = mean(z, na.rm = TRUE),
      std = mean(std, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(t, x, y)
  
  if (nrow(obs_tab_val) == 0L) {
    stop("obs_tab_val has zero rows.")
  }
  
  if (any(is.na(obs_tab_val$t))) {
    stop("Some validation training records do not match BAU_times.")
  }
  
  if (any(is.na(obs_tab_val$x)) || any(is.na(obs_tab_val$y))) {
    stop("Missing observed x/y coordinates in obs_tab_val.")
  }
  
  if (any(is.na(obs_tab_val$z))) {
    stop("Missing observed kriging values in obs_tab_val.")
  }
  
  if (any(obs_tab_val$std < 0, na.rm = TRUE)) {
    stop("Negative measurement-error standard deviations in obs_tab_val.")
  }
  
  obs_pts_val <- sp::SpatialPoints(
    coords = as.matrix(obs_tab_val[, c("x", "y")]),
    proj4string = sp::CRS(SRS_string = sf::st_crs(5070)$wkt)
  )
  
  sp::coordnames(obs_pts_val) <- c("x", "y")
  
  obs_ST_val <- spacetime::STIDF(
    sp = obs_pts_val,
    time = obs_tab_val$date_posix,
    data = data.frame(
      z = obs_tab_val$z,
      std = obs_tab_val$std
    )
  )
  
  stopifnot(all(c("z", "std") %in% names(obs_ST_val@data)))
  stopifnot(!any(names(obs_ST_val@data) %in% names(BAUs_ST_val@data)))
  
  
  
  message("obs_ST_val rows: ", format(nrow(obs_ST_val@data), big.mark = ","))
  
  n_t_basis_val <- frk_temporal_n_basis
  
  
  temporal_scale_val <- max(
    1,
    ceiling((max(BAU_data_ST_val$t) - min(BAU_data_ST_val$t)) / (n_t_basis_val - 1L))
  )
  
  basis_sp_val <- FRK::auto_basis(
    manifold = FRK::plane(),
    data = BAUs_sp_val,
    nres = frk_spatial_nres,
    type = "bisquare",
    max_basis = frk_spatial_max_basis
  )
  
  basis_t_val <- FRK::local_basis(
    manifold = FRK::real_line(),
    loc = matrix(
      seq(min(BAU_data_ST_val$t), max(BAU_data_ST_val$t), length.out = n_t_basis_val),
      ncol = 1
    ),
    scale = rep(temporal_scale_val, n_t_basis_val),
    type = "bisquare"
  )
  
  S_t_bau_val <- FRK::eval_basis(
    basis_t_val,
    matrix(BAU_data_ST_val$t, ncol = 1)
  )
  
  S_t_obs_val <- FRK::eval_basis(
    basis_t_val,
    matrix(obs_tab_val$t, ncol = 1)
  )
  
  if (any(Matrix::rowSums(S_t_bau_val) == 0)) {
    stop("Some validation BAU time rows are not covered by the temporal basis.")
  }
  
  if (any(Matrix::rowSums(S_t_obs_val) == 0)) {
    stop("Some validation observed time rows are not covered by the temporal basis.")
  }
  
  basis_st_val <- FRK::TensorP(basis_sp_val, basis_t_val)
  
  if (FRK::nbasis(basis_st_val) > 4000L) {
    stop("Too many validation spatio-temporal basis functions: ", FRK::nbasis(basis_st_val))
  }
  
  S_bau_test_val <- FRK::eval_basis(basis_st_val, BAUs_ST_val)
  
  if (any(Matrix::rowSums(S_bau_test_val) == 0)) {
    stop("Some validation BAU rows are not covered by the spatio-temporal basis.")
  }
  
  rm(S_bau_test_val, S_t_bau_val, S_t_obs_val)
  
  message("Validation spatial basis functions : ", FRK::nbasis(basis_sp_val))
  message("Validation temporal basis functions: ", FRK::nbasis(basis_t_val))
  message("Validation total basis functions   : ", FRK::nbasis(basis_st_val))
  message(
    "Validation temporal index scale      : ",
    min(BAU_data_ST_val$t),
    " to ",
    max(BAU_data_ST_val$t),
    " | basis scale: ",
    temporal_scale_val
  )
  
  SRE_model_val <- FRK::SRE(f = z ~ 1,data = list(obs_ST_val),basis = basis_st_val,BAUs = BAUs_ST_val,est_error = FALSE,average_in_BAU = TRUE,K_type = frk_k_type,response = "gaussian")
  
  SRE_fit_val <- fit_sre(SRE_model_val)
  
  
  pred_obj_val <- FRK::predict(SRE_fit_val,obs_fs = FALSE,type = c("link", "mean", "response"))
  
  pred_BAUs_ST_val <- if (is.list(pred_obj_val) && "newdata" %in% names(pred_obj_val)) {
    pred_obj_val$newdata
  } else {
    pred_obj_val
  }
  
  pred_data_val <- pred_BAUs_ST_val@data |>
    tibble::as_tibble()
  
  message("Validation prediction columns: ", paste(names(pred_data_val), collapse = ", "))
  
  pred_link_col_val <- intersect(c("p_Y", "Y", "link", "mu", "mean", "pred", "prediction"), names(pred_data_val))[1]
  
  pred_mean_col_val <- intersect(c("p_mu", "mu", "mean", "pred", "prediction"), names(pred_data_val))[1]
  
  pred_response_col_val <- intersect(c("p_Z", "Z", "response"), names(pred_data_val))[1]
  
  sd_link_col_val <- intersect(c("RMSPE_Y", "sd_Y", "se_Y", "sd", "se", "stderr", "std"), names(pred_data_val))[1]
  
  sd_mean_col_val <- intersect(c("RMSPE_mu", "sd_mu", "se_mu", "sd", "se", "stderr", "std"), names(pred_data_val))[1]
  
  sd_response_col_val <- intersect(c("RMSPE_Z", "sd_Z", "se_Z"), names(pred_data_val))[1]
  
  if (is.na(pred_mean_col_val)) {stop("Could not identify validation mean-process prediction column.")}
  
  if (is.na(pred_response_col_val)) {pred_response_col_val <- pred_mean_col_val}
  
  if (is.na(sd_response_col_val)) {sd_response_col_val <- sd_mean_col_val}
  
  if (is.na(sd_response_col_val)) {warning("Could not identify validation response uncertainty column.")}
  
  n_sp_pred_val <- nrow(pred_BAUs_ST_val@sp@data)
  n_t_pred_val <- length(BAU_times_posix_val)
  
  if (nrow(pred_data_val) != n_sp_pred_val * n_t_pred_val) {
    stop("Validation prediction rows do not equal spatial BAUs times time periods.")
  }
  
  pred_geom_fips_val <- as.character(pred_BAUs_ST_val@sp@data$area_fips)
  
  if (length(pred_geom_fips_val) != n_sp_pred_val) {
    stop("Validation BAU geom_fips key length does not match spatial BAUs.")
  }
  
  pred_n_val <- if ("n" %in% names(pred_data_val)) {
    as.integer(pred_data_val$n)
  } else {
    seq_len(nrow(pred_data_val))
  }
  
  pred_sp_id_val <- ((pred_n_val - 1L) %% n_sp_pred_val) + 1L
  pred_t_from_n_val <- ((pred_n_val - 1L) %/% n_sp_pred_val) + 1L
  
  pred_t_val <- if ("t" %in% names(pred_data_val)) {
    as.integer(pred_data_val$t)
  } else {
    pred_t_from_n_val
  }
  
  pred_bau_tbl_val <- dplyr::bind_cols(tibble::tibble(t = pred_t_val,date = as.Date(BAU_times_posix_val[pred_t_val], tz = "UTC"),geom_fips = pred_geom_fips_val[pred_sp_id_val]),pred_data_val |>dplyr::select(-dplyr::any_of(c("n", "t", "x", "y", "fs", "wts")))) |>dplyr::transmute(geom_fips,date,t,pred_log_wage_real = if (!is.na(pred_link_col_val)) {.data[[pred_link_col_val]]} else {.data[[pred_mean_col_val]]},pred_log_wage_real_se = if (!is.na(sd_link_col_val)) {.data[[sd_link_col_val]]} else if (!is.na(sd_mean_col_val)) {.data[[sd_mean_col_val]]} else {NA_real_},pred_wk_wage_real = exp(pred_log_wage_real + dplyr::if_else(!is.na(pred_log_wage_real_se),0.5 * pred_log_wage_real_se^2,0)))
  
  pred_dups_val <- pred_bau_tbl_val |>
    dplyr::count(geom_fips, date, name = "n") |>
    dplyr::filter(n > 1L)
  
  if (nrow(pred_dups_val) > 0L) {
    stop("Duplicate validation prediction keys detected.")
  }
  
  validation_holdout <- krig_xy_val |>dplyr::filter(frk_holdout) |>dplyr::select(area_fips,geom_fips,area_title,year,qtr,time_id,date,wk_wage_real,log_wage_real,wk_wage_nominal,deflator_to_base) |>dplyr::left_join(pred_bau_tbl_val,by = c("geom_fips", "date")) |>dplyr::mutate(pred_wk_wage_nominal = pred_wk_wage_real / deflator_to_base,err_log = pred_log_wage_real - log_wage_real,abs_err_log = abs(err_log),sq_err_log = err_log^2,err_wage_real = pred_wk_wage_real - wk_wage_real,abs_pct_err_wage_real = abs(err_wage_real) / wk_wage_real,pred_log_se_total = dplyr::if_else(!is.na(pred_log_wage_real_se),sqrt(pred_log_wage_real_se^2 + meas_err_sd_val^2),NA_real_),covered_95 = dplyr::if_else(!is.na(pred_log_se_total),log_wage_real >= pred_log_wage_real - 1.96 * pred_log_se_total & log_wage_real <= pred_log_wage_real + 1.96 * pred_log_se_total,NA))
  
  
  if (nrow(validation_holdout) != nrow(holdout_keys)) {
    stop("validation_holdout row count does not match holdout_keys.")
  }
  
  if (any(is.na(validation_holdout$pred_log_wage_real))) {
    stop(
      sum(is.na(validation_holdout$pred_log_wage_real)),
      " validation holdout records are missing predictions."
    )
  }
  
  validation_audit <- validation_holdout |>
    dplyr::summarise(
      holdout_rows = dplyr::n(),
      rmse_log = sqrt(mean(sq_err_log, na.rm = TRUE)),
      mae_log = mean(abs_err_log, na.rm = TRUE),
      bias_log = mean(err_log, na.rm = TRUE),
      cor_log = cor(pred_log_wage_real, log_wage_real, use = "complete.obs"),
      rmse_wage_real = sqrt(mean(err_wage_real^2, na.rm = TRUE)),
      median_abs_pct_error = round(100 * stats::median(abs_pct_err_wage_real, na.rm = TRUE), 2),
      coverage_raw = mean(covered_95, na.rm = TRUE),
      coverage_95 = ifelse(is.nan(coverage_raw), NA_real_, round(100 * coverage_raw, 2))
    ) |>
    dplyr::select(-coverage_raw)
  
  
  validation_by_year <- validation_holdout |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      holdout_rows = dplyr::n(),
      rmse_log = sqrt(mean(sq_err_log, na.rm = TRUE)),
      mae_log = mean(abs_err_log, na.rm = TRUE),
      bias_log = mean(err_log, na.rm = TRUE),
      cor_log = cor(pred_log_wage_real, log_wage_real, use = "complete.obs"),
      rmse_wage_real = sqrt(mean(err_wage_real^2, na.rm = TRUE)),
      median_abs_pct_error = round(100 * stats::median(abs_pct_err_wage_real, na.rm = TRUE), 2),
      coverage_raw = mean(covered_95, na.rm = TRUE),
      coverage_95 = ifelse(is.nan(coverage_raw), NA_real_, round(100 * coverage_raw, 2)),
      .groups = "drop"
    ) |>
    dplyr::select(-coverage_raw) |>
    dplyr::arrange(year)
  
  
  validation_by_qtr <- validation_holdout |>
    dplyr::group_by(qtr) |>
    dplyr::summarise(
      holdout_rows = dplyr::n(),
      rmse_log = sqrt(mean(sq_err_log, na.rm = TRUE)),
      mae_log = mean(abs_err_log, na.rm = TRUE),
      bias_log = mean(err_log, na.rm = TRUE),
      cor_log = cor(pred_log_wage_real, log_wage_real, use = "complete.obs"),
      rmse_wage_real = sqrt(mean(err_wage_real^2, na.rm = TRUE)),
      median_abs_pct_error = round(100 * stats::median(abs_pct_err_wage_real, na.rm = TRUE), 2),
      coverage_raw = mean(covered_95, na.rm = TRUE),
      coverage_95 = ifelse(is.nan(coverage_raw), NA_real_, round(100 * coverage_raw, 2)),
      .groups = "drop"
    ) |>
    dplyr::select(-coverage_raw) |>
    dplyr::arrange(qtr)
  
  
  print_width_55 <- suppressWarnings(as.integer(getOption("width", 120L)))
  
  if (length(print_width_55) != 1L || is.na(print_width_55) || print_width_55 < 1L) {
    print_width_55 <- 120L
  }
  
  print_width_55 <- min(max(print_width_55, 120L), 1000L)
  
  print(validation_audit, width = print_width_55)
  print(validation_by_year, n = nrow(validation_by_year), width = print_width_55)
  print(validation_by_qtr, n = nrow(validation_by_qtr), width = print_width_55)
  
  message("Step 55 complete.")
  message("Objects created:")
  message("1. holdout_keys")
  message("2. krig_xy_val")
  message("3. BAUs_ST_val")
  message("4. obs_ST_val")
  message("5. SRE_fit_val")
  message("6. pred_BAUs_ST_val")
  message("7. pred_bau_tbl_val")
  message("8. validation_holdout")
  message("9. validation_audit")
  message("10. validation_by_year")
  message("11. validation_by_qtr")
  
}

# 56. Check optimizer status.
{
  message("Step 56: verifying optimizer status without refitting...")
  
  scalar_text_56 <- function(x) {
    if (is.null(x)) {
      return("NULL")
    }
    
    if (is.atomic(x) && length(x) == 1L) {
      return(as.character(x))
    }
    
    if (is.atomic(x) && length(x) > 1L && length(x) <= 10L) {
      return(paste(as.character(x), collapse = ", "))
    }
    
    paste0("<", paste(class(x), collapse = "/"), "; length=", length(x), ">")
  }
  
  collect_fit_fields_56 <- function(x, path = "object", depth = 0L, max_depth = 8L) {
    out <- data.frame(
      path = character(),
      name = character(),
      class = character(),
      value = character(),
      stringsAsFactors = FALSE
    )
    
    if (depth > max_depth) {
      return(out)
    }
    
    key_pattern <- "converg|message|optim|nlminb|objective|loglik|likelihood|gradient|hessian|pdHess|fn|gr|value|counts|evaluations"
    
    add_row <- function(path_i, name_i, obj_i) {
      data.frame(
        path = path_i,
        name = name_i,
        class = paste(class(obj_i), collapse = "/"),
        value = scalar_text_56(obj_i),
        stringsAsFactors = FALSE
      )
    }
    
    if (isS4(x)) {
      slot_names <- methods::slotNames(x)
      
      for (sn in slot_names) {
        val <- tryCatch(
          methods::slot(x, sn),
          error = function(e) NULL
        )
        
        new_path <- paste0(path, "@", sn)
        
        if (grepl(key_pattern, sn, ignore.case = TRUE)) {
          out <- rbind(out, add_row(new_path, sn, val))
        }
        
        out <- rbind(
          out,
          collect_fit_fields_56(
            val,
            path = new_path,
            depth = depth + 1L,
            max_depth = max_depth
          )
        )
      }
    } else if (is.list(x)) {
      nm <- names(x)
      
      if (is.null(nm)) {
        nm <- paste0("[[", seq_along(x), "]]")
      }
      
      for (i in seq_along(x)) {
        name_i <- nm[i]
        val <- x[[i]]
        new_path <- paste0(path, "$", name_i)
        
        if (grepl(key_pattern, name_i, ignore.case = TRUE)) {
          out <- rbind(out, add_row(new_path, name_i, val))
        }
        
        out <- rbind(
          out,
          collect_fit_fields_56(
            val,
            path = new_path,
            depth = depth + 1L,
            max_depth = max_depth
          )
        )
      }
    } else if (is.environment(x)) {
      nm <- ls(x, all.names = TRUE)
      
      for (name_i in nm) {
        val <- tryCatch(
          get(name_i, envir = x, inherits = FALSE),
          error = function(e) NULL
        )
        
        new_path <- paste0(path, "$", name_i)
        
        if (grepl(key_pattern, name_i, ignore.case = TRUE)) {
          out <- rbind(out, add_row(new_path, name_i, val))
        }
        
        out <- rbind(
          out,
          collect_fit_fields_56(
            val,
            path = new_path,
            depth = depth + 1L,
            max_depth = max_depth
          )
        )
      }
    }
    
    out
  }
  
  report_fit_56 <- function(object_name) {
    message("")
    message("=====================================================")
    message("Optimizer diagnostic for: ", object_name)
    message("=====================================================")
    
    if (!exists(object_name, envir = .GlobalEnv)) {
      warning("Object not found in memory: ", object_name)
      return(invisible(NULL))
    }
    
    fit_obj <- get(object_name, envir = .GlobalEnv)
    
    message("Class: ", paste(class(fit_obj), collapse = ", "))
    
    if (isS4(fit_obj)) {
      message("Slots: ", paste(methods::slotNames(fit_obj), collapse = ", "))
    } else {
      message("Object is not S4.")
    }
    
    info_obj <- tryCatch(
      FRK::info_fit(fit_obj),
      error = function(e) e
    )
    
    message("")
    message("FRK::info_fit output:")
    print(info_obj)
    
    loglik_obj <- tryCatch(
      stats::logLik(fit_obj),
      error = function(e) e
    )
    
    message("")
    message("stats::logLik output:")
    print(loglik_obj)
    
    diag_tbl <- collect_fit_fields_56(
      fit_obj,
      path = object_name,
      depth = 0L,
      max_depth = 8L
    )
    
    diag_tbl <- unique(diag_tbl)
    
    message("")
    message("Detected optimizer-related fields:")
    
    if (nrow(diag_tbl) == 0L) {
      message("No optimizer-related fields were detected inside this object.")
    } else {
      print(diag_tbl, row.names = FALSE)
    }
    
    conv_tbl <- diag_tbl[
      grepl("converg", diag_tbl$name, ignore.case = TRUE) |
        grepl("converg", diag_tbl$path, ignore.case = TRUE),
      ,
      drop = FALSE
    ]
    
    conv_num <- suppressWarnings(as.numeric(conv_tbl$value))
    conv_num <- conv_num[!is.na(conv_num)]
    
    message("")
    message("Convergence decision:")
    
    if (length(conv_num) == 0L) {
      message("FORMAL STATUS: NOT EXPOSED")
      message("No numeric convergence code was found inside the printed object structure.")
      message("Interpretation: the model fitted, predicted, and validated, but this object printout does not expose the optimizer convergence code.")
    } else if (any(conv_num == 0) && !any(conv_num != 0)) {
      message("FORMAL STATUS: CONVERGENCE CONFIRMED")
      message("Detected convergence code(s): ", paste(unique(conv_num), collapse = ", "))
      message("Interpretation: convergence code 0 was found.")
    } else if (any(conv_num == 0) && any(conv_num != 0)) {
      warning("FORMAL STATUS: MIXED CONVERGENCE CODES. Detected: ", paste(unique(conv_num), collapse = ", "))
    } else {
      warning("FORMAL STATUS: NONZERO CONVERGENCE CODE(S). Detected: ", paste(unique(conv_num), collapse = ", "))
    }
    
    invisible(
      list(
        object_name = object_name,
        class = class(fit_obj),
        info_fit = info_obj,
        logLik = loglik_obj,
        optimizer_fields = diag_tbl,
        convergence_fields = conv_tbl,
        convergence_codes = conv_num
      )
    )
  }
  
  frk_optimizer_diagnostic_main <- report_fit_56("SRE_fit_main")
  frk_optimizer_diagnostic_val <- report_fit_56("SRE_fit_val")
  
  message("")
  message("Step 56 complete.")
  message("Objects created:")
  message("1. frk_optimizer_diagnostic_main")
  message("2. frk_optimizer_diagnostic_val")
}

# ==============================================================================
# 57. Export Processed Objects and Models to '3_Outputs'
# ==============================================================================

{
  message("Step 57: exporting essential objects to '3_Outputs'.")
  
  pkgs_57 <- c("here", "fs", "purrr", "dplyr", "tibble", "readr")
  
  miss_57 <- pkgs_57[
    !vapply(pkgs_57, requireNamespace, logical(1), quietly = TRUE)
  ]
  
  if (length(miss_57) > 0L) {
    install.packages(miss_57, repos = "https://cloud.r-project.org")
  }
  
  suppressPackageStartupMessages(
    invisible(lapply(pkgs_57, library, character.only = TRUE))
  )
  
  # ---------------------------------------------------------------------------
  # 57.1 Output directory structure
  # ---------------------------------------------------------------------------
  
  out_base   <- here::here("3_Outputs")
  out_data   <- fs::path(out_base, "1_Data_Processed")
  out_models <- fs::path(out_base, "2_Models")
  out_figs   <- fs::path(out_base, "3_Figures")
  out_tabs   <- fs::path(out_base, "4_Tables")
  out_logs   <- fs::path(out_data, "Run_Logs")
  
  fs::dir_create(
    c(out_data, out_models, out_figs, out_tabs, out_logs),
    recurse = TRUE
  )
  
  # ---------------------------------------------------------------------------
  # 57.2 Safe object writer
  # ---------------------------------------------------------------------------
  
  save_object_rds <- function(obj_name, folder, compress = "xz") {
    if (!exists(obj_name, envir = .GlobalEnv)) {
      warning("Object not found and skipped: ", obj_name)
      
      return(
        tibble::tibble(
          object = obj_name,
          saved = FALSE,
          path = NA_character_,
          class = NA_character_,
          rows = NA_integer_,
          columns = NA_integer_,
          size_mb = NA_real_
        )
      )
    }
    
    obj <- get(obj_name, envir = .GlobalEnv)
    file_path <- fs::path(folder, paste0(obj_name, ".rds"))
    
    saveRDS(obj, file = file_path, compress = compress)
    
    tibble::tibble(
      object = obj_name,
      saved = TRUE,
      path = as.character(file_path),
      class = paste(class(obj), collapse = "; "),
      rows = if (is.data.frame(obj)) nrow(obj) else NA_integer_,
      columns = if (is.data.frame(obj)) ncol(obj) else NA_integer_,
      size_mb = as.numeric(object.size(obj)) / 1024^2
    )
  }
  
  # ---------------------------------------------------------------------------
  # 57.3 Objects to preserve
  # ---------------------------------------------------------------------------
  
  data_objects <- c(
    "panel_cty_qtr",
    "panel_num",
    "krig_dat",
    "krig_xy",
    "krig_xy_completed",
    "target_imputed",
    "audit_cty_qtr",
    "supp_ann",
    "supp_rate",
    "gaps_ann",
    "mean_cty_qtr",
    "cpi_qtr",
    "cpi_monthly",
    "audit_interp",
    "deflator_audit",
    "imputation_audit",
    "holdout_keys",
    "krig_xy_val",
    "validation_holdout",
    "validation_audit",
    "validation_by_year",
    "validation_by_qtr"
  )
  
  model_objects <- c(
    "SRE_fit_main",
    "SRE_fit_val",
    "basis_sp",
    "basis_sp_main",
    "basis_t",
    "basis_st",
    "BAUs_sp",
    "BAUs_ST",
    "BAUs_ST_val",
    "obs_ST",
    "obs_ST_val",
    "pred_BAUs_ST",
    "pred_BAUs_ST_val",
    "pred_bau_tbl",
    "pred_bau_tbl_val",
    "counties_proj",
    "krig_sf",
    "krig_obs_sf",
    "krig_target_sf",
    "krig_zero_sf"
  )
  
  log_objects <- c(
    "frk_optimizer_diagnostic_main",
    "frk_optimizer_diagnostic_val"
  )
  
  manifest <- dplyr::bind_rows(
    purrr::map(data_objects,  ~ save_object_rds(.x, out_data)),
    purrr::map(model_objects, ~ save_object_rds(.x, out_models)),
    purrr::map(log_objects,   ~ save_object_rds(.x, out_logs))
  )
  
  readr::write_csv(
    manifest,
    fs::path(out_logs, "Step57_Object_Manifest.csv")
  )
  
  # Lightweight interoperable version of the completed panel.
  if (exists("krig_xy_completed", envir = .GlobalEnv)) {
    readr::write_csv(
      krig_xy_completed,
      fs::path(out_data, "krig_xy_completed.csv.gz")
    )
  }
  
  session_info <- utils::sessionInfo()
  
  saveRDS(
    session_info,
    fs::path(out_logs, "session_info.rds"),
    compress = "xz"
  )
  
  writeLines(
    capture.output(print(session_info)),
    fs::path(out_logs, "session_info.txt")
  )
  
  message("Step 57 complete. Essential objects saved to '3_Outputs'.")
}

# ==============================================================================
# 58. Generate Methodological Tables, Figures, and Logs
# ==============================================================================

{
  message("Step 58: generating methodological statistics, tables, and figures.")
  
  pkgs_58 <- c(
    "here", "fs", "readr", "dplyr", "tidyr", "tibble",
    "ggplot2", "sf", "viridis", "scales", "gt", "patchwork", "hexbin"
  )
  
  miss_58 <- pkgs_58[
    !vapply(pkgs_58, requireNamespace, logical(1), quietly = TRUE)
  ]
  
  if (length(miss_58) > 0L) {
    install.packages(miss_58, repos = "https://cloud.r-project.org")
  }
  
  suppressPackageStartupMessages(
    invisible(lapply(pkgs_58, library, character.only = TRUE))
  )
  
  # ---------------------------------------------------------------------------
  # 58.1 Paths and robust object loading
  # ---------------------------------------------------------------------------
  
  out_base   <- here::here("3_Outputs")
  out_data   <- fs::path(out_base, "1_Data_Processed")
  out_models <- fs::path(out_base, "2_Models")
  out_figs   <- fs::path(out_base, "3_Figures")
  out_tabs   <- fs::path(out_base, "4_Tables")
  out_logs   <- fs::path(out_data, "Run_Logs")
  
  fs::dir_create(c(out_figs, out_tabs, out_logs), recurse = TRUE)
  
  load_object <- function(obj_name, required = TRUE) {
    if (exists(obj_name, envir = .GlobalEnv)) {
      return(get(obj_name, envir = .GlobalEnv))
    }
    
    candidate_paths <- fs::path(
      c(out_data, out_models, out_logs),
      paste0(obj_name, ".rds")
    )
    
    existing <- candidate_paths[fs::file_exists(candidate_paths)]
    
    if (length(existing) == 0L) {
      if (required) {
        stop("Required object not found in memory or 3_Outputs: ", obj_name)
      }
      
      warning("Optional object not found: ", obj_name)
      return(NULL)
    }
    
    obj <- readRDS(existing[1])
    assign(obj_name, obj, envir = .GlobalEnv)
    obj
  }
  
  krig_xy_completed  <- load_object("krig_xy_completed")
  validation_holdout <- load_object("validation_holdout")
  validation_audit   <- load_object("validation_audit")
  validation_by_year <- load_object("validation_by_year", required = FALSE)
  validation_by_qtr  <- load_object("validation_by_qtr", required = FALSE)
  counties_proj      <- load_object("counties_proj")
  
  audit_interp       <- load_object("audit_interp", required = FALSE)
  imputation_audit   <- load_object("imputation_audit", required = FALSE)
  supp_rate          <- load_object("supp_rate", required = FALSE)
  gaps_ann           <- load_object("gaps_ann", required = FALSE)
  
  # ---------------------------------------------------------------------------
  # 58.2 Helper functions
  # ---------------------------------------------------------------------------
  
  pick_col <- function(data, candidates, required = TRUE) {
    out <- candidates[candidates %in% names(data)][1]
    
    if (is.na(out) || length(out) == 0L) {
      if (required) {
        stop(
          "None of these columns were found: ",
          paste(candidates, collapse = ", ")
        )
      }
      
      return(NULL)
    }
    
    out
  }
  
  sum_flag <- function(data, col) {
    if (is.null(col) || !col %in% names(data)) {
      return(NA_integer_)
    }
    
    values <- data[[col]]
    
    sum(values %in% c(TRUE, 1L, "1", "TRUE", "true"), na.rm = TRUE)
  }
  
  pct <- function(num, den) {
    ifelse(is.na(num) | is.na(den) | den == 0, NA_real_, 100 * num / den)
  }
  
  if (!"geom_fips" %in% names(krig_xy_completed)) {
    if ("area_fips" %in% names(krig_xy_completed)) {
      krig_xy_completed <- krig_xy_completed |>
        dplyr::mutate(geom_fips = as.character(area_fips))
    } else {
      stop("krig_xy_completed must contain either 'geom_fips' or 'area_fips'.")
    }
  }
  
  krig_xy_completed <- krig_xy_completed |>
    dplyr::mutate(
      geom_fips = as.character(geom_fips),
      year = as.character(year),
      qtr = as.character(qtr)
    )
  
  if (!"time_id" %in% names(krig_xy_completed)) {
    krig_xy_completed <- krig_xy_completed |>
      dplyr::arrange(year, qtr) |>
      dplyr::mutate(time_id = dplyr::dense_rank(paste(year, qtr)))
  }
  
  if (!inherits(counties_proj, "sf")) {
    counties_proj <- sf::st_as_sf(counties_proj)
  }
  
  if (!"area_fips" %in% names(counties_proj)) {
    stop("counties_proj must contain 'area_fips'.")
  }
  
  map_base <- counties_proj |>
    dplyr::mutate(geom_fips = as.character(area_fips)) |>
    dplyr::select(geom_fips)
  
  obs_col       <- pick_col(krig_xy_completed, c("obs_wage"), required = FALSE)
  target_col    <- pick_col(krig_xy_completed, c("target_wage", "imputed_by_frk"))
  zero_col      <- pick_col(krig_xy_completed, c("real_zero"), required = FALSE)
  log_obs_col   <- pick_col(krig_xy_completed, c("log_wage_real", "krig_value", "log_wage_real_completed"))
  log_comp_col  <- pick_col(krig_xy_completed, c("log_wage_real_completed"))
  wage_comp_col <- pick_col(krig_xy_completed, c("wk_wage_real_completed", "pred_wk_wage_real"), required = FALSE)
  se_col        <- pick_col(krig_xy_completed, c("pred_log_wage_real_se", "RMSPE_Y", "RMSPE_mu", "sd_Y", "sd_mu", "se_Y", "se_mu"), required = FALSE)
  
  krig_xy_completed <- krig_xy_completed |>
    dplyr::mutate(
      .target_wage_for_counts = .data[[target_col]] %in% c(TRUE, 1L, "1", "TRUE", "true"),
      .real_zero_for_counts = if (!is.null(zero_col)) .data[[zero_col]] %in% c(TRUE, 1L, "1", "TRUE", "true") else FALSE
    )
  
  krig_xy_completed <- krig_xy_completed |>
    dplyr::mutate(
      .obs_wage_for_figures = if (!is.null(obs_col)) {
        .data[[obs_col]] %in% c(TRUE, 1L, "1", "TRUE", "true")
      } else {
        !.data$.target_wage_for_counts &
          !.data$.real_zero_for_counts &
          !is.na(.data[[log_obs_col]])
      }
    )
  
  # ---------------------------------------------------------------------------
  # 58.3 Plot theme
  # ---------------------------------------------------------------------------
  
  theme_q1 <- ggplot2::theme_minimal(base_size = 11, base_family = "sans") +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 13),
      plot.subtitle = ggplot2::element_text(color = "grey30", size = 10),
      plot.caption = ggplot2::element_text(color = "grey50", size = 8, hjust = 0),
      legend.position = "bottom",
      legend.title = ggplot2::element_text(face = "bold", size = 9),
      legend.key.width = ggplot2::unit(1.5, "cm"),
      panel.grid.minor = ggplot2::element_blank()
    )
  
  theme_map <- theme_q1 +
    ggplot2::theme(
      axis.title = ggplot2::element_blank(),
      axis.text = ggplot2::element_blank(),
      axis.ticks = ggplot2::element_blank(),
      panel.grid = ggplot2::element_blank()
    )
  
  ggplot2::theme_set(theme_q1)
  
  # ---------------------------------------------------------------------------
  # 58.4 Core summary tables
  # ---------------------------------------------------------------------------
  
  target_flag <- krig_xy_completed$.target_wage_for_counts
  observed_n  <- sum(krig_xy_completed$.obs_wage_for_figures, na.rm = TRUE)
  target_n    <- sum(krig_xy_completed$.target_wage_for_counts, na.rm = TRUE)
  zero_n      <- sum(krig_xy_completed$.real_zero_for_counts, na.rm = TRUE)
  
  target_completed_n <- sum(
    krig_xy_completed$.target_wage_for_counts &
      !is.na(krig_xy_completed[[log_comp_col]]),
    na.rm = TRUE
  )
  
  interp_summary <- tibble::tibble(
    rows_completed = nrow(krig_xy_completed),
    observed_rows = observed_n,
    target_rows_to_interpolate = target_n,
    target_rows_successfully_imputed = target_completed_n,
    real_zero_rows_not_interpolated = zero_n,
    missing_completed_targets = target_n - target_completed_n,
    pct_observed = pct(observed_n, nrow(krig_xy_completed)),
    pct_to_interpolate = pct(target_n, nrow(krig_xy_completed)),
    pct_successfully_imputed = pct(target_completed_n, target_n),
    pct_real_zero_not_interpolated = pct(zero_n, nrow(krig_xy_completed))
  )
  
  readr::write_csv(
    interp_summary,
    fs::path(out_tabs, "Table1_Interpolation_Universe.csv")
  )
  
  tab_1 <- interp_summary |>
    gt::gt() |>
    gt::tab_header(
      title = "Table 1: Spatio-Temporal Interpolation Universe",
      subtitle = "Observed, suppressed/imputed, and real-zero county-quarter wage records"
    ) |>
    gt::fmt_number(
      columns = c(
        rows_completed,
        observed_rows,
        target_rows_to_interpolate,
        target_rows_successfully_imputed,
        real_zero_rows_not_interpolated,
        missing_completed_targets
      ),
      decimals = 0
    ) |>
    gt::fmt_number(
      columns = c(
        pct_observed,
        pct_to_interpolate,
        pct_successfully_imputed,
        pct_real_zero_not_interpolated
      ),
      decimals = 2
    ) |>
    gt::tab_source_note(
      source_note = "Note: real-zero records are retained as zero wages and are not interpolated on the log scale."
    )
  
  gt::gtsave(tab_1, fs::path(out_tabs, "Table1_Interpolation_Universe.html"))
  gt::gtsave(tab_1, fs::path(out_tabs, "Table1_Interpolation_Universe.tex"))
  gt::gtsave(tab_1, fs::path(out_tabs, "Table1_Interpolation_Universe.docx"))
  
  readr::write_csv(
    validation_audit,
    fs::path(out_tabs, "Table2_Validation_Audit.csv")
  )
  
  val_num_cols <- names(validation_audit)[
    vapply(validation_audit, is.numeric, logical(1))
  ]
  
  tab_2 <- validation_audit |>
    gt::gt() |>
    gt::tab_header(
      title = "Table 2: Out-of-Sample FRK Validation Diagnostics",
      subtitle = "Observed wage holdout versus FRK predictions"
    ) |>
    gt::fmt_number(columns = dplyr::all_of(val_num_cols), decimals = 3)
  
  gt::gtsave(tab_2, fs::path(out_tabs, "Table2_Validation_Audit.html"))
  gt::gtsave(tab_2, fs::path(out_tabs, "Table2_Validation_Audit.tex"))
  gt::gtsave(tab_2, fs::path(out_tabs, "Table2_Validation_Audit.docx"))
  
  if (!is.null(validation_by_year)) {
    readr::write_csv(
      validation_by_year,
      fs::path(out_tabs, "Table3_Validation_By_Year.csv")
    )
    
    tab_3 <- validation_by_year |>
      gt::gt() |>
      gt::tab_header(
        title = "Table 3: Validation Diagnostics by Year"
      ) |>
      gt::fmt_number(
        columns = dplyr::all_of(
          names(validation_by_year)[vapply(validation_by_year, is.numeric, logical(1))]
        ),
        decimals = 3
      )
    
    gt::gtsave(tab_3, fs::path(out_tabs, "Table3_Validation_By_Year.html"))
    gt::gtsave(tab_3, fs::path(out_tabs, "Table3_Validation_By_Year.tex"))
  }
  
  if (!is.null(validation_by_qtr)) {
    readr::write_csv(
      validation_by_qtr,
      fs::path(out_tabs, "Table4_Validation_By_Quarter.csv")
    )
    
    tab_4 <- validation_by_qtr |>
      gt::gt() |>
      gt::tab_header(
        title = "Table 4: Validation Diagnostics by Quarter"
      ) |>
      gt::fmt_number(
        columns = dplyr::all_of(
          names(validation_by_qtr)[vapply(validation_by_qtr, is.numeric, logical(1))]
        ),
        decimals = 3
      )
    
    gt::gtsave(tab_4, fs::path(out_tabs, "Table4_Validation_By_Quarter.html"))
    gt::gtsave(tab_4, fs::path(out_tabs, "Table4_Validation_By_Quarter.tex"))
  }
  
  # ---------------------------------------------------------------------------
  # 58.5 Period audit for figure selection
  # ---------------------------------------------------------------------------
  
  period_audit <- krig_xy_completed |>
    dplyr::group_by(time_id, year, qtr) |>
    dplyr::summarise(
      rows = dplyr::n(),
      observed_rows = sum(.data$.obs_wage_for_figures, na.rm = TRUE),
      target_rows = sum(.data$.target_wage_for_counts, na.rm = TRUE),
      real_zero_rows = sum(.data$.real_zero_for_counts, na.rm = TRUE),
      mean_completed_wage = if (!is.null(wage_comp_col)) mean(.data[[wage_comp_col]], na.rm = TRUE) else NA_real_,
      .groups = "drop"
    ) |>
    dplyr::arrange(time_id)
  
  readr::write_csv(
    period_audit,
    fs::path(out_tabs, "Table5_Period_Audit.csv")
  )
  
  latest_period <- period_audit |>
    dplyr::filter(time_id == max(time_id, na.rm = TRUE)) |>
    dplyr::slice(1)
  
  high_gap_period <- period_audit |>
    dplyr::arrange(dplyr::desc(target_rows), dplyr::desc(time_id)) |>
    dplyr::slice(1)
  
  period_label <- function(x) {
    paste0(x$year[1], " Q", x$qtr[1])
  }
  
  # ---------------------------------------------------------------------------
  # 58.6 Figure 1: spatial suppression intensity
  # ---------------------------------------------------------------------------
  
  gaps_spatial <- krig_xy_completed |>
    dplyr::group_by(geom_fips) |>
    dplyr::summarise(
      suppressed_count = sum(.data$.target_wage_for_counts, na.rm = TRUE),
      .groups = "drop"
    )
  
  fig1_data <- map_base |>
    dplyr::left_join(gaps_spatial, by = "geom_fips") |>
    dplyr::mutate(
      suppressed_count = dplyr::coalesce(suppressed_count, 0)
    )
  
  fig_1 <- ggplot2::ggplot(fig1_data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = suppressed_count),
      color = NA
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "magma",
      direction = -1,
      name = "Suppressed\nquarters"
    ) +
    ggplot2::labs(
      title = "Figure 1: Spatial Intensity of QCEW Wage Suppression",
      subtitle = "Cumulative suppressed county-quarter records requiring FRK imputation",
      caption = "Source: processed BLS QCEW county-quarter panel."
    ) +
    theme_map
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig1_Spatial_Suppression_Intensity.png"),
    fig_1,
    width = 10,
    height = 6,
    dpi = 600,
    bg = "white"
  )
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig1_Spatial_Suppression_Intensity.pdf"),
    fig_1,
    width = 10,
    height = 6
  )
  
  # ---------------------------------------------------------------------------
  # 58.7 Figure 2: before/after map for the highest-gap quarter
  # ---------------------------------------------------------------------------
  
  example_df <- krig_xy_completed |>
    dplyr::filter(time_id == high_gap_period$time_id[1]) |>
    dplyr::mutate(
      raw_observed_log_wage = dplyr::if_else(
        .data$.obs_wage_for_figures,
        .data[[log_obs_col]],
        NA_real_,
        missing = NA_real_
      )
    )
  
  example_map <- map_base |>
    dplyr::left_join(example_df, by = "geom_fips")
  
  p_raw <- ggplot2::ggplot(example_map) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = raw_observed_log_wage),
      color = NA
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "viridis",
      name = "Log real wage",
      na.value = "grey88"
    ) +
    ggplot2::labs(
      title = paste0("A. Observed data only (", period_label(high_gap_period), ")"),
      subtitle = "Grey counties are suppressed or non-observed in the raw wage field"
    ) +
    theme_map
  
  p_completed <- ggplot2::ggplot(example_map) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = .data[[log_comp_col]]),
      color = NA
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "viridis",
      name = "Log real wage",
      na.value = "grey88"
    ) +
    ggplot2::labs(
      title = paste0("B. Completed FRK field (", period_label(high_gap_period), ")"),
      subtitle = "Observed, FRK-imputed, and real-zero records in a single completed surface"
    ) +
    theme_map
  
  fig_2 <- p_raw + p_completed +
    patchwork::plot_layout(guides = "collect") &
    ggplot2::theme(legend.position = "bottom")
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig2_Before_After_Imputation_Map.png"),
    fig_2,
    width = 12,
    height = 6,
    dpi = 600,
    bg = "white"
  )
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig2_Before_After_Imputation_Map.pdf"),
    fig_2,
    width = 12,
    height = 6
  )
  
  # ---------------------------------------------------------------------------
  # 58.8 Figure 3: completed field for the latest quarter
  # ---------------------------------------------------------------------------
  
  latest_df <- krig_xy_completed |>
    dplyr::filter(time_id == latest_period$time_id[1])
  
  latest_map <- map_base |>
    dplyr::left_join(latest_df, by = "geom_fips")
  
  fig_3 <- ggplot2::ggplot(latest_map) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = .data[[log_comp_col]]),
      color = NA
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "viridis",
      name = "Log real wage",
      na.value = "grey88"
    ) +
    ggplot2::labs(
      title = "Figure 3: Completed Spatio-Temporal Wage Field",
      subtitle = paste0("Latest available quarter: ", period_label(latest_period)),
      caption = "Real-zero records are retained as zeros and omitted from the log-wage color scale."
    ) +
    theme_map
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig3_Completed_Field_Latest_Quarter.png"),
    fig_3,
    width = 10,
    height = 6,
    dpi = 600,
    bg = "white"
  )
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig3_Completed_Field_Latest_Quarter.pdf"),
    fig_3,
    width = 10,
    height = 6
  )
  
  # ---------------------------------------------------------------------------
  # 58.9 Figure 4: FRK prediction uncertainty
  # ---------------------------------------------------------------------------
  
  if (!is.null(se_col)) {
    fig_4 <- ggplot2::ggplot(latest_map) +
      ggplot2::geom_sf(
        ggplot2::aes(fill = .data[[se_col]]),
        color = NA
      ) +
      ggplot2::scale_fill_viridis_c(
        option = "inferno",
        name = "Prediction\nRMSPE / SE",
        na.value = "grey88"
      ) +
      ggplot2::labs(
        title = "Figure 4: Spatial Prediction Uncertainty",
        subtitle = paste0("FRK uncertainty surface for ", period_label(latest_period)),
        caption = "Dark counties generally correspond to observed records; bright counties indicate higher uncertainty among imputed records."
      ) +
      theme_map
    
    ggplot2::ggsave(
      fs::path(out_figs, "Fig4_FRK_Prediction_Uncertainty.png"),
      fig_4,
      width = 10,
      height = 6,
      dpi = 600,
      bg = "white"
    )
    
    ggplot2::ggsave(
      fs::path(out_figs, "Fig4_FRK_Prediction_Uncertainty.pdf"),
      fig_4,
      width = 10,
      height = 6
    )
  } else {
    warning("No prediction uncertainty column found. Figure 4 was skipped.")
  }
  
  # ---------------------------------------------------------------------------
  # 58.10 Figure 5: holdout validation hexbin plot
  # ---------------------------------------------------------------------------
  
  val_obs_col  <- pick_col(validation_holdout, c("log_wage_real", "observed_log_wage", "obs_log_wage"))
  val_pred_col <- pick_col(validation_holdout, c("pred_log_wage_real", "predicted_log_wage", "p_Y"))
  
  rmse_txt <- if ("rmse_log" %in% names(validation_audit)) {
    paste0("RMSE log = ", round(validation_audit$rmse_log[1], 3))
  } else {
    "RMSE log = NA"
  }
  
  cor_txt <- if ("cor_log" %in% names(validation_audit)) {
    paste0("Correlation = ", round(validation_audit$cor_log[1], 3))
  } else {
    "Correlation = NA"
  }
  
  fig_5 <- ggplot2::ggplot(
    validation_holdout,
    ggplot2::aes(x = .data[[val_obs_col]], y = .data[[val_pred_col]])
  ) +
    ggplot2::geom_hex(bins = 70, na.rm = TRUE) +
    ggplot2::geom_abline(
      slope = 1,
      intercept = 0,
      linetype = "dashed",
      linewidth = 0.8
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "magma",
      name = "Holdout\nrecords"
    ) +
    ggplot2::coord_equal() +
    ggplot2::labs(
      title = "Figure 5: Out-of-Sample Prediction Accuracy",
      subtitle = paste0(
        "Observed versus predicted log real wages; ",
        rmse_txt,
        " | ",
        cor_txt
      ),
      x = "Observed log real wage",
      y = "FRK-predicted log real wage",
      caption = "Dashed line denotes perfect prediction."
    ) +
    theme_q1
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig5_Holdout_Validation_Hexbin.png"),
    fig_5,
    width = 7,
    height = 7,
    dpi = 600,
    bg = "white"
  )
  
  ggplot2::ggsave(
    fs::path(out_figs, "Fig5_Holdout_Validation_Hexbin.pdf"),
    fig_5,
    width = 7,
    height = 7
  )
  
  # ---------------------------------------------------------------------------
  # 58.11 Figure 6: Hovmöller-style state-year heatmap
  # ---------------------------------------------------------------------------
  
  if (!is.null(wage_comp_col)) {
    hovmoller_data <- krig_xy_completed |>
      dplyr::mutate(
        state_fips = substr(geom_fips, 1, 2),
        year_num = as.integer(year)
      ) |>
      dplyr::filter(!is.na(.data[[wage_comp_col]]), !is.na(year_num)) |>
      dplyr::group_by(year_num, state_fips) |>
      dplyr::summarise(
        mean_real_wage = mean(.data[[wage_comp_col]], na.rm = TRUE),
        .groups = "drop"
      )
    
    state_fips_labels <- c(
      "01" = "AL",
      "04" = "AZ",
      "05" = "AR",
      "06" = "CA",
      "08" = "CO",
      "09" = "CT",
      "10" = "DE",
      "11" = "DC",
      "12" = "FL",
      "13" = "GA",
      "16" = "ID",
      "17" = "IL",
      "18" = "IN",
      "19" = "IA",
      "20" = "KS",
      "21" = "KY",
      "22" = "LA",
      "23" = "ME",
      "24" = "MD",
      "25" = "MA",
      "26" = "MI",
      "27" = "MN",
      "28" = "MS",
      "29" = "MO",
      "30" = "MT",
      "31" = "NE",
      "32" = "NV",
      "33" = "NH",
      "34" = "NJ",
      "35" = "NM",
      "36" = "NY",
      "37" = "NC",
      "38" = "ND",
      "39" = "OH",
      "40" = "OK",
      "41" = "OR",
      "42" = "PA",
      "44" = "RI",
      "45" = "SC",
      "46" = "SD",
      "47" = "TN",
      "48" = "TX",
      "49" = "UT",
      "50" = "VT",
      "51" = "VA",
      "53" = "WA",
      "54" = "WV",
      "55" = "WI",
      "56" = "WY"
    )
    
    hovmoller_anomalies <- hovmoller_data |>
      dplyr::group_by(state_fips) |>
      dplyr::mutate(
        state_median = stats::median(mean_real_wage, na.rm = TRUE),
        state_mad = stats::mad(mean_real_wage, na.rm = TRUE),
        robust_z = dplyr::if_else(
          state_mad > 0,
          abs(mean_real_wage - state_median) / state_mad,
          NA_real_
        )
      ) |>
      dplyr::ungroup() |>
      dplyr::arrange(dplyr::desc(robust_z)) |>
      dplyr::slice_head(n = 25)
    
    readr::write_csv(
      hovmoller_anomalies,
      fs::path(out_tabs, "Table6_Hovmoller_State_Year_Anomalies.csv")
    )
    
    fig_6 <- ggplot2::ggplot(
      hovmoller_data,
      ggplot2::aes(x = year_num, y = state_fips, fill = mean_real_wage)
    ) +
      ggplot2::geom_tile(linewidth = 0.05) +
      ggplot2::scale_fill_viridis_c(
        option = "viridis",
        labels = scales::dollar_format(),
        name = "Mean real\nweekly wage"
      ) +
      ggplot2::scale_y_discrete(
        labels = state_fips_labels
      ) +
      ggplot2::scale_x_continuous(
        expand = c(0, 0),
        breaks = seq(
          min(hovmoller_data$year_num, na.rm = TRUE),
          max(hovmoller_data$year_num, na.rm = TRUE),
          by = 5
        )
      ) +
      ggplot2::labs(
        title = "Figure 6: Hovmöller-Style Spatio-Temporal Wage Diagram",
        subtitle = "State-year average real weekly wages after FRK completion",
        x = "Year",
        y = "State"
      ) +
      theme_q1 +
      ggplot2::theme(
        panel.grid = ggplot2::element_blank(),
        axis.text.y = ggplot2::element_text(size = 7)
      )
    
    ggplot2::ggsave(
      fs::path(out_figs, "Fig6_Hovmoller_State_Year_Wages.png"),
      fig_6,
      width = 10,
      height = 8,
      dpi = 600,
      bg = "white"
    )
    
    ggplot2::ggsave(
      fs::path(out_figs, "Fig6_Hovmoller_State_Year_Wages.pdf"),
      fig_6,
      width = 10,
      height = 8
    )
  } else {
    warning("No completed real-wage column found. Figure 6 was skipped.")
  }
  
  # ---------------------------------------------------------------------------
  # 58.12 Reproducibility log and output manifest
  # ---------------------------------------------------------------------------
  
  output_files <- fs::dir_ls(out_base, recurse = TRUE, type = "file")
  
  output_manifest <- tibble::tibble(
    file = as.character(output_files),
    size_mb = round(as.numeric(fs::file_size(output_files)) / 1024^2, 4)
  ) |>
    dplyr::arrange(file)
  
  readr::write_csv(
    output_manifest,
    fs::path(out_logs, "Step58_Output_File_Manifest.csv")
  )
  
  coverage_txt <- if ("coverage_95" %in% names(validation_audit)) {
    as.character(validation_audit$coverage_95[1])
  } else {
    "NA"
  }
  
  log_text <- c(
    "==========================================================",
    "QCEW FRK Spatio-Temporal Interpolation - Methodological Outputs",
    "==========================================================",
    paste("Timestamp:", Sys.time()),
    paste("Completed panel rows:", format(nrow(krig_xy_completed), big.mark = ",")),
    paste("Observed rows:", format(interp_summary$observed_rows[1], big.mark = ",")),
    paste("Target rows to interpolate:", format(interp_summary$target_rows_to_interpolate[1], big.mark = ",")),
    paste("Targets successfully imputed:", format(interp_summary$target_rows_successfully_imputed[1], big.mark = ",")),
    paste("Real-zero rows not interpolated:", format(interp_summary$real_zero_rows_not_interpolated[1], big.mark = ",")),
    paste("Missing completed targets:", format(interp_summary$missing_completed_targets[1], big.mark = ",")),
    paste("Validation RMSE log:", if ("rmse_log" %in% names(validation_audit)) round(validation_audit$rmse_log[1], 4) else "NA"),
    paste("Validation 95% coverage:", coverage_txt),
    paste("Latest mapped period:", period_label(latest_period)),
    paste("Highest-gap mapped period:", period_label(high_gap_period)),
    paste("Output files generated:", length(output_files)),
    "=========================================================="
  )
  
  writeLines(
    log_text,
    fs::path(out_logs, "Step58_Methodological_Output_Log.txt")
  )
  message("PNG figures saved at 600 dpi with white background.")
  message("Step 58 complete. Tables, figures, and logs saved in '3_Outputs'.")
}
