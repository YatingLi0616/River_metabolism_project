# Calculate_nutrient_index_and_discharge_skewness.R
#
# purpose:
#   computes two variables used in the paper:
#     1. nutrient index              - standardized upstream N and P loading
#     2. discharge skewness          - L-skewness from annual discharge L-moments
#
# required input data (not included - obtain and format as described below):
#
#   1. nitrogen and phosphorus loading by COMID
#      source: Sekellick, A. J., & Sherr, C. F. (2024). Nitrogen and
#      phosphorus inputs from fertilizer and manure in the Continental
#      United States, 2002-2017. U.S. Geological Survey data release.
#      DOI: https://doi.org/10.5066/P9WDBIXC
#
#      download the eight component layers - agricultural confined manure,
#      agricultural fertilizer, and agricultural unconfined manure (each
#      for both total nitrogen and total phosphorus), plus developed
#      fertilizer (for both N and P). each layer should be indexed by
#      COMID, with one column per available year (2002, 2007, 2012, 2017).
#
#   2. a COMID for every monitoring site
#      the nutrient loading data above, and the upstream river network
#      traversal below, are both indexed by COMID (the NHDPlus common
#      identifier). 
#      every monitoring site must be matched to its corresponding COMID before 
#      this script can run. this is typically done by snapping each site's
#      coordinates to the NHDPlus flowline network. 
#
#   3. daily discharge data 
#      source: Appling, A.P., Read, J.S., Winslow, L.A., Arroita, M.,
#      Bernhardt, E.S., Griffiths, N.A., Heffernan, J.B., Stets, E.G.,
#      Yackulic, C.B., Beck, W.H., Burgers, A.S., and Hall, R.O. (2018).
#      Metabolism estimates for 356 U.S. rivers ... U.S. Geological Survey
#      data release. DOI: https://doi.org/10.5066/F70864KX
#
#      this script expects daily discharge as a named list of per-site
#      data.frames, each with a date column and a discharge column.
#
# outputs:
#   - dt_merged          : site-month table with upstream N/P flux, areal
#                          loading (A_TN, A_TP), and the standardized
#                          nutrient index (nutrient_index)
#   - flow_metrics_final : one row per site with averaged annual discharge
#                          l-moments (disch_mean, disch_cv, disch_skew,
#                          disch_kurt)
#
# usage:
#   fill in the four data objects in the "load your data" sections below
#   with your own data, matching the formats described above, then run.


library(data.table)
library(nhdplusTools)
library(lmomco)
library(lubridate)

# part 1: nutrient input index (NII) --------------------------------------------

# 1.1 load data: N/P loading layers (see requirement #1 above)
# each of the eight objects below must be a data.table with a COMID column
# and one column per year, e.g. ag_tn_cman_2002, ag_tn_cman_2007, ...

ag_tn_cman <- NULL   # agricultural confined manure, total nitrogen
ag_tn_fert <- NULL   # agricultural fertilizer, total nitrogen
ag_tn_uman <- NULL   # agricultural unconfined manure, total nitrogen
ag_tp_cman <- NULL   # agricultural confined manure, total phosphorus
ag_tp_fert <- NULL   # agricultural fertilizer, total phosphorus
ag_tp_uman <- NULL   # agricultural unconfined manure, total phosphorus
de_tn_fert <- NULL   # developed fertilizer, total nitrogen
de_tp_fert <- NULL   # developed fertilizer, total phosphorus

# 1.2 average across years and combine layers

