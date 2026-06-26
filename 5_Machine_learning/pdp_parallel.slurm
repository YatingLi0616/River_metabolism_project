#!/bin/bash

# pdp_parallel.slurm
# runs: pdp_analysis_parallel.R
# purpose: conditional pdp / ice threshold analysis, one array task per target

#SBATCH --job-name=pdp_parallel
#SBATCH --time=6:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=9
#SBATCH --nodes=1
#SBATCH --mem=64G
#SBATCH --array=0-2                         # 3 jobs: index 0=GPP, 1=ER, 2=NEP
#SBATCH --output=pdp_parallel.%A_%a.out     # %A=array job id, %a=task index

module load GCC/12.2.0
module load OpenMPI/4.1.4
module load R/4.3.1

export RSTUDIO=0
export TZ=UTC

# edit this to your project root before running
project_dir="your/project/root"
cd "$project_dir" || exit 1

# map array index to target name
TARGETS=("GPP" "ER" "NEP")
TARGET=${TARGETS[$SLURM_ARRAY_TASK_ID]}

echo "Running target: $TARGET (array task $SLURM_ARRAY_TASK_ID)"

Rscript pdp_analysis_parallel.R \
  "Data/output/ML_data/ML_monthly.rds" \
  "Output/RF/RF_ML_monthly/models/" \
  "Output/RF/RF_ML_monthly/pdp_ice_threshold_analysis/" \
  "$TARGET"
