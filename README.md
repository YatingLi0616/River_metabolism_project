# Code for: Environmental drivers of river ecosystem metabolism and their implications for enhanced weathering across the contiguous United States

## overview
end-to-end pipeline for modeling river metabolism (GPP, ER, NEP) as a
function of physical, chemical, and watershed drivers: compiles per-site
data from several sources into one model-ready table, then runs random
forest modeling with treeshap importance, nested cross-validation, and
conditional pdp/ice threshold analysis.

three stages, each with more detail in its own section below:

```
stage 1: data compilation   ->  builds Data/output/ML_data/ML_monthly.rds
stage 2: land cover (HPRC)  ->  builds Data/output/NLCD_data/landcover_allsites.csv
                                 (feeds into stage 1's final merge step)
stage 3: rf / shap / pdp    ->  trains models and analyzes them, using ML_monthly.rds
```

## repository structure

```
project_root/
├── Data/
│   ├── input/                          (raw data - see "stage 1 inputs" below)
│   └── output/                         (everything else is generated)
│       ├── river_metabolism_data/
│       ├── USGS_data/
│       ├── NLCD_data/landcover_allsites.csv
│       ├── nutrient_index.csv
│       ├── discharge_skewness.csv
│       ├── tcc_allsites.csv
│       └── ML_data/                     <- stage 1 final output, stage 3 input
│
├── 1_Calculate_average_rivermetabolism.R
├── 2_Calculate_averge_USGS.R
├── 3_1_Nutrient_index.R
├── 3_2_Discharge_skewness.R
├── 3_3_Calculate_TCC.R
├── 3_4_Calculate_landcover/             <- stage 2, run separately on HPRC
│   ├── run_parallel.slurm
│   ├── create_batches.sh
│   ├── extract_and_reproject.sh
│   ├── process_single_site.sh
│   └── merge_results.sh
├── 4_Complie_data.R                     <- run last in stage 1
│
├── 5_Machine_learning/                  <- stage 3, run on HPRC
│   ├── RF_monthly.R / RF_monthly.slurm
│   ├── RF_DCV_monthly.R / RF_DCV_monthly.slurm
│   └── pdp_analysis_parallel.R / pdp_parallel.slurm
│
└── README.md
```

note: the `Output/` tree that stage 3 writes to (results, models, pdp
analysis) is a separate top-level folder from `Data/output/` - see stage 3
below for its actual structure.

---

## stage 1: data compilation

builds the model-ready dataset (`ML_monthly.rds`) by compiling river
metabolism, water chemistry, nutrient loading, discharge statistics, and
tree canopy cover for each site. stage 2 (land cover) feeds into the last
step of this stage but is run separately - see its own section below.

### pipeline

```
1_Calculate_average_rivermetabolism.R   appling GPP/ER/drivers -> daily & monthly averages
2_Calculate_averge_USGS.R               usgs water chemistry (pH, alk, ...) -> daily & monthly averages
3_1_Nutrient_index.R                    usgs fertilizer/manure loading + nldi upstream sum -> nutrient index
3_2_Discharge_skewness.R                daily discharge -> annual l-moments, averaged across years
3_3_Calculate_TCC.R                     nlcd tree canopy cover -> per-site zonal stats
3_4_Calculate_landcover/                nlcd land cover -> per-site class proportions (stage 2, own README inside)
4_Complie_data.R                        merges everything above into ML_monthly.rds
```

scripts 1, 2, 3_1, 3_2, 3_3, and stage 2 (`3_4_Calculate_landcover/`) are
independent of each other and can run in any order, or in parallel.
`4_Complie_data.R` is the only one that depends on all of their outputs, so
it runs last.

```
run order:
1. 1_Calculate_average_rivermetabolism.R   \
2. 2_Calculate_averge_USGS.R                |  independent - any order,
3. 3_1_Nutrient_index.R                     |  or in parallel
4. 3_2_Discharge_skewness.R                 |
5. 3_3_Calculate_TCC.R                      |
6. 3_4_Calculate_landcover/  (on HPRC)      /
7. 4_Complie_data.R                        <- run last, after all of the above
```

**a note on `2_Calculate_averge_USGS.R`**: this script processes one water
chemistry parameter per run - set `param_name` near the top (`"alk"`,
`"pH"`, `"TN"`, `"TP"`, ...) and rerun for each parameter you need.
`4_Complie_data.R` only pulls in whichever parameters are listed in its own
`vars_to_keep` (currently `pH` and `alk`), so you only need to run this
script for the parameters you actually plan to use.

### stage 1 inputs

