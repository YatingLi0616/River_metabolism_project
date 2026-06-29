# RF_monthly_local.R
#
# purpose:
#   trains a single random forest model (via mlr3 + ranger) for each of three
#   river metabolism targets (GPP, ER, NEP), using an 80/20 train/test split
#   and 10-fold cv grid search for hyperparameter tuning. computes treeshap
#   importance and per-observation shap dependency values for the final model.
#
#
# inputs:
#   - data/input/ml_monthly.rds : data.table with columns GPP, ER, NEP, and
#     the predictor columns listed in feature_cols below
#
# outputs:
#   - output/ml_monthly/results/<target>_evaluation_predictions.csv
#   - output/ml_monthly/results/<target>_treeshap_importance.csv
#   - output/ml_monthly/results/<target>_shap_dependency.csv
#   - output/ml_monthly/results/overall_summary.csv
#   - output/ml_monthly/models/<target>_main_model.rds  (used by pdp_analysis_local.R)
#
# usage:
#   Rscript RF_monthly_local.R
#   or open in RStudio and run the whole script (Source)
#   (run from the project root, or set the working directory below)
#
# expected runtime: this trains 3 random forests with a 10-fold cv grid
# search each, plus treeshap on the full dataset - on a laptop this can
# take anywhere from several minutes to an hour or more depending on
# dataset size and core count. 


# 1. setup ----------------------------------------------------------------------

# set this if your r packages live in a non-default location (e.g. a conda
# or renv library path). leave blank to use the default library path.
custom_lib_path <- ""
if (nzchar(custom_lib_path)) .libPaths(custom_lib_path)

library(mlr3)
library(mlr3learners)
library(mlr3tuning)
library(paradox)
library(data.table)
library(treeshap)
library(future)
library(tictoc)
library(ranger)
library(MLmetrics)
library(parallel)

# uncomment and edit if running from somewhere other than the project root:
# setwd("your/project/root")

# use all but one local core, so the machine stays responsive for other work -
# edit this directly if you want to use more or fewer cores
n_cores <- max(1, parallel::detectCores() - 1)
cat("Using", n_cores, "cores locally\n")

output_base  <- "Output/RF/RF_ML_monthly/"
results_path <- file.path(output_base, "results/")
model_path   <- file.path(output_base, "models/")

for (d in c(output_base, results_path, model_path)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE)
}

# 2. load data and define tasks ------------------------------------------------

ML_data <- readRDS("Data/input/ML_monthly.rds")

feature_cols <- c("light_eff", "disch_skew",
                  "DIC", "nutrient_index",
                  "urban", "forest", "wetland", "dryland", "agriculture")

set.seed(123)
train_idx  <- sample(1:nrow(ML_data), size = 0.8 * nrow(ML_data))
train_data <- ML_data[train_idx, ]
test_data  <- ML_data[-train_idx, ]

GPP_train <- train_data[, c("GPP", feature_cols), with = FALSE]
ER_train  <- train_data[, c("ER",  feature_cols), with = FALSE]
NEP_train <- train_data[, c("NEP", feature_cols), with = FALSE]

GPP_test  <- test_data[, c("GPP", feature_cols), with = FALSE]
ER_test   <- test_data[, c("ER",  feature_cols), with = FALSE]
NEP_test  <- test_data[, c("NEP", feature_cols), with = FALSE]

GPP_task <- TaskRegr$new(id = "GPP_task", backend = GPP_train, target = "GPP")
ER_task  <- TaskRegr$new(id = "ER_task",  backend = ER_train,  target = "ER")
NEP_task <- TaskRegr$new(id = "NEP_task", backend = NEP_train, target = "NEP")

# 3. helper functions ----------------------------------------------------------

# fit the final model on the full dataset (train + test) using the best
# hyperparameters found during tuning
train_main_model <- function(full_data, target_col, feature_cols, best_params, seed = 123) {
  full_df <- as.data.frame(full_data[, c(target_col, feature_cols), with = FALSE])

  set.seed(seed)
  model_main <- ranger(
    formula = as.formula(paste(target_col, "~ .")),
    data = full_df,
    num.trees = best_params$num.trees,
    min.node.size = best_params$min.node.size,
    seed = seed,
    importance = "impurity"
  )
  return(model_main)
}

# treeshap importance and per-observation shap dependency values
calculate_shap_importance <- function(ranger_model, features_X, feature_cols) {

  unified_model <- ranger.unify(ranger_model, features_X)
  shap_values   <- treeshap(unified_model, features_X, verbose = FALSE)$shaps

  treeshap_importance <- data.frame(
    variable = names(shap_values),
    importance = apply(abs(shap_values), 2, mean)
  )
  treeshap_importance <- treeshap_importance[order(-treeshap_importance$importance), ]

  dependency_data <- data.frame(observation_id = seq_len(nrow(shap_values)))
  for (feat in feature_cols) {
    dependency_data[[paste0(feat, "_value")]] <- features_X[[feat]]
    dependency_data[[paste0(feat, "_shap")]]  <- shap_values[[feat]]
  }

  return(list(
    treeshap = treeshap_importance,
    shap_dependency = dependency_data
  ))
}

