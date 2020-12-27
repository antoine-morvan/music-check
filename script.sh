#!/bin/bash -eu

########################################
##  MEDIA FILE CHECK
########################################

#### Commands to check for consistency
# use latest FLAC binary compiled from master branch
# in order to avoid having false positive MD5 issues
FLAC="/usr/local/bin/flac"
MP3VAL=mp3val

#### Folders & paths
ZIK_DIR="/mnt/DATA/DATA/Zik/zik/"
LOG_DIR=~/

FLAC_LIST_FILE="${LOG_DIR}/flac_list"
FLAC_LOG_FILE="${LOG_DIR}/flac_test_log"
FLAG_ERROR_LOG_FILE="${FLAC_LOG_FILE}_error"
MP3_LIST_FILE="${LOG_DIR}/mp3_list"
MP3_LOG_FILE="${LOG_DIR}/mp3_test_log"
MP3_ERROR_LOG_FILE="${MP3_LOG_FILE}_error"

ncore=$(nproc)

echo "" > "${FLAC_LOG_FILE}"
echo "" > "${FLAG_ERROR_LOG_FILE}"
echo "" > "${MP3_LOG_FILE}"
echo "" > "${MP3_ERROR_LOG_FILE}"

find "${ZIK_DIR}" -iname "*.flac" > "${FLAC_LIST_FILE}"
find "${ZIK_DIR}" -iname "*.mp3" > "${MP3_LIST_FILE}"

set +e

echo " -- Checking flac ..."
cat "${FLAC_LIST_FILE}"| parallel --bar -j $ncore -I§ --max-args 1 "\
    ${FLAC} -t -s § >> ${FLAC_LOG_FILE} 2>> ${FLAG_ERROR_LOG_FILE}"

echo " -- Checking MP3 ..."
cat "${MP3_LIST_FILE}" | parallel --bar -j $ncore -I§ --max-args 1 "\
    ${MP3VAL} -si § | grep -v '^Done!\|^Analyzing file' >> ${MP3_ERROR_LOG_FILE}"

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
