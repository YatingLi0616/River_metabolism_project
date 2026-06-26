#!/bin/bash
# RF_DCV_monthly.slurm
# runs: RF_DCV_monthly.R
# purpose: nested cv comparison of feature combinations for GPP, ER, NEP

#SBATCH --job-name=RF_DCV_monthly
#SBATCH --time=2:00:00
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=9        # request 9 cpu cores
#SBATCH --nodes=1
#SBATCH --mem=8G
#SBATCH --output=RF_DCV_monthly.%j.out

module load GCC/12.2.0
module load OpenMPI/4.1.4
module load R/4.3.1

export RSTUDIO=0
export TZ=UTC

# edit this to your project root before running
project_dir="your/project/root"
cd "$project_dir" || exit 1

Rscript RF_DCV_monthly.R
