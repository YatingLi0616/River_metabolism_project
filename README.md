# Code for: "Environmental drivers of river ecosystem metabolism and their implications for enhanced weathering across the contiguous United States"

this folder contains the code for two parts of the analysis: how two key
predictor variables (nutrient index, discharge skewness) are calculated,
and the random forest / shap / pdp modeling that uses them.

## structure

```
project_root/
├── 1_Calculate_nutrient_index_and_discharge_skewness.R   <- methodology template, see note below
│
├── 2_Machine_learning/
│   ├── 1_RF_DCV_monthly.R     nested cv comparison of feature combinations
│   ├── 2_RF_monthly.R         trains the main rf models + shap importance
│   └── 3_pdp_analysis.R       conditional pdp/ice analysis on those models
│
└── Data/
    └── input/
        ├── ML_monthly.rds                          <- main dataset, used as the example throughout
        ├── ML_daily.rds                             daily-resolution version
        ├── ML_monthly_largearea.rds                  monthly, large-drainage-area sites only
        ├── ML_monthly_smallarea.rds                  monthly, small-drainage-area sites only
        ├── ML_monthly_nutrientconc.rds                monthly, nutrient index from concentration instead of flux
        ├── ML_monthly_nutrientconc_largearea.rds       combination of the two above
        └── ML_monthly_nutrientconc_smallarea.rds       combination of the two above
```

## part 1: `1_Calculate_nutrient_index_and_discharge_skewness.R`

this is a **methodology template, not a runnable script with real data
included**. it documents exactly what raw data is required (USGS N/P
fertilizer and manure loading, a site-to-COMID lookup, and Appling et al.
daily discharge - sources and DOIs are in the script's header) and contains
the unmodified calculation logic used to produce the nutrient index and
discharge skewness columns found in the `ML_*.rds` files. the `<- NULL`
placeholders are meant to be filled in with your own data, formatted as
described in the comments above each one - there's no example data
included.

if you want to calculate the nutrient index from nutrient *concentration*
instead of *flux*, the relevant note is in part 1.6 of the script: download
concentration data instead of loading data, follow the same standardization
approach, and skip the discharge-normalization step.

## part 2: `2_Machine_learning/`

trains random forest models, evaluates feature combinations via nested cv,
and runs conditional pdp/ice analysis.

| file | purpose |
|---|---|
| `1_RF_DCV_monthly.R` | nested (double) cv comparison of 7 feature-set combinations per target, for unbiased performance estimates |
| `2_RF_monthly.R` | trains one rf model per target (80/20 split, 10-fold cv tuning), computes treeshap importance |
| `3_pdp_analysis.R` | conditional pdp/ice analysis on the models from `2_RF_monthly.R` |

`1_RF_DCV_monthly.R` and `2_RF_monthly.R` are independent - run in either
order. `3_pdp_analysis.R` depends on `2_RF_monthly.R` having already
produced the `<target>_main_model.rds` files, so run it last.

### running on the example dataset (`ML_monthly.rds`)

as provided, all three scripts already point at `Data/input/ML_monthly.rds`
- just run them in this order:

```bash
Rscript 1_RF_DCV_monthly.R
Rscript 2_RF_monthly.R
Rscript 3_pdp_analysis.R
```

(or open each in RStudio and click "Source" - no command-line arguments
are required, see the comments at the top of `3_pdp_analysis.R` for
optional overrides)

### running on a different dataset

`ML_monthly.rds` is used as the working example throughout - to run the
same analysis on one of the other six files, edit **two** lines in each
script: the input path, and the output folder name. changing only the
input path will silently overwrite the monthly results, since both
datasets would otherwise write to the same output folder.

**in `2_RF_monthly.R`:**
```r
ML_data <- readRDS("Data/input/ML_monthly.rds")     # <- change to your file
...
output_base  <- "Output/RF/RF_ML_monthly/"          # <- change to match
```

**in `1_RF_DCV_monthly.R`:**
```r
ML_data <- readRDS("Data/input/ML_monthly.rds")     # <- change to your file
...
base_output_dir <- "Output/RF_DCV/RF_ML_monthly/"   # <- change to match
```

**in `3_pdp_analysis.R`:**
```r
default_data_path <- "Data/input/ML_monthly.rds"                       # <- change to your file
default_model_dir <- "Output/RF/RF_ML_monthly/models/"                 # <- must match 2_RF_monthly.R's output_base for that dataset
default_output_dir <- "Output/RF/RF_ML_monthly/pdp_ice_threshold_analysis/"  # <- change to match
```

a consistent naming pattern - just swap `monthly` for whatever's in the
filename - keeps results from each dataset separate:

| input file | suggested output folder suffix |
|---|---|
| `ML_monthly.rds` | `RF_ML_monthly` (the default, shown above) |
| `ML_daily.rds` | `RF_ML_daily` |
| `ML_monthly_largearea.rds` | `RF_ML_monthly_largearea` |
| `ML_monthly_smallarea.rds` | `RF_ML_monthly_smallarea` |
| `ML_monthly_nutrientconc.rds` | `RF_ML_monthly_nutrientconc` |
| `ML_monthly_nutrientconc_largearea.rds` | `RF_ML_monthly_nutrientconc_largearea` |
| `ML_monthly_nutrientconc_smallarea.rds` | `RF_ML_monthly_nutrientconc_smallarea` |

### r package dependencies

`data.table`, `mlr3`, `mlr3learners`, `mlr3tuning`, `paradox`, `ranger`,
`treeshap`, `iml`, `future`, `tictoc`, `MLmetrics`, `foreach`, `doParallel`,
`parallel`