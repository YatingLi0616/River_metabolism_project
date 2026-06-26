# 1_Calculate_average_rivermetabolism.R
#
# purpose:
#   processes Appling et al. 2018 river metabolism data into day-of-year and
#   monthly site-level averages, for both the model outputs (GPP, ER) and
#   the model inputs (depth, light, discharge, water temperature).
#
# data source:
# Appling et al. (2018). The metabolic regimes of 356 rivers in the United States.
# The original dataset was downloaded from the published data release and
# processed to generate the analysis-ready variables used in this study.
# DOI: https://doi.org/10.1038/sdata.2018.292
# 
# inputs:
#   - Data/input/river_meatabolism_data/original_data/Appling_Output.rds
#     (list of per-site data.frames with GPP_daily_mean, ER_daily_mean)
#   - Data/input/river_meatabolism_data/original_data/Appling_Input.rds
#     (list of per-site data.frames with date, depth, light, discharge,
#     temp.water, DO.obs, DO.sat)
#
# outputs (written to Data/river_meatabolism_data/averaged_data/):
#   - Appling_output_average_daily.csv   : GPP/ER averaged by day-of-year
#   - Appling_output_average_monthly.csv : GPP/ER averaged by month
#   - Appling_input_average_daily.csv    : driver variables averaged by day-of-year
#   - Appling_input_average_monthly.csv  : driver variables averaged by month


library(data.table)
library(lubridate)


# 1. process appling output data (GPP, ER) -------------------------------------

appling_output <- readRDS("Data/input/river_meatabolism_data/original_data/Appling_Output.rds")

output_dir <- file.path("Data", "output", "river_meatabolism_data", "averaged_data")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

site_data_list <- list()

for (site_name in names(appling_output)) {
  cat("Processing site:", site_name, "\n")

  dt <- as.data.table(appling_output[[site_name]])

  # extract site id from the name - the part after "nwis_" and before the next "_"
  site_id <- gsub("nwis_([^_]+)_.*", "\\1", site_name)
  site_id <- as.character(site_id)

  dt[, site_id := site_id]
  dt[, year := year(date)]
  dt[, month := month(date)]

  # fixed day-of-year, mapping leap-day to 60.5 so years line up consistently
  dt[, `:=`(doy = ifelse(format(date, "%m-%d") == "02-29",
                         60.5,
                         yday(update(date, year = 2021))))]

  site_data_list[[site_name]] <- dt
}

all_appling_data <- rbindlist(site_data_list)

# remove abnormal data
all_appling_data <- all_appling_data[GPP_daily_mean >= 0 & ER_daily_mean <= 0]
all_appling_data <- all_appling_data[GPP_daily_mean <= 30]

hist(all_appling_data$GPP_daily_mean, main = "GPP Distribution", xlab = "GPP")
hist(all_appling_data$ER_daily_mean, main = "ER Distribution", xlab = "ER")

## daily averages -------------------------------
output_doy <- all_appling_data[, .(
  GPP_avg = mean(GPP_daily_mean, na.rm = TRUE),
  ER_avg = mean(ER_daily_mean, na.rm = TRUE),
  count = .N
), by = .(site_id, doy)]

## monthly averages ------------------------------
output_monthly <- all_appling_data[, .(
  GPP_avg = mean(GPP_daily_mean, na.rm = TRUE),
  ER_avg = mean(ER_daily_mean, na.rm = TRUE),
  count = .N
), by = .(site_id, month)]

cat("Saving averaged results...\n")
fwrite(output_doy, file.path(output_dir, "Appling_output_average_daily.csv"))
fwrite(output_monthly, file.path(output_dir, "Appling_output_average_monthly.csv"))


# 2. process appling input data (depth, light, discharge, water temperature) -------------

appling_input <- readRDS("Data/input/river_meatabolism_data/original_data/Appling_Input.rds")

site_data_list <- list()

for (site_name in names(appling_input)) {
  cat("Processing site:", site_name, "\n")

  dt <- as.data.table(appling_input[[site_name]])

  site_id <- gsub("nwis_([^_]+)_.*", "\\1", site_name)
  dt[, site_id := as.character(site_id)]

  dt[, year := year(date)]
  dt[, month := month(date)]

  dt[, `:=`(doy = ifelse(format(date, "%m-%d") == "02-29",
                         60.5,
                         yday(update(date, year = 2021))))]

  site_data_list[[site_name]] <- dt
}

all_appling_input_data <- rbindlist(site_data_list)

all_appling_input_data <- all_appling_input_data[`temp.water` > -100] # there are very negative temp in the data

## daily averages --------------------------------------------------------------
input_doy <- all_appling_input_data[, .(
  DO_obs_avg = mean(`DO.obs`, na.rm = TRUE),
  DO_sat_avg = mean(`DO.sat`, na.rm = TRUE),
  depth_avg = mean(depth, na.rm = TRUE),
  temp_water_avg = mean(`temp.water`, na.rm = TRUE),
  light_avg = mean(light, na.rm = TRUE),
  discharge_avg = mean(discharge, na.rm = TRUE),
  count = .N
), by = .(site_id, doy)]

## monthly averages ------------------------------------------------------------
input_monthly <- all_appling_input_data[, .(
  DO_obs_avg = mean(`DO.obs`, na.rm = TRUE),
  DO_sat_avg = mean(`DO.sat`, na.rm = TRUE),
  depth_avg = mean(depth, na.rm = TRUE),
  temp_water_avg = mean(`temp.water`, na.rm = TRUE),
  light_avg = mean(light, na.rm = TRUE),
  discharge_avg = mean(discharge, na.rm = TRUE),
  count = .N
), by = .(site_id, month)]

fwrite(input_doy, file.path(output_dir, "Appling_input_average_daily.csv"))
fwrite(input_monthly, file.path(output_dir, "Appling_input_average_monthly.csv"))
