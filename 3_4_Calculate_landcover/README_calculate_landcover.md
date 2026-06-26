# nlcd land cover proportion pipeline (used in TAMU HPRC)

computes the proportion of each nlcd land cover class within each site's
upstream basin.

## input data you need

- nlcd raster:
  `Data/input/NLCD_data/Annual_NLCD_LndCov_2010_CU_C1V1/Annual_NLCD_LndCov_2010_CU_C1V1.tiff`
  (check the real file extension - if it's actually `.tif` not `.tiff`,
  fix that one line in `extract_and_reproject.sh`)

- basin shapefiles, one per site:
  `Data/input/NLCD_data/upstream_basin/*.shp`
  (works whether files are named `basin_<site_id>.shp` or `<site_id>.shp`)

## what gets created

- `Data/output/NLCD_data/nlcd_classes/` - binary class masks (one per class code)
- `Data/output/NLCD_data/nlcd_classes_wgs84/` - same masks, reprojected to wgs84
- `Data/output/NLCD_data/landcover_proportions/` - one temp csv + debug log per site
- `Data/output/landcover_allsites.csv` - final merged table, one row per site

## run order

### 1. extract and reproject all classes (run once)

```bash
sbatch run_parallel.slurm
```

wait for this to finish before moving on - everything downstream needs the
reprojected rasters it produces.

### 2. generate batch scripts (run once)

```bash
bash create_batches.sh
```

this counts how many `.shp` files are in `upstream_basin/` and writes out
`nlcd_batch1.sbatch`, `nlcd_batch2.sbatch`, etc. (50 sites per batch by
default - change `batch_size` at the top of the script if you want a
different size).

### 3. submit each generated batch

```bash
sbatch nlcd_batch1.sbatch
sbatch nlcd_batch2.sbatch
# ... one per file create_batches.sh made
```

these can run at the same time. each one crops every class raster to each
site's basin and counts pixels.

### 4. merge results (run once, after all batches finish)

```bash
bash merge_results.sh
```

produces `Data/output/landcover_allsites.csv` and prints a quick sanity
check (mean/min/max total_proportion, how many sites came out at zero -
that usually means the crop or pixel count failed for that site and is
worth checking the corresponding `debug_<site_id>.log`).

## before running the full batch

test `extract_and_reproject.sh` on just one class first
(`bash extract_and_reproject.sh 11`) to confirm the new raster path is
correct before launching all 16 in parallel.
