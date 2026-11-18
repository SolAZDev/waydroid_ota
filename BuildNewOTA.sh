#!/bin/bash

# Default Values
# ARCH="x86_64"
BASE_FOLDER="v4.4-t"
OUT=/out/target/product/
VER="4.4.2-t"
DATE=$(date -u +%Y%m%d)

OUTPUT_DIR=eos-$VER-$DATE
RELEASE_REPO="SolAZDev/waydroid_ota"
RELEASE_URL="https://github.com/$RELEASE_REPO/releases/download"
OG_PWD=$PWD

TS=$(date -u +%s)
TAG=eos-$DATE-$TS

# ( cd "$OUT" && zip -9 eos-$VER-$DATE-VANILLA-waydroid_$ARCH-system.zip system.img )
# ( cd "$OUT" && zip -9 eos-$VER-$DATE-MAINLINE-waydroid_$ARCH-vendor.zip vendor.img )
# 
# sha256sum eos-*.zip
# stat -c '%n %s' eos-*.zip
# date +%s

function yes_or_no {
    while true; do
        read -p "$* [y/n]: " yn
        case $yn in
            [Yy]*) return 0  ;;
            [Nn]*) echo "Aborted" ; return  1 ;;
        esac
    done
}


function GetValues {
	read -p "What Version Folder should we look for? : " BASE_FOLDER
	read -p "What Version is this? : " VER
	# read -p "What Waydroid Architecture should I look for? (x86_64, arm64, arm64_only, etc) : " ARCH
	ValidateOptions || exit 1
}

function ValidateOptions {
	echo "\n\n\n"
	echo "Please confirm your selection"
	# echo "Arch      : $ARCH"
	echo "Version   : $VER"
	echo "Stored at : $BASE_FOLDER"
	echo "Finalized Folder is : $BASE_FOLDER$OUT"
	yes_or_no "Are these options Correct?: "
}

function ZipUp {
	cd $BASE_FOLDER$OUT  || { echo "cannot enter $BASE_FOLDER$OUT"; exit 1; }
	mkdir -p $OUTPUT_DIR
	for dir in waydroid_*/; do
		 if [ ! -f "${dir}system.img" ] || [ ! -f "${dir}vendor.img" ]; then
	        echo "skipping $dir (no system or vendor found)"
	        continue
	    fi
		ARCH=${dir%/}; ARCH=${ARCH#waydroid_}
		zip -9 -j ./$OUTPUT_DIR/eos-$VER-$DATE-VANILLA-waydroid_$ARCH-system.zip $dir/system.img
		zip -9 -j ./$OUTPUT_DIR/eos-$VER-$DATE-MAINLINE-waydroid_$ARCH-vendor.zip $dir/vendor.img
	done
	echo "Images from $BASE_FOLDER$OUT were compressed into zip files to $BASE_FOLDER$OUT/$OUTPUT_DIR!"
}

function MakeRelease { 
	cd $BASE_FOLDER$OUT/$OUTPUT_DIR || { echo "cannot enter $BASE_FOLDER$OUTPUT_DIR"; exit 1; }
	echo "Also this will take some time... Get a drink, or read a book for a bit."
	gh release create $TAG --repo $RELEASE_REPO --draft --target master --title "e/OS $VER ($DATE)" --notes "Build $DATE"

	# zips=( "$OUTPUT_DIR"/eos-$VER-$DATE-*.zip )
	# [ ${#zips[@]} -gt 0 ] || { echo "no zips to upload"; exit 1; }
	# gh release upload "$TAG" --repo "$RELEASE_REPO" "${zips[@]}"
	
	gh release upload $TAG --repo $RELEASE_REPO eos-$VER-$DATE-*.zip
	gh release edit $TAG --repo $RELEASE_REPO --draft=false
	echo "Upload to Github
	 release COMPLETE"	
}

function UpdateManifests {
	cd $OG_PWD
	echo "Appending to manifests"
	
	for sysZip in $BASE_FOLDER$OUT/$OUTPUT_DIR/*-system.zip; do
		[ -e "$sysZip" ] || continue
		sys=${sysZip#$BASE_FOLDER$OUT/$OUTPUT_DIR/}
		arch=${sys##*waydroid_}; arch=${arch%-system.zip}
		sha=$(sha256sum "$sysZip" | cut -d' ' -f1)
		size=$(stat -c %s "$sysZip")
		url="$RELEASE_URL/$TAG/$sys"

		json="system/lineage/waydroid_$arch/VANILLA.json"
		mkdir -p "$(dirname "$json")" # Just in case it doesn't exist
		if [ -f "$json" ] && grep -qF "\"id\": \"$sha\"" "$json"; then
		    echo "already present in $json"
		else
		    python3 append.py "$json" "$TS" "$sys" "$sha" VANILLA "$size" "$url" "$VER"
		fi
	done

	for vndZip in $BASE_FOLDER$OUT/$OUTPUT_DIR/*-vendor.zip; do	
		[ -e "$vndZip" ] || continue
		vnd=${vndZip#$BASE_FOLDER$OUT/$OUTPUT_DIR/}
		arch=${vnd##*waydroid_}; arch=${arch%-vendor.zip}
		sha=$(sha256sum "$vndZip" | cut -d' ' -f1)
		size=$(stat -c %s "$vndZip")
		url="$RELEASE_URL/$TAG/$vnd"

		for vt in MAINLINE HALIUM_11 HALIUM_12 HALIUM_12L HALIUM_13; do
			json="vendor/waydroid_$arch/$vt.json"
			mkdir -p "$(dirname "$json")" # Just in case it doesn't exist
			if [ -f "$json" ] && grep -qF "\"id\": \"$sha\"" "$json"; then
			    echo "already present in $json"
			else
			 	python3 append.py "$json" "$TS" "$vnd" "$sha" MAINLINE "$size" "$url" "$VER"
		 	fi
		done
	done
	echo "Manifest Update is done!"
}


echo "Notice! This should be executed from the waydroid_ota repo folder."
echo "It also requires the Github CLI, unfortunately. At least to upload Release."
echo "For appending it works fine, but you need to make sure the Release is finalized."
GetValues
ZipUp
UpdateManifests

echo -e "\n\nAt this point, you can stop if you don't have the Github CLI. But if you do you can use it to make a new Release"
echo "Alternatively you must make the release yourself using the following tag; $TAG"
yes_or_no "Use Github CLI to Make a new release?" && MakeRelease
echo "The Process is finished. You must now do Commit and Push to reflect the new OTA."
