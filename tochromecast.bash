#! /bin/bash

# Batch Convert Script by StevenTrux, modified by outlyer
# The Purpose of this Script is to batch convert any video file to mp4 or mkv format for chromecast compatibility
# this script only convert necessary tracks if the video is already
# in H.264 format it won't convert it saving your time!

# Put all video files need to be converted in a folder!
# the name of files must not have " " Space!
# Rename the File if contain space 

# Variable used:
# outmode should be mp4 or mkv
# sourcedir is the directory where to be converted videos are
# indir is the directory where converted video will be created

# usage:
#########################
# cast.sh mp4 /home/user/divx /home/user/chromecastvideos
# or
# cast.sh mkv /home/user/divx /home/user/chromecastvideos
#########################

# Configurable options (original hardcoded value in comments):
PREFERRED_LANGUAGE=spa
ABITRATE="-vbr 5"   # -ab 192k
VBITRATE="-crf 18" # "-qmax 22 -qmin 20". [1] 18 is perceptually near-lossless
PROFILE=high       # main. [2] Highest supported
LEVEL=4.1          # 3.1. [2] Highest officially supported ([3] uses 4.2)
VPROFILE_OPT=-vprofile # -profile:v (this varies with Ffmpeg version)
PRESET="-preset slow"  # None defined. Defaults to medium
QUIET=-hide_banner     # None defined. Removes the FFmpeg banner, build options, etc.
X264OPTS="cabac=1:bframes=3" # no-cabac:ref=2 [3],[4]
LOWPASS=20000 # None defined. Audio frequency cutoff. Defaults to 14k, highest is 20k [5]
# Reference [1]: https://trac.ffmpeg.org/wiki/Encode/H.264
#           [2]: https://developers.google.com/cast/docs/media
#           [3]: http://www.thelins.se/johan/blog/2015/01/plex-and-chromecast/
#           [4]: Plex's Chromecast.xml resource
#           [5]: https://trac.ffmpeg.org/wiki/Encode/AAC

# working mode
outmode=$1
# check output mode
if [[ $outmode ]]; then
if [ $outmode = "mp4" ] || [ $outmode = "mkv" ]
	then 
	echo "WORKING MODE $outmode"
	else
	echo "$outmode is NOT a Correct target format. You need to set an output format! like cast.sh mp4 xxxx or cast.sh mkv xxxx"
	exit
fi
else
echo "Working mode is missing. You should set a correct target format like mp4 or mkv"
exit
fi

# Source dir
sourcedir=$2
if [[ "$sourcedir" ]]; then 
     echo "Using $sourcedir as Input Folder"
	else
	 echo "Error: Check if you have set an input folder"
	 exit
fi

# Target dir
indir=$3
if [[ "$indir" ]]; then 
	if mkdir -p "$indir/castable"
		then
		 echo "Using $indir/castable as Output Folder"
		else
		 echo "Error: Check if you have the rights to write in $indir"
		 exit
	fi
else
 echo "Error: Check if you have set an output folder"
 exit
fi

# set format
if [ $outmode=mp4 ]
	then
	 outformat=mp4
	else
	 outformat=matroska
fi

# Check FFMPEG Installation
if ffmpeg -formats > /dev/null 2>&1 
	then
	 ffversion=`ffmpeg -version 2> /dev/null | grep ffmpeg | sed -n 's/ffmpeg\s//p'`
	 echo "Your ffmpeg verson is $ffversion"
	else
	 echo "ERROR: You need ffmpeg installed with x264 and libfdk_aac encoder"
	 exit
fi

if ffmpeg -formats 2> /dev/null | grep -q "E mp4"
	then
	 echo "Check mp4 container format ... OK"
	else
	 echo "Check mp4 container format ... NOK"
	 exit
fi

if ffmpeg -formats 2> /dev/null | grep -q "E matroska"
        then
         echo "Check mkv container format ... OK"
        else
         echo "Check mkv container format ... NOK"
         exit
fi

if ffmpeg -codecs 2> /dev/null | grep -q "libfdk_aac"
        then
         echo "Check AAC Audio Encoder ... OK"
        else
         echo "Check AAC Audio Encoder ... NOK"
         exit