# hyperparameter tuning (10-fold cv grid search), train/test evaluation,
# final model fit on full data, treeshap importance
run_ml_workflow <- function(task_name, task, learner, test_data,
                            feature_cols, target_col,
                            results_path, model_path,
                            param_set, train_data, n_cores, seed = 123) {

  set.seed(seed)
  future::plan(future::multisession, workers = max(1, n_cores - 1))

  tuning_instance <- TuningInstanceBatchSingleCrit$new(
    task = task,
    learner = learner,
    resampling = rsmp("cv", folds = 10),
    measure = msr("regr.mse"),
    search_space = param_set,
    terminator = trm("none")
  )

  tic("Tuning")
  tnr("grid_search")$optimize(tuning_instance)
  future::plan(future::sequential)
  toc()

  best_params <- tuning_instance$result_learner_param_vals
  cat("Best parameters:\n"); print(best_params)

  # evaluate on train set
  learner$param_set$values <- best_params
  learner$train(task)

  train_pred <- learner$predict(task)
  train_r2   <- R2_Score(train_pred$response, train_pred$truth)
  train_rmse <- RMSE(train_pred$response, train_pred$truth)
  cat("Training R2:", round(train_r2, 4), "  RMSE:", round(train_rmse, 4), "\n")

  # evaluate on test set
  test_task <- TaskRegr$new(
    id = paste0(task_name, "_test"),
    backend = test_data,
    target = target_col
  )
  test_pred <- learner$predict(test_task)
  test_r2   <- R2_Score(test_pred$response, test_pred$truth)
  test_rmse <- RMSE(test_pred$response, test_pred$truth)
  cat("Test R2:", round(test_r2, 4), "  RMSE:", round(test_rmse, 4), "\n")

  eval_predictions <- data.frame(
    actual = c(train_pred$truth, test_pred$truth),
    predicted = c(train_pred$response, test_pred$response),
    dataset = c(rep("training", length(train_pred$truth)),
                rep("test", length(test_pred$truth)))
  )
  write.csv(eval_predictions,
            file.path(results_path, paste0(task_name, "_evaluation_predictions.csv")),
            row.names = FALSE)

  # final model: refit on full data (train + test) with the tuned hyperparameters
  full_data <- rbind(train_data, test_data)

  model_main <- train_main_model(full_data, target_col, feature_cols, best_params, seed)
  saveRDS(model_main, file.path(model_path, paste0(task_name, "_main_model.rds")))

  # treeshap importance on the full dataset
  features_X <- as.data.frame(full_data[, feature_cols, with = FALSE])

  shap_results <- calculate_shap_importance(model_main, features_X, feature_cols)

  write.csv(shap_results$treeshap,
            file.path(results_path, paste0(task_name, "_treeshap_importance.csv")),
            row.names = FALSE)
  write.csv(shap_results$shap_dependency,
            file.path(results_path, paste0(task_name, "_shap_dependency.csv")),
            row.names = FALSE)

  summary_data <- data.frame(
    target = task_name,
    train_r2 = train_r2,
    test_r2 = test_r2,
    train_rmse = train_rmse,
    test_rmse = test_rmse,
    num_trees = best_params$num.trees,
    min_node_size = best_params$min.node.size,
    seed = seed,
    train_date = as.character(Sys.time())
  )

  return(summary_data)
}

# 4. run for each target -------------------------------------------------------

param_set <- ps(
  num.trees = p_fct(c(100, 200, 400, 600, 800, 1000)),
  min.node.size = p_fct(c(2, 4, 6, 8, 10))
)

# num.threads = 1 here is intentional: future already parallelizes across
# hyperparameter combinations during tuning, so each individual model fit
# should stay single-threaded to avoid oversubscribing local cpu cores
tuning_learner <- function() {
  lrn("regr.ranger", predict_type = "response", num.threads = 1)
}

tic("GPP")
GPP_summary <- run_ml_workflow("GPP", GPP_task, tuning_learner(),
                               GPP_test, feature_cols, "GPP", results_path, model_path,
                               param_set, GPP_train, n_cores)
toc()

tic("ER")
ER_summary <- run_ml_workflow("ER", ER_task, tuning_learner(),
                              ER_test, feature_cols, "ER", results_path, model_path,
                              param_set, ER_train, n_cores)
toc()

tic("NEP")
NEP_summary <- run_ml_workflow("NEP", NEP_task, tuning_learner(),
                               NEP_test, feature_cols, "NEP", results_path, model_path,
                               param_set, NEP_train, n_cores)
toc()

overall_summary <- rbind(GPP_summary, ER_summary, NEP_summary)
write.csv(overall_summary, file.path(results_path, "overall_summary.csv"), row.names = FALSE)

cat("\ndone. models saved to:", model_path, "\n")