| path | description |
|---|---|
| `Data/input/river_metabolism_data/Appling_Output.rds` | appling et al. 2018 metabolism outputs (GPP, ER), per site |
| `Data/input/river_metabolism_data/Appling_Input.rds` | appling et al. 2018 model inputs (depth, light, discharge, temp), per site |
| `Data/input/USGS_data/<param>_original.csv` | usgs water chemistry, one file per parameter |
| `Data/input/nutrient_data/ag_*.csv`, `de_*.csv` | usgs fertilizer/manure loading by COMID (2002/2007/2012/2017) |
| `Data/input/nutrient_data/site_COMID.csv` | site_id to COMID lookup |
| `Data/input/TCC_data/subcatchments/subcatchment_<site_id>.shp` | per-site subcatchment polygons |
| `Data/input/TCC_data/nlcd_tcc_.../*.tif` | nlcd tree canopy cover raster |
| `Data/input/appling_data_06202024_Taylor.csv` | Maavara et al. 2025 data (stream order, upstream area, river width) |
| nlcd raster + basin shapefiles | see stage 2 inputs, below |

two intermediate files are also required directly by later scripts in this
stage, not just raw inputs:

| path | produced by | read by |
|---|---|---|
| `Data/output/river_metabolism_data/Appling_input_average_monthly.csv` | script 1 | `3_1_Nutrient_index.R`, `4_Complie_data.R` |
| `Data/output/river_metabolism_data/Appling_output_average_monthly.csv` | script 1 | `4_Complie_data.R` |

make sure script 1 finishes (and writes to this exact path) before running
either of those.

### stage 1 outputs

| script | output |
|---|---|
| `1_Calculate_average_rivermetabolism.R` | `Data/output/river_metabolism_data/Appling_{input,output}_average_{daily,monthly}.csv` |
| `2_Calculate_averge_USGS.R` | `Data/output/USGS_data/<param>_{daily,monthly}.csv` |
| `3_1_Nutrient_index.R` | `Data/output/nutrient_index.csv` |
| `3_2_Discharge_skewness.R` | `Data/output/discharge_skewness.csv` |
| `3_3_Calculate_TCC.R` | `Data/output/tcc_allsites.csv` |
| `3_4_Calculate_landcover/` (stage 2) | `Data/output/NLCD_data/landcover_allsites.csv` |
| `4_Complie_data.R` | `Data/output/ML_data/ML_{daily,monthly}_{smallarea, largearea}.rds` - final model input |

### stage 1 r package dependencies

`data.table`, `lubridate`, `nhdplusTools`, `lmomco`, `sf`, `terra`,
`exactextractr`, `seacarb`

`3_1_Nutrient_index.R` queries the USGS NLDI web service (via
`nhdplusTools::navigate_nldi()`), so it needs internet access and can take a
while to run for a large number of sites.

---

## stage 2: land cover (`3_4_Calculate_landcover/`)

computes the proportion of each nlcd land cover class within each site's
upstream basin. **run separately on TAMU HPRC**, since it's a SLURM-based
raster pipeline rather than a plain R script.

### stage 2 inputs

