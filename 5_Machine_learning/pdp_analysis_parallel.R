# pdp_analysis_parallel.R
#
# purpose:
#   conditional pdp / ice threshold analysis for the random forest models
#   produced by RF_monthly.R. for each target (GPP, ER, NEP) and a set of
#   predefined feature/gate/threshold combinations, splits observations into
#   low/high groups by the gate feature and computes:
#     1. conditional 1d pdp for feature_x, separately for the low and high groups
#     2. overall 1d pdp for the gate feature
#     3. 2d pdp for feature_x x feature_gate
#   combinations within a target run in parallel across the available cpus.
#
# inputs:
#   - <data_path> : rds file matching the data used to train the models
#     (data.table with the feature columns and GPP/ER/NEP target columns)
#   - <model_dir> : directory containing <target>_main_model.rds files,
#     produced by RF_monthly.R
#
# outputs (written under <output_dir>/ModeB_<target>_<feature_x>_by_<feature_gate>_thr<threshold>/):
#   - PDP_conditional.csv : 1d pdp for feature_x, split by gate threshold
#   - PDP_gate_overall.csv : 1d pdp for the gate feature, all data
#   - PDP_2D.csv : 2d pdp for feature_x x feature_gate
#
# usage:
#   Rscript pdp_analysis_parallel.R <data_path> <model_dir> <output_dir> [target]
#   [target] is optional - one of GPP/ER/NEP, or omit/pass ALL to run all three
#   (see pdp_parallel.slurm for the cluster array-job version)


# 1. setup ---------------------------------------------------------------------

# set this if your r packages live in a non-default location (e.g. an hpc
# cluster library path). leave blank to use the default library path.
custom_lib_path <- ""
if (nzchar(custom_lib_path)) .libPaths(custom_lib_path)

library(data.table)
library(ranger)
library(iml)
library(foreach)
library(doParallel)

args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
  stop("Usage: Rscript pdp_analysis_parallel.R <data_path> <model_dir> <output_dir> [target]")
}

data_path <- args[1]
model_dir <- args[2]
output_dir <- args[3]
target_arg <- ifelse(length(args) >= 4, args[4], "ALL")

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# parallel setup: one worker per combination, within a target
n_cores <- as.integer(Sys.getenv("SLURM_CPUS_PER_TASK", unset = "1"))
n_cores <- max(1, n_cores - 1)
cat("Using", n_cores, "parallel cores\n")

cl <- makeCluster(n_cores)
registerDoParallel(cl)
on.exit(stopCluster(cl))

if (nzchar(custom_lib_path)) clusterEvalQ(cl, .libPaths(custom_lib_path))

# 2. fixed parameters ----------------------------------------------------------

feature_cols <- c("light_eff", "disch_skew",
                  "DIC", "nutrient_index",
                  "urban", "dryland", "forest", "wetland", "agriculture")

grid_size_1d <- 100
grid_size_2d <- 50
seed <- 616
set.seed(seed)

# 3. load data -----------------------------------------------------------------

ML_data <- readRDS(data_path)
ML_dt <- as.data.table(ML_data)

X <- as.data.frame(ML_dt[, ..feature_cols])

# 4. prediction function (passed to iml's Predictor) ---------------------------

predict_function <- function(model, newdata) {
  predict(model, data = newdata)$predictions
}

# 5. core function: run one feature/gate/threshold combination -----------------
#    (called inside foreach, so it must be self-contained)

