# 2_Calculate_averge_USGS.R
#
# purpose:
#   processes one USGS water chemistry parameter at a time into day-of-year
#   and monthly site-level averages. edit param_name and rerun for each
#   parameter you need (alk, pH, TN, TP, tds, ...).
#
# data source:
# U.S. Geological Survey (USGS) Water Quality Portal (WQP). 
# raw data were processed to obtain the variables used in this study 
#
# inputs:
#   - Data/input/USGS_data/<param_name>_original.csv
#
# outputs (written to Data/output/USGS_data/):
#   - <param_name>_daily.csv   : value averaged by site and day-of-year
#   - <param_name>_monthly.csv : value averaged by site and month
#

library(data.table)
library(lubridate)


# 1. set which parameter to process --------------------------------------------

param_name <- "alk"  # change this manually for each parameter

dt <- fread(file.path("Data", "input", "USGS_data", paste0(param_name, "_original.csv")))

dt[, stream_date := as.Date(stream_date)]
dt[, `:=`(stream_month = month(stream_date))]

# fixed day-of-year, mapping leap-day to 60.5 so years line up consistently
dt[, stream_doy := ifelse(
  format(stream_date, "%m-%d") == "02-29",
  60.5,
  yday(update(stream_date, year = 2021)) # a non-leap reference year
)]

output_dir <- file.path("Data", "output", "USGS_data")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)


# 2. daily averages ------------------------------------------------------------

dt_doy <- copy(dt)
dt_doy[, value := mean(value), by = c("site_no", "stream_doy")]

# count how many days of data went into each site/doy average
dt_doy[, doy_day_count := uniqueN(stream_date),
       by = c("site_no", "stream_doy")]

dt_doy[, stream_date := NULL]
dt_doy[, stream_month := NULL]
dt_doy[, stream_season := NULL]

dt_doy <- unique(dt_doy, by = c("site_no", "stream_doy"))

fwrite(dt_doy, file.path(output_dir, paste0(param_name, "_daily.csv")))


# 3. monthly averages ----------------------------------------------------------

dt_month <- copy(dt)
dt_month[, value := mean(value), by = c("site_no", "stream_month")]

# count how many days of data went into each site/month average
dt_month[, month_day_count := uniqueN(stream_date),
         by = c("site_no", "stream_month")]

dt_month[, stream_date := NULL]
dt_month[, stream_doy := NULL]
dt_month[, stream_season := NULL]

dt_month <- unique(dt_month, by = c("site_no", "stream_month"))

fwrite(dt_month, file.path(output_dir, paste0(param_name, "_monthly.csv")))