| path | description |
|---|---|
| `Data/input/NLCD_data/Annual_NLCD_LndCov_2010_CU_C1V1/Annual_NLCD_LndCov_2010_CU_C1V1.tif` | nlcd raster (check the real file extension - if it's `.tiff` not `.tif`, update the one line in `extract_and_reproject.sh`) |
| `Data/input/NLCD_data/upstream_basin/*.shp` | basin shapefiles, one per site (works whether named `basin_<site_id>.shp` or `<site_id>.shp`) |

### stage 2 run order

all paths below are relative to `3_4_Calculate_landcover/`.

**1. extract and reproject all classes** (run once)

```bash
sbatch run_parallel.slurm
```

wait for this to finish before moving on - everything downstream needs the
reprojected rasters it produces. worth testing on one class first
(`bash extract_and_reproject.sh 11`) to confirm the raster path is correct
before launching all 16 in parallel.

**2. generate batch scripts** (run once)

```bash
bash create_batches.sh
```

counts how many `.shp` files are in `upstream_basin/` and writes out
`nlcd_batch1.sbatch`, `nlcd_batch2.sbatch`, etc. (50 sites per batch by
default - change `batch_size` at the top of the script for a different size).

**3. submit each generated batch**

```bash
sbatch nlcd_batch1.sbatch
sbatch nlcd_batch2.sbatch
# ... one per file create_batches.sh made
```

these can run at the same time. each one crops every class raster to each
site's basin and counts pixels.

**4. merge results** (run once, after all batches finish)

```bash
bash merge_results.sh
```

produces `Data/output/NLCD_data/landcover_allsites.csv` and prints a quick
sanity check (mean/min/max total_proportion, how many sites came out at
zero - that usually means the crop or pixel count failed for that site and
is worth checking the corresponding `debug_<site_id>.log`).

### stage 2 outputs

| path | description |
|---|---|
| `Data/output/NLCD_data/nlcd_classes/` | binary class masks (one per class code) |
| `Data/output/NLCD_data/nlcd_classes_wgs84/` | same masks, reprojected to wgs84 |
| `Data/output/NLCD_data/landcover_proportions/` | one temp csv + debug log per site |
| `Data/output/NLCD_data/landcover_allsites.csv` | final merged table, one row per site - read directly by `4_Complie_data.R` |

---

## stage 3: random forest / shap / pdp (`5_Machine_learning/`)

random forest modeling of GPP, ER, and NEP, with treeshap importance,
nested cross-validation feature-combination comparison, and conditional
pdp/ice threshold analysis. all three files below live in
`5_Machine_learning/`.

### files

| file | purpose |
|---|---|
| `RF_monthly.R` / `RF_monthly.slurm` | trains one rf model per target (80/20 split, 10-fold cv tuning), computes treeshap importance |
| `RF_DCV_monthly.R` / `RF_DCV_monthly.slurm` | nested (double) cv comparison of 7 feature-set combinations per target, for unbiased performance estimates |
| `pdp_analysis_parallel.R` / `pdp_parallel.slurm` | conditional pdp/ice analysis on the models from `RF_monthly.R`, run as a 3-way slurm array job (one task per target) |

`RF_monthly.R` and `RF_DCV_monthly.R` are independent of each other - both
read the same input data but answer different questions (final model +
importance, vs. feature-set comparison), and write to **separate** output
trees (see below). `pdp_analysis_parallel.R` depends on `RF_monthly.R`
having already produced the `<target>_main_model.rds` files - it reads
them from `RF_monthly.R`'s output tree specifically, not `RF_DCV_monthly.R`'s.

### stage 3 inputs

```
Data/output/ML_data/ML_monthly.rds
```

this is the file produced at the end of stage 1 (`4_Complie_data.R`'s
output) - a data.table with columns `GPP`, `ER`, `NEP`, and the predictor
columns: `light_eff`, `disch_skew`, `DIC`, `nutrient_index`, `urban`,
`forest`, `wetland`, `dryland`, `agriculture`.

### stage 3 run order

```
1. RF_monthly.R             (independent)
2. RF_DCV_monthly.R         (independent - can run any time, including in parallel with step 1)
3. pdp_analysis_parallel.R  (depends on step 1's model files)
```

```bash
sbatch RF_monthly.slurm
sbatch RF_DCV_monthly.slurm
# after RF_monthly.slurm finishes:
sbatch pdp_parallel.slurm
```

### stage 3 outputs

`RF_monthly.R` and `RF_DCV_monthly.R` write to **separate** trees under
`Output/` - they don't share a folder, even though they read the same
input data. `pdp_analysis_parallel.R` writes into `RF_monthly.R`'s tree,
since it depends on the models there.

```
Output/
├── RF/RF_ML_monthly/                         <- from RF_monthly.R
│   ├── results/
│   │   ├── <target>_evaluation_predictions.csv
│   │   ├── <target>_treeshap_importance.csv
│   │   ├── <target>_shap_dependency.csv
│   │   └── overall_summary.csv
│   ├── models/
│   │   └── <target>_main_model.rds           <- read by pdp_analysis_parallel.R
│   └── pdp_ice_threshold_analysis/            <- from pdp_analysis_parallel.R
│       └── ModeB_<target>_<feature_x>_by_<feature_gate>_thr<threshold>/
│           ├── PDP_conditional.csv
│           ├── PDP_gate_overall.csv
│           └── PDP_2D.csv
│
└── RF_DCV/RF_ML_monthly/                     <- from RF_DCV_monthly.R
    ├── <target>/<combination>/
    │   └── <target>_double_cv_results.rds
    ├── feature_combination_summary.csv
    └── all_feature_combination_results.rds
```

### before running stage 3

each `.slurm` file has a placeholder you need to fill in:

```bash
project_dir="your/project/root"
```

each `.R` file has an optional library-path override, only needed if your r
packages aren't on the default library path (e.g. a custom hpc install):

```r
custom_lib_path <- ""   # set to your library path if needed, otherwise leave blank
```

### stage 3 r package dependencies

`data.table`, `mlr3`, `mlr3learners`, `mlr3tuning`, `paradox`, `ranger`,
`treeshap`, `iml`, `future`, `tictoc`, `MLmetrics`, `foreach`, `doParallel`
