# 3_3_Calculate_TCC.R
#
# purpose:
#   computes tree canopy cover (tcc) statistics for each site's local
#   subcatchment, using zonal statistics (exact_extract) on the nlcd tcc
#   raster.
#
# data source:
# U.S. Department of Agriculture Forest Service.
# National Land Cover Database (NLCD) Tree Canopy Cover (TCC) Science Product
# Available from: https://www.mrlc.gov/data/type/nlcd-tree-canopy-cover
#
# inputs:
#   - Data/input/TCC_data/subcatchments/subcatchment_<site_id>.shp
#     (one polygon shapefile per site, assumed to contain exactly one
#     polygon feature per file)
#   - Data/input/TCC_data/nlcd_tcc_CONUS_2010_v2023-5_wgs84/
#     nlcd_tcc_conus_wgs84_v2023-5_20100101_20101231.tif
#
# outputs:
#   - Data/output/tcc_allsites.csv : one row per site with mean/median/min/
#     max/stdev/count of tcc within the subcatchment
#


library(sf)
library(terra)
library(exactextractr)
library(data.table)

# paths are relative to the project root - run from there, or use absolute paths
subcatchment_dir <- "Data/input/TCC_data/subcatchments/"
tcc_raster_path <- "Data/input/TCC_data/nlcd_tcc_CONUS_2010_v2023-5_wgs84/nlcd_tcc_conus_wgs84_v2023-5_20100101_20101231.tif"

cat("=== tcc processing for all subcatchments ===\n\n")

# load tcc raster once
tcc_raster <- rast(tcc_raster_path)

# get all subcatchment files
subcatchment_files <- list.files(subcatchment_dir, pattern = "^subcatchment_.*\\.shp$", full.names = TRUE)
if (length(subcatchment_files) == 0) {
  stop("no subcatchment files found!")
}

# pre-allocate results list
results_list <- vector("list", length(subcatchment_files))

# process each subcatchment
for (i in seq_along(subcatchment_files)) {
  subcatchment_file <- subcatchment_files[i]
  site_id <- gsub("^.*/subcatchment_(.*)\\.shp$", "\\1", subcatchment_file)

  cat("processing", i, "of", length(subcatchment_files), "- site:", site_id, "\n")

  result <- tryCatch({
    subcatchment <- st_read(subcatchment_file, quiet = TRUE)

    # always reproject to the raster's crs - a no-op if already matching,
    # and avoids comparing an sf crs object to a terra crs string directly
    subcatchment <- st_transform(subcatchment, crs(tcc_raster))

    tcc_values <- exact_extract(tcc_raster, subcatchment,
                                c('mean', 'median', 'min', 'max', 'stdev', 'count'))

    tcc_stats <- data.table(
      site_id = site_id,
      mean = tcc_values$mean,
      median = tcc_values$median,
      min = tcc_values$min,
      max = tcc_values$max,
      stdev = tcc_values$stdev,
      count = tcc_values$count
    )

    cat("  done - mean tcc:", round(tcc_stats$mean, 2), "% | pixels:", tcc_stats$count, "\n")

    tcc_stats
  }, error = function(e) {
    cat("  error processing site", site_id, ":", e$message, "\n")

    data.table(
      site_id = site_id,
      mean = NA_real_,
      median = NA_real_,
      min = NA_real_,
      max = NA_real_,
      stdev = NA_real_,
      count = NA_integer_
    )
  })

  results_list[[i]] <- result

  # progress update every 50 sites
  if (i %% 50 == 0) {
    cat("--- processed", i, "sites so far ---\n")
  }
}

# combine all results
final_results <- rbindlist(results_list)

# make sure site_id is character before saving
final_results[, site_id := as.character(site_id)]

# create output directory if needed
output_dir <- dirname(output_file)
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

fwrite(final_results, "Data/output/tcc_allsites.csv")
