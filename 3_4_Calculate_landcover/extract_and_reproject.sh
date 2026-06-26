# # data source:
# U.S. Geological Survey (USGS). Annual National Land Cover Database (NLCD) Collection 1 Science Products
# DOI: https://doi.org/10.5066/P94UXNTS

#!/bin/bash
# create a binary mask for one nlcd class and reproject it to wgs84
# usage: bash extract_and_reproject.sh <class_code>

class=$1
echo "processing class $class"

nlcd_tif="Data/input/NLCD_data/Annual_NLCD_LndCov_2010_CU_C1V1/Annual_NLCD_LndCov_2010_CU_C1V1.tif"
out_dir="Data/output/NLCD_data/nlcd_classes"
reproj_dir="Data/output/NLCD_data/nlcd_classes_wgs84"

mkdir -p "$out_dir" "$reproj_dir"

# create a nodata-aware copy of the source raster once, reused for every class
nodata_tif="$out_dir/nlcd_nodata.tif"
if [ ! -f "$nodata_tif" ]; then
    echo "creating nodata version of input raster..."
    gdal_translate -a_nodata 0 -co compress=deflate "$nlcd_tif" "$nodata_tif"
fi

# binary mask: 1 where pixel equals this class, 0/nodata elsewhere
class_out="$out_dir/nlcd_class_${class}.tif"
gdal_calc.py --overwrite --co="compress=deflate" --type=Byte --NoDataValue=0 \
    -A "$nodata_tif" --calc="A==$class" --outfile="$class_out"

# reproject the mask to wgs84 for use with lat/lon basin polygons
reproj_out="$reproj_dir/nlcd_class_${class}_wgs84.tif"
gdalwarp -t_srs EPSG:4326 -r near -co compress=deflate -dstnodata 0 "$class_out" "$reproj_out"

echo "done class $class"
