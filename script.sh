#!/bin/bash -eu

# TODO: integrate https://github.com/sdcweb/redoflacs

########################################
##  MEDIA FILE CHECK
########################################

#### Commands to check for consistency
# use latest FLAC binary compiled from master branch
# in order to avoid having false positive MD5 issues
export FLAC=flac
export MP3VAL=mp3val

#### Folders & paths
export ZIK_DIR="/mnt/DATA/DATA/Zik/zik/"
export LOG_DIR=~/music_check_logs
# export ZIK_DIR="/home/koubi/inco/"
# export LOG_DIR=~/music_check_logs_dls

# file list, result from find command
export FLAC_LIST_FILE="${LOG_DIR}/flac_list"
export MP3_LIST_FILE="${LOG_DIR}/mp3_list"
# Raw output from analysis
export FLAC_LOG_FILE="${LOG_DIR}/flac_check_log"
export MP3_LOG_FILE="${LOG_DIR}/mp3_check_log"
# Cleaned list of erroneous files
export FLAC_ERROR_LIST="${LOG_DIR}/flac_errors"
export MP3_ERROR_LIST="${LOG_DIR}/mp3_errors"

# above 2, HDD saturates...
# increase if working with SSDs
ncore=8

# 1. initialize file list & log files
mkdir -p "${LOG_DIR}"
echo " -- Listing FLAC files"
find "${ZIK_DIR}" -iname "*.flac" >"${FLAC_LIST_FILE}"
echo " -- Listing MP3 files"
find "${ZIK_DIR}" -iname "*.mp3" >"${MP3_LIST_FILE}"

echo " -- Reset log files"
echo -n "" >"${FLAC_LOG_FILE}"
echo -n "" >"${FLAC_ERROR_LIST}"
echo -n "" >"${MP3_LOG_FILE}"
echo -n "" >"${MP3_ERROR_LIST}"

# 2. analyse folder
# single folder version:
# for file in *.flac; do flac -wst "$file" ; done
# for file in *.mp3; do mp3val -si "$file" ; done

function flac_check() {
    FLAC_FILE="${1}"
    ESCAPED_FILENAME=$(printf '%q' "${FLAC_FILE}")
    "${FLAC}" -wst "${FLAC_FILE}" 2>&1 | sed -r "s<^<${ESCAPED_FILENAME}:<g" >>"${FLAC_LOG_FILE}"
}
export -f flac_check
function mp3_check() {
    MP3_FILE="${1}"
    #echo "$MP3_FILE"
    "${MP3VAL}" -si "${MP3_FILE}" | grep -v '^Done!\|^Analyzing file' >>"${MP3_LOG_FILE}"
}
export -f mp3_check

set +e
echo " -- Checking flac ..."
cat "${FLAC_LIST_FILE}" | parallel --bar -j $ncore --max-args 1 flac_check {}
echo " -- Checking MP3 ..."
cat "${MP3_LIST_FILE}" | parallel --bar -j $ncore --max-args 1 mp3_check {}
set -e

# 3. clean logs
echo " -- Clean MP3 log results ..."
cat "${MP3_LOG_FILE}" | cut -d":" -f2 | rev | cut -d'"' -f2 | rev | grep "^${ZIK_DIR}" | sort -u >"${MP3_ERROR_LIST}"

echo " -- Clean FLAC log results ..."
cat "${FLAC_LOG_FILE}" | grep "^${ZIK_DIR}" | cut -d":" -f1 | sort -u >"${FLAC_ERROR_LIST}"

echo " -- Done."
echo " -- Logs in '${LOG_DIR}'"
echo " --"
exit 0

########################################
##  EXTENSION CHECK & CLEANUP
########################################
#
# Looks for all extensions found in the library and list them
# Uncomment to clean the blacklisted ones (covers, playlists, etc.)
# Uncomment to remove empty directories
#

EXTS=$(find -type f | rev | cut -d"." -f1 | rev | tr '[:upper:]' '[:lower:]' | sort -u)

echo "All extensions found:"
echo $EXTS
echo "--"

BLACKLIST="pls qdat rtf tif cdp cdq webp aucdtect ffp md5
    html ico inf doc ds_store es exe 00j 00n 00s 00t
    pdf txt jpg jpeg png bmp gif log info ini m3u m3u8 nfo sfv db tiff accurip"

for EXT in $EXTS; do
    if [[ $BLACKLIST =~ (^|[[:space:]])$EXT($|[[:space:]]) ]]; then
        echo " >> DELETE $EXT"
        # find . -type f -iname "*.$EXT"
        # find . -type f -iname "*.$EXT" -exec rm {} \;
    else
        echo " >> Keep $EXT"
    fi
