# 3_1_Nutrient_index.R
#
# purpose:
#   builds a nutrient input index (NII) for each site from upstream nitrogen
#   and phosphorus loading. combines four usgs fertilizer/manure source
#   layers (2002/2007/2012/2017 averages), traverses each site's upstream
#   network via the nldi to sum loading across all upstream comids, then
#   combines with discharge to compute and standardize areal N and P loading.
#   if using nutrient concentration instead of flux, the same standardization
#   approach can be applied directly to concentration data.
#
# data source:
#   USGS Nitrogen and phosphorus inputs from fertilizer and manure in the
#   Continental United States, 2002-2017 (kg/yr)
#   https://www.usgs.gov/data/nitrogen-and-phosphorus-inputs-fertilizer-and-manure-continental-united-states-2002-2017
#
# inputs:
#   - Data/input/nutrient_data/ag_tn_cman.csv, ag_tn_fert.csv, ag_tn_uman.csv,
#     ag_tp_cman.csv, ag_tp_fert.csv, ag_tp_uman.csv, de_tn_fert.csv,
#     de_tp_fert.csv : usgs fertilizer/manure loading by COMID, one column
#     per year (2002/2007/2012/2017)
#   - Data/input/nutrient_data/site_COMID.csv : site_id to COMID lookup
#   - Data/output/river_metabolism_data/Appling_input_average_monthly.csv :
#     monthly discharge averages (from 1_Calculate_average_rivermetabolism.R)
#
# outputs:
#   - Data/output/nutrient_index.csv : site-month table with upstream N/P
#     flux, load-derived nutrient concentrations (A_TN, A_TP), and the standardized nutrient index


library(data.table)
library(nhdplusTools)


# 1. load and average the usgs fertilizer/manure loading layers ----------------

