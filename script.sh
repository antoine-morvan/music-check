#!/bin/bash -eu

########################################
##  MEDIA FILE CHECK
########################################

#### Commands to check for consistency
# use latest FLAC binary compiled from master branch
# in order to avoid having false positive MD5 issues
export FLAC=flac
export MP3VAL=mp3val

#### Folders & paths
export ZIK_DIR="/mnt/DATA/DATA/Zik/zik/Keziah Jones/"
export LOG_DIR=~/music_check_logs

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
find "${ZIK_DIR}" -iname "*.flac" > "${FLAC_LIST_FILE}"
echo " -- Listing MP3 files"
find "${ZIK_DIR}" -iname "*.mp3" > "${MP3_LIST_FILE}"

echo " -- Reset log files"
echo "" > "${FLAC_LOG_FILE}"
echo "" > "${FLAC_ERROR_LIST}"
echo "" > "${MP3_LOG_FILE}"
echo "" > "${MP3_ERROR_LIST}"

# 2. analyse folder
echo " -- Checking flac ..."
function flac_check () {
    FLAC_FILE="${1}"
    ESCAPED_FILENAME=$(printf '%q' "${FLAC_FILE}")
    "${FLAC}" -t -s "${FLAC_FILE}" 2>&1 | sed -r "s#^#${ESCAPED_FILENAME}:#g" >> "${FLAC_LOG_FILE}"
}
export -f flac_check

cat "${FLAC_LIST_FILE}"| parallel --bar -j $ncore --max-args 1 flac_check {}
echo " -- Checking MP3 ..."
function mp3_check () {
    MP3_FILE="${1}"
    #echo "$MP3_FILE"
    "${MP3VAL}" -si "${MP3_FILE}" | grep -v '^Done!\|^Analyzing file' >> "${MP3_LOG_FILE}"
}
export -f mp3_check
cat "${MP3_LIST_FILE}" | parallel --bar -j $ncore --max-args 1 mp3_check {}
set -e

# 3. clean logs
echo " -- Clean MP3 log results ..."
cat "${MP3_LOG_FILE}" | cut -d":" -f2 | rev | cut -d'"' -f2 | rev | grep "^${ZIK_DIR}" | sort -u > "${MP3_ERROR_LIST}"

echo " -- Clean FLAC log results ..."
cat "${FLAC_LOG_FILE}" | grep "^${ZIK_DIR}" | cut -d":" -f1 | sort -u > "${FLAC_ERROR_LIST}"

echo " -- Done."
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

BLACKLIST="pdf txt jpg jpeg png bmp gif log info ini m3u m3u8 nfo sfv db"

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
#find . -type d  -empty -delete

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
#### convert DSF to FLAC /!\ warning with rate
for i in *.dsf; do ffmpeg -i "$i" -ar 192000 "${i%.*}.flac"; done

#### split cue to flac
shnsplit -o flac -t "%n - %t" -f 
shnsplit -o flac -t "%n - %t" -f *.cue *.flac

########################################
##  PATH & FILE NAME CHECK (Manual)
########################################
#
# Make sure all paths/file names are readable from windows & linux
#

# 1.1. on windows: check file name/path issues
# both commands should success
sudo chmod 777 -R .
sudo du -hs .

# 1.2. on linux: rename files with issues
#manualy :o
