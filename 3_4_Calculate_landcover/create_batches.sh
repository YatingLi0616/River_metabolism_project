#!/bin/bash
# generate one slurm batch script per group of sites, sized to however
# many basin shapefiles are actually present

basin_dir="Data/input/NLCD_data/upstream_basin"
batch_size=50

echo "generating slurm scripts for all batches..."

actual_sites=$(ls "$basin_dir"/*.shp 2>/dev/null | wc -l)
if [ "$actual_sites" -eq 0 ]; then
    echo "error: no basin files found! check the $basin_dir directory"
    exit 1
fi

echo "detected actual number of sites: $actual_sites"

total_sites=$actual_sites
num_batches=$(( (total_sites + batch_size - 1) / batch_size ))

echo "total sites: $total_sites"
echo "batch size: $batch_size"
echo "number of batches needed: $num_batches"

for i in $(seq 1 $num_batches); do
    start_site=$(( (i-1) * batch_size + 1 ))
    end_site=$(( i * batch_size ))

    if [ $end_site -gt $total_sites ]; then
        end_site=$total_sites
    fi

    script_name="nlcd_batch${i}.sbatch"

    echo "creating $script_name (sites $start_site-$end_site)"

    cat > $script_name << eof
#!/bin/bash
#SBATCH --job-name=nlcd_batch${i}
#SBATCH --output=logs/nlcd_%A_%a.out
#SBATCH --error=logs/nlcd_%A_%a.err
#SBATCH --time=04:00:00
#SBATCH --partition=cpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --array=${start_site}-${end_site}%5

module load Anaconda3
source activate gdal_env

bash process_single_site.sh \$SLURM_ARRAY_TASK_ID
eof
    chmod +x $script_name
done

echo "generation complete! created $num_batches batch scripts"