# total nitrogen from agricultural confined manure sources
ag_tn_cman <- fread("Data/input/nutrient_data/ag_tn_cman.csv", colClasses = list(character = "COMID"))
ag_tn_cman[, ag_tn_cman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_cman_2002", "ag_tn_cman_2007", "ag_tn_cman_2012", "ag_tn_cman_2017")]
tn_cman_avg <- ag_tn_cman[, .(COMID, ag_tn_cman_avg)]

# total nitrogen from agricultural fertilizer sources
ag_tn_fert <- fread("Data/input/nutrient_data/ag_tn_fert.csv", colClasses = list(character = "COMID"))
ag_tn_fert[, ag_tn_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_fert_2002", "ag_tn_fert_2007", "ag_tn_fert_2012", "ag_tn_fert_2017")]
tn_fert_avg <- ag_tn_fert[, .(COMID, ag_tn_fert_avg)]

# total nitrogen from agricultural unconfined manure sources
ag_tn_uman <- fread("Data/input/nutrient_data/ag_tn_uman.csv", colClasses = list(character = "COMID"))
ag_tn_uman[, ag_tn_uman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tn_uman_2002", "ag_tn_uman_2007", "ag_tn_uman_2012", "ag_tn_uman_2017")]
tn_uman_avg <- ag_tn_uman[, .(COMID, ag_tn_uman_avg)]

# total phosphorus from agricultural confined manure sources
ag_tp_cman <- fread("Data/input/nutrient_data/ag_tp_cman.csv", colClasses = list(character = "COMID"))
ag_tp_cman[, ag_tp_cman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_cman_2002", "ag_tp_cman_2007", "ag_tp_cman_2012", "ag_tp_cman_2017")]
tp_cman_avg <- ag_tp_cman[, .(COMID, ag_tp_cman_avg)]

# total phosphorus from agricultural fertilizer sources
ag_tp_fert <- fread("Data/input/nutrient_data/ag_tp_fert.csv", colClasses = list(character = "COMID"))
ag_tp_fert[, ag_tp_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_fert_2002", "ag_tp_fert_2007", "ag_tp_fert_2012", "ag_tp_fert_2017")]
tp_fert_avg <- ag_tp_fert[, .(COMID, ag_tp_fert_avg)]

# total phosphorus from agricultural unconfined manure sources
ag_tp_uman <- fread("Data/input/nutrient_data/ag_tp_uman.csv", colClasses = list(character = "COMID"))
ag_tp_uman[, ag_tp_uman_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("ag_tp_uman_2002", "ag_tp_uman_2007", "ag_tp_uman_2012", "ag_tp_uman_2017")]
tp_uman_avg <- ag_tp_uman[, .(COMID, ag_tp_uman_avg)]

# total nitrogen from developed fertilizer sources
de_tn_fert <- fread("Data/input/nutrient_data/de_tn_fert.csv", colClasses = list(character = "COMID"))
de_tn_fert[, de_tn_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("de_tn_fert_2002", "de_tn_fert_2007", "de_tn_fert_2012", "de_tn_fert_2017")]
de_tn_fert_avg <- de_tn_fert[, .(COMID, de_tn_fert_avg)]

# total phosphorus from developed fertilizer sources
de_tp_fert <- fread("Data/input/nutrient_data/de_tp_fert.csv", colClasses = list(character = "COMID"))
de_tp_fert[, de_tp_fert_avg := rowMeans(.SD, na.rm = TRUE),
           .SDcols = c("de_tp_fert_2002", "de_tp_fert_2007", "de_tp_fert_2012", "de_tp_fert_2017")]
de_tp_fert_avg <- de_tp_fert[, .(COMID, de_tp_fert_avg)]

# merge all source layers by COMID
dt_list <- list(tn_cman_avg, tn_fert_avg, tn_uman_avg, tp_cman_avg,
                tp_fert_avg, tp_uman_avg, de_tn_fert_avg, de_tp_fert_avg)

nutrient_summary <- Reduce(function(dt1, dt2) {merge(dt1, dt2, by = "COMID", all = TRUE)}, dt_list)

# total N and P inputs per COMID
nutrient_summary[, total_N_input := ag_tn_cman_avg + ag_tn_fert_avg + ag_tn_uman_avg + de_tn_fert_avg]
nutrient_summary[, total_P_input := ag_tp_cman_avg + ag_tp_fert_avg + ag_tp_uman_avg + de_tp_fert_avg]


# 2. sum loading across each site's upstream network ---------------------------

COMID_data <- fread("Data/input/nutrient_data/site_COMID.csv",
                    colClasses = list(character = c("site_id", "COMID")))

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

start_time <- Sys.time()

n_sites <- nrow(COMID_data)
all_results <- list()

for (i in 1:n_sites) {
  row <- COMID_data[i]

  cat("Processing site", i, "/", n_sites, "- Site ID:", row$site_id, "...")

  result <- get_upstream_flux(row$site_id, row$COMID, nutrient_summary)
  all_results[[i]] <- result

  cat("Status:", result$status, "\n")
}

end_time <- Sys.time()
duration <- end_time - start_time
cat("Total processing time:", round(as.numeric(duration, units = "mins"), 2), "minutes\n")

results_dt <- rbindlist(lapply(all_results, as.data.table), fill = TRUE)

dt_nutrient <- results_dt[, status := NULL]
dt_nutrient <- na.omit(dt_nutrient)


# 3. combine with discharge and compute the standardized nutrient index ---------

dt_disch <- fread("Data/output/river_metabolism_data/Appling_input_average_monthly.csv",
                  colClasses = list(character = "site_id"))

dt_disch <- dt_disch[, .(
  site_id = site_id,
  month = month,
  discharge_avg = discharge_avg)]

dt_disch[, mean_discharge := mean(discharge_avg, na.rm = TRUE), by = site_id]

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

# nutrient input index (NII)
dt_merged[, nutrient_index := (TN_star + TP_star) / 2]

fwrite(dt_merged, "Data/output/nutrient_index.csv")