ag_tn_cman[, ag_tn_cman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_cman_2002", "ag_tn_cman_2007", "ag_tn_cman_2012", "ag_tn_cman_2017")]
tn_cman_avg <- ag_tn_cman[, .(COMID, ag_tn_cman_avg)]

ag_tn_fert[, ag_tn_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_fert_2002", "ag_tn_fert_2007", "ag_tn_fert_2012", "ag_tn_fert_2017")]
tn_fert_avg <- ag_tn_fert[, .(COMID, ag_tn_fert_avg)]

ag_tn_uman[, ag_tn_uman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_uman_2002", "ag_tn_uman_2007", "ag_tn_uman_2012", "ag_tn_uman_2017")]
tn_uman_avg <- ag_tn_uman[, .(COMID, ag_tn_uman_avg)]

ag_tp_cman[, ag_tp_cman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_cman_2002", "ag_tp_cman_2007", "ag_tp_cman_2012", "ag_tp_cman_2017")]
tp_cman_avg <- ag_tp_cman[, .(COMID, ag_tp_cman_avg)]

ag_tp_fert[, ag_tp_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_fert_2002", "ag_tp_fert_2007", "ag_tp_fert_2012", "ag_tp_fert_2017")]
tp_fert_avg <- ag_tp_fert[, .(COMID, ag_tp_fert_avg)]

ag_tp_uman[, ag_tp_uman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_uman_2002", "ag_tp_uman_2007", "ag_tp_uman_2012", "ag_tp_uman_2017")]
tp_uman_avg <- ag_tp_uman[, .(COMID, ag_tp_uman_avg)]

de_tn_fert[, de_tn_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("de_tn_fert_2002", "de_tn_fert_2007", "de_tn_fert_2012", "de_tn_fert_2017")]
de_tn_fert_avg <- de_tn_fert[, .(COMID, de_tn_fert_avg)]

de_tp_fert[, de_tp_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("de_tp_fert_2002", "de_tp_fert_2007", "de_tp_fert_2012", "de_tp_fert_2017")]
de_tp_fert_avg <- de_tp_fert[, .(COMID, de_tp_fert_avg)]

dt_list <- list(tn_cman_avg, tn_fert_avg, tn_uman_avg, tp_cman_avg,
                tp_fert_avg, tp_uman_avg, de_tn_fert_avg, de_tp_fert_avg)

nutrient_summary <- Reduce(function(dt1, dt2) {merge(dt1, dt2, by = "COMID", all = TRUE)}, dt_list)

nutrient_summary[, total_N_input := ag_tn_cman_avg + ag_tn_fert_avg + ag_tn_uman_avg + de_tn_fert_avg]
nutrient_summary[, total_P_input := ag_tp_cman_avg + ag_tp_fert_avg + ag_tp_uman_avg + de_tp_fert_avg]

# 1.3 load data: site-to-COMID lookup (see requirement #2 above)
# a data.table with one row per monitoring site: columns site_id, COMID

COMID_data <- NULL

# 1.4 sum loading across each site's upstream network

get_upstream_flux <- function(site_id, comid, nutrient_data) {
  
  if (is.na(comid) || comid == "") {
    return(list(site_id = site_id, upstream_N = NA, upstream_P = NA, status = "No COMID"))
  }
  
  # distance_km = 9999 effectively pulls the entire upstream network -
  # the nldi default of 10 km is far too short for a basin-scale sum
  upstream <- tryCatch({
    navigate_nldi(list(featureSource = "comid", featureID = as.character(comid)),
                  mode = "UT",
                  data_source = "flowlines",
                  distance_km = 9999)
  }, error = function(e) NULL)
  
  if (is.null(upstream) || is.null(upstream$UT) || nrow(upstream$UT) == 0) {
    return(list(site_id = site_id, upstream_N = NA, upstream_P = NA, status = "No upstream"))
  }
  
  upstream_comids <- upstream$UT$nhdplus_comid
  nutrient_subset <- nutrient_data[COMID %in% upstream_comids]
  
  return(list(
    site_id = site_id,
    COMID = comid,
    upstream_N = sum(nutrient_subset$total_N_input, na.rm = TRUE),
    upstream_P = sum(nutrient_subset$total_P_input, na.rm = TRUE),
    status = "Success"
  ))
}

n_sites <- nrow(COMID_data)
all_results <- list()

for (i in 1:n_sites) {
  row <- COMID_data[i]
  
  cat("Processing site", i, "/", n_sites, "- Site ID:", row$site_id, "...")
  
  result <- get_upstream_flux(row$site_id, row$COMID, nutrient_summary)
  all_results[[i]] <- result
  
  cat("Status:", result$status, "\n")
}

results_dt <- rbindlist(lapply(all_results, as.data.table), fill = TRUE)
dt_nutrient <- results_dt[, status := NULL]
dt_nutrient <- na.omit(dt_nutrient)

# 1.5 load data: monthly discharge averages (see requirement #3 above,
#     averaged to monthly - see part 2 below for the daily version)
# a data.table with columns site_id, month, discharge_avg

dt_disch <- NULL

dt_disch[, mean_discharge := mean(discharge_avg, na.rm = TRUE), by = site_id]

# 1.6 combine and compute the standardized nutrient index

dt_merged <- merge(dt_disch, dt_nutrient, by = "site_id")

dt_merged[, `:=`(A_TN = (upstream_N / (mean_discharge * 60 * 60 * 24 * 365)),
                 A_TP = (upstream_P / (mean_discharge * 60 * 60 * 24 * 365)))]

# standardize using median and IQR (robust to outliers, common for skewed loading data)
median_TN <- median(dt_merged$A_TN, na.rm = TRUE)
IQR_TN <- IQR(dt_merged$A_TN, na.rm = TRUE)

median_TP <- median(dt_merged$A_TP, na.rm = TRUE)
IQR_TP <- IQR(dt_merged$A_TP, na.rm = TRUE)

dt_merged[, `:=`(TN_star = (A_TN - median_TN) / IQR_TN,
                 TP_star = (A_TP - median_TP) / IQR_TP)]

dt_merged[, nutrient_index := (TN_star + TP_star) / 2]

# note: if calculate nutrient_index with nutrient concerntration
# download nutrient concentration data from USGS
# then follow the above approch, do not need to divided by discharge

# part 2: discharge skewness --------------------------------------------------

# 2.1 load data: daily discharge (see requirement #3 above)
# a named list of per-site data.frames, each with columns date, discharge

input_data <- NULL

# 2.2 calculation functions

# l-moments for one year of daily discharge
calc_annual_lmom <- function(q) {
  q <- q[is.finite(q) & !is.na(q)]
  
  # need at least 50 observations to calculate l-moments reliably
  if (length(q) < 50) return(NULL)
  
  l <- lmomco::lmom.ub(q)
  
  return(data.table(
    disch_mean = l$L1,
    disch_cv = l$LCV,
    disch_skew = l$TAU3,
    disch_kurt = l$TAU4
  ))
}

# site-level metrics: l-moments per valid year, averaged across valid years
calc_site_flow_metrics_yearly <- function(df_site,
                                          site_id,
                                          date_col = "date",
                                          q_col = "discharge",
                                          min_coverage_year = 0.50,  # at least 50% data per year
                                          min_valid_years = 1)       # at least 1 valid year
{
  dt <- as.data.table(df_site)
  
  dt[, date := as.Date(get(date_col))]
  dt <- dt[!is.na(date)]
  dt[, Year := year(date)]
  
  years <- sort(unique(dt$Year))
  annual_results <- list()
  
  for (yr in years) {
    dt_year <- dt[Year == yr]
    
    year_start <- as.Date(paste0(yr, "-01-01"))
    year_end <- as.Date(paste0(yr, "-12-31"))
    total_days_in_year <- as.numeric(difftime(year_end, year_start, units = "days")) + 1
    
    q_year <- dt_year[[q_col]]
    q_year_valid <- q_year[is.finite(q_year)]
    
    n_obs <- length(q_year_valid)
    coverage_year <- n_obs / total_days_in_year
    
    if (coverage_year < min_coverage_year) next
    
    lmom_year <- calc_annual_lmom(q_year_valid)
    if (is.null(lmom_year)) next
    
    annual_results[[as.character(yr)]] <- cbind(
      data.table(
        site_id = site_id,
        year = yr,
        n_obs = n_obs,
        coverage = round(coverage_year, 3)
      ),
      lmom_year
    )
  }
  
  if (length(annual_results) < min_valid_years) {
    return(data.table(
      site_id = site_id,
      disch_mean = NA_real_,
      disch_cv = NA_real_,
      disch_skew = NA_real_,
      disch_kurt = NA_real_,
      n_years_valid = length(annual_results),
      n_years_total = length(years),
      mean_coverage = NA_real_,
      filter_reason = "insufficient_valid_years"
    ))
  }
  
  annual_dt <- rbindlist(annual_results, use.names = TRUE, fill = TRUE)
  
  site_metrics <- data.table(
    site_id = site_id,
    disch_mean = mean(annual_dt$disch_mean, na.rm = TRUE),
    disch_cv = mean(annual_dt$disch_cv, na.rm = TRUE),
    disch_skew = mean(annual_dt$disch_skew, na.rm = TRUE),
    disch_kurt = mean(annual_dt$disch_kurt, na.rm = TRUE),
    n_years_valid = nrow(annual_dt),
    n_years_total = length(years),
    mean_coverage = mean(annual_dt$coverage, na.rm = TRUE),
    years_used = paste(annual_dt$year, collapse = ","),
    filter_reason = "passed"
  )
  
  return(site_metrics)
}

# 2.3 apply to all sites

flow_metrics_yearly <- rbindlist(
  lapply(names(input_data), function(nm) {
    site_id <- gsub("_input$", "", nm)
    
    calc_site_flow_metrics_yearly(
      df_site = input_data[[nm]],
      site_id = site_id,
      date_col = "date",
      q_col = "discharge",
      min_coverage_year = 0.50,
      min_valid_years = 1
    )
  }),
  use.names = TRUE,
  fill = TRUE
)

print(table(flow_metrics_yearly$filter_reason))

flow_metrics_final <- flow_metrics_yearly[filter_reason == "passed"]

flow_metrics_final[, `:=`(
  disch_mean = round(disch_mean, 3),
  disch_cv = round(disch_cv, 3),
  disch_skew = round(disch_skew, 3),
  disch_kurt = round(disch_kurt, 3),
  mean_coverage = round(mean_coverage, 3)
)]