fi

if ffmpeg -codecs 2> /dev/null | grep -q "libx264"
        then
         echo "Check x264 the free H.264 Video Encoder ... OK"
        else
         echo "Check x264 the free H.264 Video Encoder ... NOK"
         exit
fi

echo "Your FFMpeg is OK Entering File Processing"

################################################################
cd "$sourcedir"
for filelist in *
do
	if ffmpeg -i "$filelist" 2>&1 | grep 'Invalid data found'		#check if it's video file
	   then
	   echo "ERROR File $filelist is NOT A VIDEO FILE can be converted!"
	   continue	   
	
	fi

	if ffmpeg -i "$filelist" 2>&1 | grep Video: | grep -q h264		#check video codec
	   then
	    vcodec=copy
	   else
	    vcodec=libx264
	fi

	if ffmpeg -i "$filelist" 2>&1 | grep Video: | grep -q "High 10"	#10 bit H.264 can't be played by Hardware.
	   then
	    vcodec=libx264
	fi

	audio=$(ffmpeg -i "$filelist" 2>&1 | grep Audio:)
	if [[ 1 < $(echo "$audio" | wc -l) ]]; then
		echo "Multiple audio tracks present"
		preftrack=$(echo "$audio" | grep "\(${PREFERRED_LANGUAGE}\)") 
		if [[ -n "$preftrack" ]] ; then
			echo "> Preferred language detected."
			audio="$preftrack"
		else
			echo "> Preferred language not detected. Defaulting to first track"
			audio=$(head -1 <<<"$audio")
		fi
	fi 

	LOWPASS_OPT=
	# TODO: Chromecast supports AC3 passthrough
	if echo "$audio" | grep -q -E '(aac|mp3)'	#check audio codec
	   then
	    acodec=copy
	   else
	    acodec=libfdk_aac
            LOWPASS_OPT="-cutoff ${LOWPASS}"
	fi
	# If the codec is not AAC, this can break playback
	ABSF=
	if [[ "$acodec" = libfdk_aac ]]; then
		ABSF="-absf aac_adtstoasc"
	fi
	# Map audio track (only required for multi-track files)
	# Does it have language tags?
	if echo "$audio" | grep -qP '\d\(' ; then
		audiotrack=$(echo "$audio" | sed -e 's/^.*Stream #//' -e 's/(.*$//')
	else
		audiotrack=$(echo "$audio" | sed -e 's/^.*Stream #//' -e 's/: .*$//')

	fi
	videotrack=$(ffmpeg -i "$filelist" 2>&1 | grep Video: | sed -e 's/^.*Stream #//' -e 's/(.*$//' -e 's/: .*$//')
	if [[ ( -z "$audiotrack" ) || ( -z "$videotrack" ) ]]; then
		echo "Track selection failed"
		exit 1
	fi

	echo "Converting $filelist"
	echo "Video codec: $vcodec. Audio codec: $acodec. Container: $outformat." 
	echo "Video track: $videotrack. Audio track: $audiotrack."

# using ffmpeg for real converting
	echo "ffmpeg $QUIET -i $filelist -map $videotrack -map $audiotrack -y -f $outformat -acodec $acodec $ABITRATE -ac 2 $ABSF $LOWPASS_OPT -async 1 -vcodec $vcodec $PRESET -vsync 0 $VPROFILE_OPT $PROFILE -level $LEVEL $VBITRATE -x264opts $X264OPTS -movflags faststart -threads 0 $indir/castable/$filelist.$outmode"
	ffmpeg $QUIET -i "$filelist" -map "$videotrack" -map "$audiotrack" -y -f $outformat -acodec $acodec $ABITRATE -ac 2 $ABSF $LOWPASS_OPT -async 1 -vcodec $vcodec $PRESET -vsync 0 $VPROFILE_OPT $PROFILE -level $LEVEL $VBITRATE -x264opts $X264OPTS -movflags faststart -threads 0 "$indir/castable/$filelist.$outmode"

	
done
	echo ALL Processed!

###################
echo "DONE, your video files are chromecast ready"

