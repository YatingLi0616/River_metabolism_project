# 4_Complie_data.R
#
# purpose:
#   compiles all the averaged/derived datasets from scripts 1-3 and the
#   nlcd land cover pipeline into a single model-ready table. shown here
#   for monthly data - daily compilation follows the same steps, just
#   swapping in the daily versions of each input file.
#
# inputs:
#   - Data/output/river_metabolism_data/Appling_input_average_monthly.csv
#   - Data/output/river_metabolism_data/Appling_output_average_monthly.csv
#   - Data/output/USGS_data/<pH|alk|...>_monthly.csv  (from 2_Calculate_averge_USGS.R)
#   - Data/output/nutrient_index.csv                  (from 3_1_Nutrient_index.R)
#   - Data/output/discharge_skewness.csv              (from 3_2_Discharge_skewness.R)
#   - Data/output/tcc_allsites.csv                    (from 3_3_Calculate_TCC.R)
#   - Data/output/NLCD_data/landcover_allsites.csv    (from 3_4_Calculate_landcover - see its own README)
#
# outputs:
#   - Data/output/ML_monthly.rds : one row per site-month, with metabolism
#     (GPP/ER/NEP), drivers (light, light_eff, discharge, disch_skew, temp),
#     land cover fractions, nutrient flux/index, and carbonate chemistry
#     (pH, alk, pCO2, CO2, HCO3, CO3, DIC). this is the input file used by
#     RF_monthly.R, RF_DCV_monthly.R, and pdp_analysis_parallel.R.


library(data.table)
library(seacarb)


# 1. load appling averaged data and merge GPP/ER with drivers ------------------

appling_input_average <- fread("Data/output/river_metabolism_data/Appling_input_average_monthly.csv",
                               colClasses = list(character = "site_id"))
length(unique(appling_input_average$site_id))

appling_output_average <- fread("Data/output/river_metabolism_data/Appling_output_average_monthly.csv",
                                colClasses = list(character = "site_id"))
length(unique(appling_output_average$site_id))

# start the combined dataset from output (GPP and ER)
combined_data <- copy(appling_output_average)
combined_data[, count := NULL]
combined_data[, site_id := as.character(site_id)]

# merge in input drivers: DO, light, depth, discharge, temp_water
input_data <- copy(appling_input_average)
input_data[, site_id := as.character(site_id)]

combined_data <- merge(
  combined_data,
  input_data[, .(
    site_id, month,
    depth_avg,
    temp_water_avg, light_avg, discharge_avg
  )],
  by = c("site_id", "month"),
  all.x = TRUE)

length(unique(combined_data$site_id))

# convert ER to a positive value, calculate NEP
combined_data[, ER_avg := - ER_avg]
combined_data[, NEP_avg := GPP_avg - ER_avg]


# 2. add usgs water chemistry data ---------------------------------------------

# only keep these variables (must match the part before "_monthly.csv")
vars_to_keep <- c("pH", "alk")
# add TN and TP for TN concentration and TP concentration if needed

average_files <- file.path("Data/output/USGS_data", paste0(vars_to_keep, "_monthly.csv"))
names(average_files) <- vars_to_keep

USGS_average_list <- lapply(average_files, fread)

USGS_average_list <- lapply(USGS_average_list, function(dt) {
  dt[, site_id := gsub("USGS-", "", site_no)]
  dt
})

# build one site coordinate lookup table from whichever files have lon/lat
coords_list <- lapply(USGS_average_list, function(dt) {
  if (all(c("lon", "lat") %in% names(dt))) dt[, .(site_id, lon, lat)] else NULL
})
site_coords <- rbindlist(coords_list, use.names = TRUE)
site_coords <- unique(site_coords[!is.na(lon) & !is.na(lat)], by = "site_id")

# merge coordinates into combined_data once
combined_data <- merge(combined_data, site_coords, by = "site_id", all.x = TRUE)

# merge each parameter's values in turn
for (param_name in names(USGS_average_list)) {
  cat("Processing", param_name, "data...\n")

  usgs_data <- copy(USGS_average_list[[param_name]])
  setnames(usgs_data, c("stream_month", "value"), c("month", param_name))

  merge_cols <- c("site_id", "month", param_name)
  combined_data <- merge(
    combined_data,
    usgs_data[, ..merge_cols],
    by = c("site_id", "month"),
    all.x = TRUE
  )

  cat("  Parameter", param_name, "merged successfully.\n\n")
}

# tidy up "_avg" suffixes from the appling merge
avg_cols <- names(combined_data)[grepl("_avg", names(combined_data))]
new_names <- gsub("_avg", "", avg_cols)
setnames(combined_data, avg_cols, new_names)

# convert pH (H+) to the standard -log10 scale
combined_data[, pH := -log10(pH)]
 

# 3. add nutrient flux / nutrient index data -----------------------------------

dt_nutrient <- fread("Data/output/nutrient_index.csv",
            colClasses = list(character = "site_id"))

