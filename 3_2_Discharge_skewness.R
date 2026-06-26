# 3_2_Discharge_skewness.R
#
# purpose:
#   computes site-level discharge l-moments (mean, l-cv, l-skewness,
#   l-kurtosis) from daily discharge. for each site, computes l-moments
#   per calendar year, keeps years meeting a minimum daily-coverage
#   threshold, then averages across all valid years.
#   requirements: each year must have >= 50% coverage; site must have
#   at least 1 valid year.
#
# inputs:
#   - Data/input/river_meatabolism_data/Appling_Input.rds
#     (list of per-site data.frames with date, discharge)
#
# outputs:
#   - Data/output/discharge_skewness.csv : one row per site with averaged
#     l-moments, years used, and mean coverage
#

library(data.table)
library(lmomco)
library(lubridate)


# 1. functions -----------------------------------------------------------------

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


# 2. apply to all sites --------------------------------------------------------

input_data <- readRDS("Data/input/river_meatabolism_data/Appling_Input.rds")

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


# 3. clean and save ------------------------------------------------------------

flow_metrics_final <- flow_metrics_yearly[filter_reason == "passed"]

flow_metrics_final[, `:=`(
    disch_mean = round(disch_mean, 3),
    disch_cv = round(disch_cv, 3),
    disch_skew = round(disch_skew, 3),
    disch_kurt = round(disch_kurt, 3),
    mean_coverage = round(mean_coverage, 3)
  )]

fwrite(flow_metrics_final, "Data/output/discharge_skewness.csv")
