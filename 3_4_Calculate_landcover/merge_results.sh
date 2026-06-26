#!/bin/bash
# merge per-site temporary csvs into one final landcover summary table

project_dir="/scratch/user/u.yl170950/nlcd_project"
output_dir="Data/output/NLCD_data/landcover_proportions"
final_csv="Data/output/NLCD_data/landcover_allsites.csv"

cd "$project_dir" || exit 1
mkdir -p "$(dirname "$final_csv")"

classes=(11 12 21 22 23 24 31 41 42 43 52 71 81 82 90 95)

temp_count=$(ls "$output_dir"/temp_*.csv 2>/dev/null | wc -l)
echo "found $temp_count temporary files."

if [ "$temp_count" -eq 0 ]; then
    echo "no temporary files found. check whether the jobs completed successfully."
    exit 1
fi

# write header
{
  echo -n "site_id"
  for class in "${classes[@]}"; do
    echo -n ",class_${class}"
  done
  echo ",total_proportion"
} > "$final_csv"

# merge all temp files
for temp_file in $(ls "$output_dir"/temp_*.csv | sort); do
  if [ -f "$temp_file" ]; then
    cat "$temp_file" >> "$final_csv"
    echo "merged: $(basename "$temp_file")"
  fi
done

total_sites=$(tail -n +2 "$final_csv" | wc -l)
echo "successfully processed $total_sites sites."

# summarize the total_proportion column (column 18: site_id + 16 classes + total)
tail -n +2 "$final_csv" | cut -d',' -f18 | awk '
BEGIN { count=0; sum=0; min=999; max=0; zeros=0 }
{
  count++;
  sum += $1;
  if ($1 < min) min = $1;
  if ($1 > max) max = $1;
  if ($1 == 0) zeros++;
}
END {
  printf "total sites: %d\n", count;
  printf "mean total proportion: %.6f\n", sum / count;
  printf "minimum total proportion: %.6f\n", min;
  printf "maximum total proportion: %.6f\n", max;
  printf "sites with zero total proportion: %d\n", zeros;
  printf "successfully processed sites: %d (%.1f%%)\n",
         count - zeros, (count - zeros) / count * 100;
}'

echo
echo "preview of the output:"
head -6 "$final_csv"

echo
echo "results have been saved to:"
echo "$final_csv"

echo
echo "remove temporary files? (y/n)"
read -t 10 answer

if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    rm -f "$output_dir"/temp_*.csv
    echo "temporary files removed."
else
    echo "temporary files were kept in:"
    echo "$output_dir/temp_*.csv"
fi
