#!/bin/bash
# process one site: crop each nlcd class raster to its basin and tally pixel counts
# usage: bash process_single_site.sh <task_id>

task_id=$1

# path configuration
project_dir="/scratch/user/u.yl170950/nlcd_project"
basin_dir="Data/input/NLCD_data/upstream_basin"
reprojected_dir="Data/output/NLCD_data/nlcd_classes_wgs84"
output_dir="Data/output/NLCD_data/landcover_proportions"

cd "$project_dir" || exit 1
mkdir -p "$output_dir" logs

# nlcd land cover class codes
classes=(11 12 21 22 23 24 31 41 42 43 52 71 81 82 90 95)

# get all basin files in the upstream basin folder
mapfile -t basin_files < <(ls "$basin_dir"/*.shp | sort)

# get the basin file for this task; site_id works whether files are
# named "basin_<id>.shp" or just "<id>.shp"
basin_file="${basin_files[$((task_id-1))]}"
site_id=$(basename "$basin_file" | sed -E 's/\.shp$//; s/^basin_//')

echo "processing site: $site_id (task $task_id)"

temp_csv="$output_dir/temp_${site_id}.csv"
debug_log="$output_dir/debug_${site_id}.log"

echo "start time: $(date)" > "$debug_log"
echo "site: $site_id" >> "$debug_log"
echo "basin file: $basin_file" >> "$debug_log"

total_pixels=0
pixel_counts=()

for class in "${classes[@]}"; do
  raster="$reprojected_dir/nlcd_class_${class}_wgs84.tif"
  temp_crop="temp_${site_id}_${class}_${task_id}.tif"

  if [ ! -f "$raster" ]; then
    echo "warning: raster file does not exist: $raster" >> "$debug_log"
    pixel_counts+=(0)
    continue
  fi

  # 1. crop raster to basin
  echo "cropping class $class..." >> "$debug_log"
  gdalwarp -overwrite -dstnodata 0 -crop_to_cutline -cutline "$basin_file" \
    -co compress=deflate "$raster" "$temp_crop" >> "$debug_log" 2>&1

  if [ ! -f "$temp_crop" ]; then
    echo "error: cropping failed: $temp_crop" >> "$debug_log"
    pixel_counts+=(0)
    continue
  fi

  # 2. use histogram method to get pixel count
  pixel_count=0

  # method 1: extract pixel count with value 1 from histogram
  hist_output=$(gdalinfo -hist "$temp_crop" 2>/dev/null)
  bucket_line=$(echo "$hist_output" | grep -A 1 "buckets from" | tail -1)
  if [ ! -z "$bucket_line" ]; then
    pixel_count=$(echo "$bucket_line" | awk '{print $2}')
    echo "histogram method - class $class: $pixel_count pixels" >> "$debug_log"
  fi

  # method 2: fall back to valid_percent calculation if histogram failed
  if [ "$pixel_count" = "0" ] || [ -z "$pixel_count" ]; then
    valid_percent=$(gdalinfo "$temp_crop" 2>/dev/null | grep "STATISTICS_VALID_PERCENT=" | cut -d "=" -f2)
    if [ ! -z "$valid_percent" ] && [ "$valid_percent" != "0" ]; then
      size_info=$(gdalinfo "$temp_crop" 2>/dev/null | grep "Size is")
      width=$(echo "$size_info" | awk '{print $3}' | sed 's/,//')
      height=$(echo "$size_info" | awk '{print $4}')

      if [ ! -z "$width" ] && [ ! -z "$height" ]; then
        total_size=$(echo "$width * $height" | bc)
        pixel_count=$(echo "scale=0; $total_size * $valid_percent / 100" | bc)
        echo "percentage method - class $class: $pixel_count pixels (${valid_percent}%)" >> "$debug_log"
      fi
    fi
  fi

  if ! [[ "$pixel_count" =~ ^[0-9]+$ ]]; then
    pixel_count=0
  fi

  echo "final result - class $class: $pixel_count pixels" >> "$debug_log"
  pixel_counts+=("$pixel_count")
  total_pixels=$(echo "$total_pixels + $pixel_count" | bc)

  rm -f "$temp_crop"
done

echo "total pixels: $total_pixels" >> "$debug_log"

# write current site results to its own temp file
{
  echo -n "$site_id"
  total_prop=0
  for i in "${!pixel_counts[@]}"; do
    count="${pixel_counts[$i]}"
    if (( $(echo "$total_pixels > 0" | bc -l) )); then
      prop=$(echo "scale=8; $count / $total_pixels" | bc)
    else
      prop=0
    fi
    echo -n ",$prop"
    total_prop=$(echo "$total_prop + $prop" | bc)
  done
  echo ",$total_prop"
} > "$temp_csv"

echo "completed site: $site_id | total proportion: $total_prop" >> "$debug_log"
echo "end time: $(date)" >> "$debug_log"
echo "site $site_id processing complete! total proportion: $total_prop"
