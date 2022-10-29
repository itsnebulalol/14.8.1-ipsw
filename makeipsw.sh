#!/usr/bin/env bash
# this is a small funny script to make a 14.8.1 ipsw
# may or may not work.
# made by nebula and nick chan
# usage: ./makeipsw.sh <link to 14.8.1 ota> <deviceid, eg. iPhone10,6> <optional, aria2c download threads, default 32>

if [ $# -eq 0 ]; then
    echo "Usage: $0 [link, 14.8.1 ota] [deviceid, eg. iPhone10,6] [threads, optional]" && exit 1
fi

set -e
set -o xtrace

mkdir -p ipsws
sudo rm -rf work
if [ -z "$VOLUME_NAME" ]; then
	VOLUME_NAME=AzulSecuritySky18H107.D22D221OS
fi

# aria2c args
if [ -z "$3" ]; then
    aria2c_args="-j32 -x32 -s32"
else
    aria2c_args="-j$3 -x$3 -s$3"
fi

# download the ota
aria2c $aria2c_args "$1" -o "ota-$2.zip"

# download the ipsw
ipswurl=$(curl -sL "https://api.ipsw.me/v4/device/$2?type=ipsw" | jq '.firmwares | .[] | select(.version=="14.8") | .url' --raw-output)
aria2c $aria2c_args "$ipswurl" -o "ipsw-$2.ipsw"

# create work dir
mkdir -p work/ota work/ipsw
cd work/ipsw
unzip ../../ipsw-"$2".ipsw
rm ../../ipsw-"$2".ipsw
cd ..

# unzip ota
cd ota
unzip ../../ota-"$2".zip
rm ../../ota-"$2".zip
curl -LO "https://cdn.discordapp.com/attachments/1006183120762048592/1033719560035119144/template.dmg"

# make the rootfs
mkdir AssetData/rootfs
cd AssetData/rootfs
gfind ../payloadv2 -name 'payload.[0-9][0-9][0-9]' -print -exec sudo aa extract -i {} \;
sudo aa extract -i ../payloadv2/fixup.manifest || true
sudo aa extract -i ../payloadv2/data_payload
sudo chown -R 0:0 ../payload/replace/*
sudo cp -a ../payload/replace/* .

for app in ../payloadv2/app_patches/*.app; do
    appname=$(echo $app | cut -d/ -f4)
    sudo mkdir -p "private/var/staged_system_apps/$appname"
    sudo cp -a "$app" "private/var/staged_system_apps/$appname"
    pushd "private/var/staged_system_apps/$appname"
    sudo 7z x "$appname" || true;
    sudo aa extract -i $(echo "$appname" | cut -d. -f1)|| true;
    sudo rm "$appname"
    popd
done

# make the root dmg
cd ..
cp ../template.dmg output.dmg
rm ../template.dmg
hdiutil resize -size 10000m output.dmg
sudo hdiutil attach output.dmg
sudo diskutil enableOwnership /Volumes/Template
sudo mount -urw /Volumes/Template
sudo rsync -a rootfs/ /Volumes/Template/
sudo diskutil rename /Volumes/Template $VOLUME_NAME
hdiutil detach /Volumes/$VOLUME_NAME
hdiutil convert -format ULFO -o converted.dmg output.dmg
asr imagescan --source converted.dmg
cd ../..

# use 14.8.1 Firmware + kernel except Firmware/dfu
cd ipsw
rm -rf dfu
mkdir dfu
cp -R Firmware/dfu/* dfu/
rm -rf Firmware kernelcache.release.*
mkdir Firmware
cp -R ../ota/AssetData/boot/Firmware/* Firmware/
cp ../ota/AssetData/boot/kernelcache.release.* .

rm -rf Firmware/dfu
mkdir Firmware/dfu
cp -R dfu/* Firmware/dfu/
rm -rf dfu

# Move 14.8.1 files into place
ipsw_mtree=$(plutil -extract "BuildIdentities".0."Manifest"."Ap,SystemVolumeCanonicalMetadata"."Info"."Path" raw -expect string -o - BuildManifest.plist)
ota_mtree=$(plutil -extract "BuildIdentities".0."Manifest"."Ap,SystemVolumeCanonicalMetadata"."Info"."Path" raw -expect string -o - ../ota/AssetData/boot/BuildManifest.plist)
mv $ota_mtree $ipsw_mtree

ipsw_hash=$(plutil -extract "BuildIdentities".0."Manifest"."SystemVolume"."Info"."Path" raw -expect string -o - BuildManifest.plist)
ota_hash=$(plutil -extract "BuildIdentities".0."Manifest"."SystemVolume"."Info"."Path" raw -expect string -o - ../ota/AssetData/boot/BuildManifest.plist)
mv $ota_hash $ipsw_hash

ipsw_rootfs_trustcache=$(plutil -extract "BuildIdentities".0."Manifest"."StaticTrustCache"."Info"."Path" raw -expect string -o - BuildManifest.plist)
ota_rootfs_trustcache=$(plutil -extract "BuildIdentities".0."Manifest"."StaticTrustCache"."Info"."Path" raw -expect string -o - ../ota/AssetData/boot/BuildManifest.plist)
mv $ota_rootfs_trustcache $ipsw_rootfs_trustcache

ipsw_rootfs=$(plutil -extract "BuildIdentities".0."Manifest"."OS"."Info"."Path" raw -expect string -o - BuildManifest.plist)
cp ../ota/AssetData/converted.dmg $ipsw_rootfs

# Patch the Restore/Update ramdisk
for identity in $(eval echo {0..$(expr $(plutil -extract BuildIdentities raw -expect array -o - BuildManifest.plist) - 1)}); do
	ipsw_restoreramdisk=$(plutil -extract "BuildIdentities".${identity}."Manifest"."RestoreRamDisk"."Info"."Path" raw -expect string -o - BuildManifest.plist)
	ipsw_restorebehavior=$(plutil -extract "BuildIdentities".${identity}."Info"."RestoreBehavior" raw -expect string -o - BuildManifest.plist)
	case $ipsw_restorebehavior in
		Erase)
		restored_suffix="_external"
		;;
		Update)
		restored_suffix="_update"
		;;
		*)
		>&2 echo "Unknown RestoreBehavior: ${ipsw_restorebehavior}"
		exit 1;
		;;
	esac

	if [ -f "${ipsw_restoreramdisk}.rdsk-done" ]; then continue; fi
	img4 -i $ipsw_restoreramdisk -o dec.${ipsw_restoreramdisk}

	restoreramdisk_mount_path=$(hdiutil attach dec.${ipsw_restoreramdisk} | cut -d'	' -f3)
	sudo diskutil enableOwnership "$restoreramdisk_mount_path"
	sudo mount -urw "$restoreramdisk_mount_path"
	sudo asr64_patcher "$restoreramdisk_mount_path"/usr/sbin/asr{,.patched}
	sudo mv "$restoreramdisk_mount_path"/usr/sbin/asr{.patched,}
	sudo restored_external64_patcher "$restoreramdisk_mount_path"/usr/local/bin/restored${restored_suffix}{,.patched}
	sudo mv "$restoreramdisk_mount_path"/usr/local/bin/restored${restored_suffix}{.patched,}
	sudo ldid -s "$restoreramdisk_mount_path"/usr/local/bin/restored${restored_suffix} "$restoreramdisk_mount_path"/usr/sbin/asr
	sudo chmod 755 "$restoreramdisk_mount_path"/usr/local/bin/restored${restored_suffix} "$restoreramdisk_mount_path"/usr/sbin/asr

	ipsw_restoretrustcache=$(plutil -extract "BuildIdentities".${identity}."Manifest"."RestoreTrustCache"."Info"."Path" raw -expect string -o - BuildManifest.plist)
	trustcache create -v 1 ${ipsw_restoretrustcache}.dec "$restoreramdisk_mount_path"
	hdiutil detach "${restoreramdisk_mount_path}"

	img4 -i dec.${ipsw_restoreramdisk} -o $ipsw_restoreramdisk -A -T rdsk
	img4 -i ${ipsw_restoretrustcache}.dec -o ${ipsw_restoretrustcache} -A -T rtsc
	rm -f ${ipsw_restoretrustcache}.dec dec.${ipsw_restoreramdisk}
	touch "${ipsw_restoreramdisk}.rdsk-done"
done

rm -f *".rdsk-done"
# make the ipsw
zip -r9 ../../ipsws/"$2"_14.8.1_18H107_Restore.ipsw .
cd ../../

echo "Done! Your new ipsw is in ipsws/'$2'_14.8.1_18H107_Restore.ipsw"