done

find . -type d -empty
# find . -type d -empty -delete

exit 0

########################################
##  FORMAT CONVERT (Manual)
########################################
#
# convert lossless audio to FLAC
# convert lossy audio to MP3
# split FLAC/CUE files
#

#### convert * to flac
for file in *; do ffmpeg -i "$file" -f flac "${file%.*}.flac"; done
#### convert * to mp3 V0
for file in *; do ffmpeg -i "$file" -qscale:a 0 "${file%.*}.mp3"; done
#### convert MIDI to MP3 64
for file in *.mid; do timidity "$file" -Ow -o - | ffmpeg -i - -acodec libmp3lame -ab 64k "${file%.*}.mp3"; done
#### convert DSF to FLAC /!\ Check rate before running command
for i in *.dsf; do dsf2flac -i "$i" -r 352800 -o - | flac -8 - -o "${i%.*}.flac"; done
#### Downsample FLAC
for flacFile in *.flac; do ffmpeg -i "${flacFile}" -ar 96000 -sample_fmt s32 "${flacFile%.*}_96kHz-24bits.flac"; done
for flacFile in *.flac; do ffmpeg -i "${flacFile}" -ar 44100 -sample_fmt s16 "${flacFile%.*}_44.1kHz-16bits.flac"; done

#### split cue to flac
shnsplit -o flac -t "%n - %t" -f
shnsplit -o flac -t "%n - %t" -f *.cue *.flac

########################################
##  PATH & FILE NAME CHECK (Manual)
########################################
#
# Make sure all paths/file names are readable from windows & linux
#
# to list files:
find . -name "*[<>:\\|?*\"$(printf '\t')]*"

TMPFILE=$(mktemp)
find . -name "*[<>:\\|?*\"$(printf '\t')]*" > "${TMPFILE}"
while IFS= read -r line
do
  ORIG_FILE_NAME="$line"
  echo $ORIG_FILE_NAME
  FIXED_FILE_NAME=$(echo $ORIG_FILE_NAME | sed "s/[<>:\\|?*\t\"\t]\+/_/g")
  echo $FIXED_FILE_NAME
  mv "${ORIG_FILE_NAME}" "${FIXED_FILE_NAME}"
  echo -e "--\n"
done < "${TMPFILE}"
rm "${TMPFILE}"



########################################
##  Sync 2 Directories
########################################
# NOTE: a slash at the source, but none at dest
# remove "n" option to actually perform
rsync -n --delete -auv --no-times --no-perms --no-owner --no-group "<source>/DATA/" "<dest>/DATA"

# other options :
rsync -n --delete -rv --no-times --no-owner --no-group --no-perms "<source>/DATA/" "<dest>/DATA"
rsync -n --delete -rv --checksum "<source>/DATA/" "<dest>/DATA"
rsync -n --delete -rv --size-only "<source>/DATA/" "<dest>/DATA"

########################################
##  SHNSPLIT all cue/flac files
########################################

ncore=2
function split_cue_flac() {
    CUE_FILE="${1}"
    DIR=$(dirname "${CUE_FILE}")
    CUE_BASENAME=$(basename "${CUE_FILE}")
    ESCAPED_CUE_FILENAME=$(printf '%q' "${CUE_BASENAME}")
    FLAC_FILE=$(find "${DIR}" -type f -iname "${ESCAPED_CUE_FILENAME%.*}.flac")
    FLAC_BASENAME=$(basename "${FLAC_FILE}")
    ESCAPED_FLAC_FILENAME=$(printf '%q' "${FLAC_BASENAME}")
    if [ -f "${FLAC_FILE}" ]; then
        echo " --   OK   : '$CUE_FILE'"
        echo " -- split command:   (cd \"${DIR}\" && shnsplit -o flac -t \"%n - %t\" -f '${CUE_BASENAME}' '${FLAC_BASENAME}')"
        (cd "${DIR}" && shnsplit -o flac -t "%n - %t" -f "${CUE_BASENAME}" "${FLAC_BASENAME}")
        rm "${CUE_FILE}" "${FLAC_FILE}"
    else
        echo " XX NOT OK : '$CUE_FILE'"
    fi
}
export -f split_cue_flac

TMPFILE=$(mktemp)
find -type f -iname "*.cue" >"${TMPFILE}"
cat "${TMPFILE}" | parallel -j $ncore --max-args 1 split_cue_flac {}
rm "${TMPFILE}"
