#!/bin/bash
#SBATCH --job-name=nlcd_parallel
#SBATCH --output=log_nlcd_%A_%a.out
#SBATCH --error=log_nlcd_%A_%a.err
#SBATCH --time=06:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=16
#SBATCH --mem=64G

module load Anaconda3
source activate gdal_env

# edit this to your project root before running
project_dir="your/project/root"
cd "$project_dir" || exit 1

classes=(11 12 21 22 23 24 31 41 42 43 52 71 81 82 90 95)

printf "%s\n" "${classes[@]}" > class_list.txt

cat class_list.txt | parallel -j 16 "bash extract_and_reproject.sh {}"