run_one_combo <- function(combo,
                          target,
                          rf_model,
                          X,
                          y,
                          output_dir,
                          grid_size_1d,
                          grid_size_2d,
                          run_plot1,
                          run_plot2,
                          run_plot3) {

  predict_function <- function(model, newdata) {
    predict(model, data = newdata)$predictions
  }

  feature_x <- combo$feature_x
  feature_gate <- combo$feature_gate
  threshold <- combo$threshold

  combo_tag <- paste0(target, "_", feature_x, "_by_",
                       feature_gate, "_thr", threshold)
  save_dir_B <- file.path(output_dir, paste0("ModeB_", combo_tag))

  cat("  [START]", combo_tag, "\n")

  # split indices by the gate feature's threshold
  low_idx <- which(X[[feature_gate]] <  threshold)
  high_idx <- which(X[[feature_gate]] >= threshold)

  if (length(low_idx) < 10 | length(high_idx) < 10) {
    cat("  [SKIP] Group too small:", combo_tag, "\n")
    return(paste("SKIPPED:", combo_tag))
  }

  predictor_full <- Predictor$new(
    model = rf_model, data = X, y = y,
    predict.fun = predict_function
  )
  predictor_low <- Predictor$new(
    model = rf_model,
    data  = X[low_idx, , drop = FALSE],
    y     = y[low_idx],
    predict.fun = predict_function
  )
  predictor_high <- Predictor$new(
    model = rf_model,
    data = X[high_idx, , drop = FALSE],
    y = y[high_idx],
    predict.fun = predict_function
  )

  if (!dir.exists(save_dir_B)) dir.create(save_dir_B, recursive = TRUE)

  # 1. conditional pdp: feature_x, split into low/high groups by the gate
  if (run_plot1) {
    pdp_low <- FeatureEffect$new(predictor_low,  feature = feature_x,
                                 method = "pdp", grid.size = grid_size_1d)
    pdp_high <- FeatureEffect$new(predictor_high, feature = feature_x,
                                  method = "pdp", grid.size = grid_size_1d)

    pdp_combined <- rbind(
      transform(pdp_low$results,  group = "low",
                group_label = sprintf("Low (< %.2f)",  threshold)),
      transform(pdp_high$results, group = "high",
                group_label = sprintf("High (\u2265 %.2f)", threshold))
    )
    colnames(pdp_combined)[1:2] <- c("feature_value", "prediction")
    fwrite(pdp_combined, file.path(save_dir_B, "PDP_conditional.csv"))
  }

  # 2. overall pdp for the gate feature (all data, not split)
  if (run_plot2) {
    pdp_gate <- FeatureEffect$new(predictor_full, feature = feature_gate,
                                  method = "pdp", grid.size = grid_size_1d)
    pdp_gate_data <- pdp_gate$results
    colnames(pdp_gate_data)[1:2] <- c("feature_value", "prediction")
    fwrite(pdp_gate_data, file.path(save_dir_B, "PDP_gate_overall.csv"))
  }

  # 3. 2d pdp: feature_x x feature_gate
  if (run_plot3) {
    pdp_2d <- FeatureEffect$new(
      predictor_full,
      feature   = c(feature_x, feature_gate),
      method    = "pdp",
      grid.size = c(grid_size_2d, grid_size_2d)
    )
    pdp_2d_data <- pdp_2d$results
    colnames(pdp_2d_data)[1:3] <- c("feature_x", "feature_gate", "prediction")
    fwrite(pdp_2d_data, file.path(save_dir_B, "PDP_2D.csv"))
  }

  cat("  [DONE]", combo_tag, "\n")
  return(paste("DONE:", combo_tag))
}

# 6. define targets and combinations to run ------------------------------------

all_targets <- c("GPP", "ER", "NEP")

targets_to_run <- if (target_arg %in% all_targets) target_arg else all_targets

combos_B <- list(
  list(feature_x = "nutrient_index", feature_gate = "light_eff", threshold = 400),
  list(feature_x = "nutrient_index", feature_gate = "disch_skew", threshold = 0.45),
  list(feature_x = "light_eff", feature_gate = "disch_skew", threshold = 0.45),
  list(feature_x = "DIC", feature_gate = "light_eff", threshold = 400),
  list(feature_x = "DIC", feature_gate = "disch_skew",  threshold = 0.45),
  list(feature_x = "nutrient_index", feature_gate = "DIC", threshold = 2)
)

run_plot1 <- TRUE
run_plot2 <- TRUE
run_plot3 <- TRUE

# 7. main loop: one target at a time, combinations run in parallel -------------

for (target in targets_to_run) {

  cat("Target:", target, "\n")

  model_file <- file.path(model_dir, paste0(target, "_main_model.rds"))
  if (!file.exists(model_file)) {
    cat("Model not found, skipping:", model_file, "\n")
    next
  }

  rf_model <- readRDS(model_file)
  y <- ML_dt[[target]]
  cat("Model loaded. Running", length(combos_B), "combos on", n_cores, "cores\n")

  for (combo in combos_B) {
    combo_tag <- paste0(target, "_", combo$feature_x, "_by_",
                         combo$feature_gate, "_thr", combo$threshold)
    save_dir_B <- file.path(output_dir, paste0("ModeB_", combo_tag))
    if (!dir.exists(save_dir_B)) dir.create(save_dir_B, recursive = TRUE)
  }

  results <- foreach(
    combo = combos_B,
    .packages = c("data.table", "ranger", "iml"),
    .export = c("run_one_combo"),
    .errorhandling = "pass"
  ) %dopar% {
    if (nzchar(custom_lib_path)) .libPaths(custom_lib_path)
    run_one_combo(
      combo = combo,
      target = target,
      rf_model = rf_model,
      X = X,
      y = y,
      output_dir = output_dir,
      grid_size_1d = grid_size_1d,
      grid_size_2d = grid_size_2d,
      run_plot1 = run_plot1,
      run_plot2 = run_plot2,
      run_plot3 = run_plot3
    )
  }

  cat("\nResults for target", target, ":\n")
  for (r in results) {
    if (inherits(r, "error")) {
      cat("  [ERROR]", conditionMessage(r), "\n")
    } else {
      cat(" ", r, "\n")
    }
  }
}
