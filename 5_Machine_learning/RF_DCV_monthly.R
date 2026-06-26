# RF_DCV_monthly.R
#
# purpose:
#   nested (double) cross-validation comparison of feature-set combinations
#   for predicting GPP, ER, and NEP with a random forest (mlr3 + ranger).
#   for each target, runs 7 feature combinations (physical, chemical,
#   watershed, and their unions) through a 5-fold outer cv with a 10-fold
#   inner cv grid search for hyperparameter tuning, to get an unbiased
#   estimate of test performance for each combination.
#
# inputs:
#   - data/input/ml_monthly.rds : data.table with columns GPP, ER, NEP, and
#     the predictor columns referenced in physical/chemical/watershed_features
#
# outputs:
#   - output/ml_monthly/<target>/<combination>/<target>_double_cv_results.rds
#   - output/ml_monthly/feature_combination_summary.csv
#   - output/ml_monthly/all_feature_combination_results.rds
#
# usage:
#   Rscript RF_DCV_monthly.R
#   (intended to be run from the project root - see RF_DCV_monthly.slurm)


# 1. setup ---------------------------------------------------------------------

# set this if your r packages live in a non-default location (e.g. an hpc
# cluster library path). leave blank to use the default library path.
custom_lib_path <- ""
if (nzchar(custom_lib_path)) .libPaths(custom_lib_path)

library(data.table)
library(mlr3)
library(mlr3learners)
library(mlr3tuning)
library(paradox)
library(future)
library(tictoc)
library(MLmetrics)

# this script assumes it is run from the project root (see RF_DCV_monthly.slurm,
# which cd's there before calling Rscript). uncomment and edit if running
# interactively from elsewhere:
# setwd("your/project/root")

n_cores <- as.numeric(Sys.getenv("SLURM_CPUS_PER_TASK", 1))
future::plan(future::multisession, workers = max(1, n_cores - 1))

base_output_dir <- "Output/RF_DCV/RF_ML_monthly/"
if (!dir.exists(base_output_dir)) dir.create(base_output_dir, recursive = TRUE)

# 2. load data and define feature combinations ---------------------------------

ML_data <- readRDS("Data/output/ML_data/ML_monthly.rds")

physical_features  <- c("light_eff", "disch_skew")
chemical_features  <- c("DIC", "nutrient_index")
watershed_features <- c("urban", "forest", "wetland", "dryland", "agriculture")

combo_template <- list(
  "physical" = physical_features,
  "chemical" = chemical_features,
  "watershed" = watershed_features,
  "physical_chemical" = c(physical_features, chemical_features),
  "physical_watershed" = c(physical_features, watershed_features),
  "chemical_watershed" = c(chemical_features, watershed_features),
  "all_combined" = c(physical_features, chemical_features, watershed_features)
)

# all three targets share the same combinations
feature_combinations <- list(GPP = combo_template, ER = combo_template, NEP = combo_template)

# 3. double cv function --------------------------------------------------------