dt_nutrient <- dt_nutrient[, .(
  site_id = site_id,
  TN_flux = upstream_N,
  TP_flux = upstream_P,
  month = month,
  nutrient_index = nutrient_index)]

combined_data <- merge(
  combined_data,
  dt_nutrient,
  by = c("site_id", "month"),
  all.x = TRUE)
 

# 4. add discharge skewness data -----------------------------------------------

disch_skewness <- fread("Data/output/discharge_skewness.csv",
                       colClasses = list(character = "site_id"))

# discharge_skewness.csv uses bare usgs ids; combined_data uses "nwis_" prefixed
# ids at this point, so match on a temporary prefixed column
combined_data[, site_id_match := paste0("nwis_", site_id)]

combined_data[disch_skewness, disch_skew := i.disch_skew,
              on = .(site_id_match = site_id)]

combined_data[, site_id_match := NULL]


# 5. add tree canopy cover (tcc) data ------------------------------------------

dt_TCC <- fread("Data/output/tcc_allsites.csv",
                colClasses = list(character = "site_id"))

dt_TCC <- dt_TCC[, .(
  site_id = site_id,
  TCC = mean.mean
)]

combined_data <- merge(
  combined_data,
  dt_TCC,
  by = c("site_id"),
  all.x = TRUE)

# effective light after accounting for canopy shading
combined_data[, light_eff := light * (1-TCC/100)]


# 6. add nlcd land cover data --------------------------------------------------

land_cover <- fread("Data/output/NLCD_data/landcover_allsites.csv",
                    colClasses = list(character = c("site_id")))

land_cover <- land_cover[, .(
  site_id = site_id,
  urban = urban,
  forest = forest,
  dryland = dryland,
  agriculture = agriculture,
  wetland = wetland)]

combined_data <- merge(
  combined_data,
  land_cover,
  by = c("site_id"),
  all.x = TRUE)

# drop any row missing a value in any column at this point
combined_data <- na.omit(combined_data)


# 7. carbonate chemistry (pCO2, CO2, HCO3, CO3, DIC) via seacarb ---------------

combined_data[, alk_1 := alk / 1000]

carb_initial <- carb(
  flag = 8,              # known alkalinity and pH, calculate DIC
  var1 = combined_data$pH,
  var2 = combined_data$alk_1,
  S = 0.1,
  T = combined_data$temp_water,
  k1k2 = "m06")          # use Millero (2006) constants

combined_data[, `:=`(pCO2 = carb_initial$pCO2,         # uatm
                         CO2 = carb_initial$CO2 * 1000,    # mmol/L
                         HCO3 = carb_initial$HCO3 * 1000,  # mmol/L
                         CO3 = carb_initial$CO3 * 1000,    # mmol/L
                         DIC = carb_initial$DIC * 1000)]   # mmol/L

combined_data[, `:=`(alk_1 = NULL)]
combined_data <- combined_data[DIC > 0]

# 8. other variables -----------------------------------------------------------
ws_dt <- fread("Data/input/appling_data_06202024_Taylor.csv")
ws_dt$site_name <- gsub("nwis_", "", ws_dt$site_name)

vars_to_add <- c("order", "uparea")
ws_site <- unique(ws_dt[, c("site_name", vars_to_add), with = FALSE])

combined_data <- merge(combined_data, ws_site,
                       by.x = "site_id", by.y = "site_name",
                       all.x = TRUE)

vars_to_add <- c("width")
ws_site <- ws_dt[, lapply(.SD, mean, na.rm = TRUE), 
                 by = .(site_name, month), 
                 .SDcols = vars_to_add]

combined_data <- merge(combined_data, ws_site,
                       by.x = c("site_id", "month"), by.y = c("site_name", "month"),
                       all.x = TRUE)

combined_data <- na.omit(combined_data)

# 9. reorder columns and save --------------------------------------------------

combined_data <- combined_data[, .(site_id, lon, lat, month,
                                   GPP, ER, NEP,
                                   depth, temp_water, light, light_eff, discharge, disch_skew,
                                   urban, forest, dryland, agriculture, wetland, TCC,
                                   TN_flux, TP_flux, nutrient_index,
                                   pH, alk, pCO2, CO2, HCO3, CO3, DIC,
                                   order, uparea, width)]

saveRDS(combined_data, "Data/output/ML_monthly.rds")

# 10. group river systems by size ----------------------------------------------
# Get site-level uparea (same value per site so unique() is fine)
site_uparea <- unique(combined_data[, .(site_id, order, uparea)])

# Get max uparea for each order
max_order <- site_uparea[order == 3, max(uparea)]

# Cut into subsets based on thresholds
small_river <- combined_data[uparea <= max_order]       
large_river <- combined_data[uparea > max_order]

saveRDS(small_river, "Data/output/ML_data/ML_monthly_smallarea.rds")
saveRDS(large_river, "Data/output/ML_data/ML_monthly_largearea.rds")