run_double_cv <- function(target_var, features, combination_name, n_cores, original_seed = 123) {

  output_dir <- file.path(base_output_dir, target_var, combination_name)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  target_data <- ML_data[, c(target_var, features), with = FALSE]
  task_full   <- TaskRegr$new(id = paste0(target_var, "_full"),
                              backend = target_data, target = target_var)

  set.seed(original_seed)
  outer_cv <- rsmp("cv", folds = 5)
  outer_cv$instantiate(task_full)

  param_set <- ps(
    num.trees = p_fct(c(100, 200, 400, 600, 800, 1000)),
    min.node.size = p_fct(c(2, 4, 6, 8, 10))
  )

  outer_fold_results <- vector("list", outer_cv$iters)

  tic(paste(target_var, combination_name))

  for (outer_fold in seq_len(outer_cv$iters)) {
    fold_seed <- original_seed + outer_fold
    set.seed(fold_seed)
    cat(sprintf("  Outer fold %d/%d\n", outer_fold, outer_cv$iters))

    train_set <- outer_cv$train_set(outer_fold)
    test_set <- outer_cv$test_set(outer_fold)

    outer_train_task <- task_full$clone()$filter(train_set)

    # num.threads = 1 here is intentional: future already parallelizes across
    # the inner cv's hyperparameter combinations, so each individual fit
    # should stay single-threaded to avoid oversubscribing cpus on a shared node
    learner <- lrn("regr.ranger", predict_type = "response",
                   seed = fold_seed,
                   num.threads = 1)

    tuning_instance <- TuningInstanceBatchSingleCrit$new(
      task = outer_train_task,
      learner = learner,
      resampling = rsmp("cv", folds = 10),
      measure = msr("regr.mse"),
      search_space = param_set,
      terminator = trm("none")
    )
    tnr("grid_search")$optimize(tuning_instance)
    best_params <- tuning_instance$result_learner_param_vals

    # this is a single fit, not running alongside other concurrent fits, so
    # it can use the full core allocation
    final_learner <- lrn("regr.ranger", predict_type = "response",
                         seed = fold_seed,
                         num.threads = n_cores)
    final_learner$param_set$values <- best_params
    final_learner$train(outer_train_task)

    train_pred <- final_learner$predict(outer_train_task)
    test_pred  <- final_learner$predict(task_full$clone()$filter(test_set))

    outer_fold_results[[outer_fold]] <- list(
      fold = outer_fold,
      seed = fold_seed,
      best_params = best_params,
      train_predictions = data.frame(actual = train_pred$truth, predicted = train_pred$response),
      test_predictions = data.frame(actual = test_pred$truth,  predicted = test_pred$response),
      metrics = list(
        train_r2 = R2_Score(train_pred$response, train_pred$truth),
        train_rmse = RMSE(train_pred$response,     train_pred$truth),
        test_r2 = R2_Score(test_pred$response,  test_pred$truth),
        test_rmse = RMSE(test_pred$response,      test_pred$truth)
      )
    )
  }

  toc()

  saveRDS(outer_fold_results, file.path(output_dir, paste0(target_var, "_double_cv_results.rds")))

  # aggregate metrics across outer folds
  train_r2_vals <- sapply(outer_fold_results, function(x) x$metrics$train_r2)
  test_r2_vals <- sapply(outer_fold_results, function(x) x$metrics$test_r2)

  return(list(
    target = target_var,
    combination = combination_name,
    n_features = length(features),
    train_r2_mean = mean(train_r2_vals),
    train_r2_sd = sd(train_r2_vals),
    test_r2_mean = mean(test_r2_vals),
    test_r2_sd = sd(test_r2_vals),
    train_rmse_mean = mean(sapply(outer_fold_results, function(x) x$metrics$train_rmse)),
    test_rmse_mean = mean(sapply(outer_fold_results, function(x) x$metrics$test_rmse))
  ))
}

# 4. run for each target and feature combination -------------------------------

targets     <- c("GPP", "ER", "NEP")
all_results <- list()

for (target in targets) {

  target_results <- list()
  for (combo_name in names(feature_combinations[[target]])) {
    features <- feature_combinations[[target]][[combo_name]]
    target_results[[combo_name]] <- run_double_cv(target, features, combo_name, n_cores)
  }
  all_results[[target]] <- target_results
}

future::plan(future::sequential)

# 5. summarize and save --------------------------------------------------------

summary_results <- do.call(rbind, lapply(targets, function(target) {
  do.call(rbind, lapply(names(all_results[[target]]), function(combo) {
    r <- all_results[[target]][[combo]]
    data.frame(
      target      = target,
      combination = combo,
      n_features  = r$n_features,
      train_r2    = round(r$train_r2_mean, 3),
      train_r2_sd = round(r$train_r2_sd,   3),
      test_r2     = round(r$test_r2_mean,  3),
      test_r2_sd  = round(r$test_r2_sd,    3),
      train_rmse  = round(r$train_rmse_mean, 3),
      test_rmse   = round(r$test_rmse_mean,  3),
      stringsAsFactors = FALSE
    )
  }))
}))

print(summary_results)
write.csv(summary_results, file.path(base_output_dir, "feature_combination_summary.csv"), row.names = FALSE)
saveRDS(all_results,       file.path(base_output_dir, "all_feature_combination_results.rds"))
