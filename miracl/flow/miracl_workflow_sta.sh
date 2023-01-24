#!/usr/bin/env bash
set -e

# get version
function getversion()
{
	ver=`cat ${MIRACL_HOME}/version.txt`
	printf "MIRACL pipeline v$ver \n"
}


# help/usage function
function usage()
{

    cat <<usage

    Workflow (wrapper) for structure tensor analysis (STA):

    1) Converts Tiff stack to nii (& down-sample)
    2) Uses registered labels to create seed mask & creates brain mask
	3) Run STA analysis

    Executes:
        conv/miracl_conv_convertTifftoNII.py
        lbls/miracl_lbls_get_graph_info.py
        lbls/miracl_lbls_generate_parents_at_depth.py
        utilfn/miracl_extract_lbl.py
        utilfn/miracl_create_brain_mask.py
        sta/miracl_sta_track_primary_eigen.py
        lbls/miracl_lbls_stats.py
        sta/miracl_sta_gen_tract_density.py

    Usage: `basename $0`

        A GUI will open to choose folder with tif files for STA and the registered Allen labels

        and choosing STA parameters
  
    ----------

	For command-line / scripting

    Usage: `basename $0` -f [Tiff folder] -o [output nifti] -l [Allen seed label] -m [ hemisphere ] -r [Reg final dir] -d [ downsample ratio ]

    Example: `basename $0` -f my_tifs -o clarity_virus -l PL -m combined -r clar_reg_final -d 5 -c AAV g 0.5 -k 0.5 -a 25

    Or for right PL:

    Example: `basename $0` -f my_tifs -o clarity_virus -l RPL -m split -r clar_reg_final -d 5 -c AAV -g 0.5 -k 0.5 -a 25

        arguments (required):
            -f: Input Clarity tif folder/dir [folder name without spaces]
            -o: Output nifti
            -l: Seed label abbreviation (from Allen atlas ontology)
            -r: CLARITY final registration folder
            -m: Labels hemi
            -g: [ Derivative of Gaussion (dog) sigma ]
            -k: [ Gaussian smoothing sigma ]
            -a: [ Tracking angle threshold ]

        optional arguments:
            -d: Downsample ratio (default: 5)
            -c: Output channel name
            -n: Chan # for extracting single channel from multiple channel data (default: 0)
            -p: Chan prefix (string before channel number in file name). ex: C00
            -x: Original resolution in x-y plane in um (default: 5)
            -z: Original thickness (z-axis resolution / spacing between slices) in um (default: 5)
            -b: Brain mask (to replace brain mask automatically generated by workflow)
            -u: Seed mask (in place of regional seed mask generated by workflow)
            -s: Step length
            --downz: Downsample in z
            --dilationfx: Dilation factor for x (factor to dilate seed label by)
            --dilationfy: Dilation factor for y (factor to dilate seed label by)
            --dilationfz: Dilation factor for z (factor to dilate seed label by)
            --rk: Use 2nd order range-kutta method for tracking (default: 0)
            --out_dir: Output directory

	----------
	Main Outputs
        tract file = clarity_sta_[label]_seed/dog[dog]_gauss[gauss]/filter_ang[angle].trk
        virus stats csv = virus_signal_stats_depth_[depth].csv
        streamline density stats csv = sta_streamlines_density_stats_depth_[depth].csv
    ----------

usage
getversion >&2

}


# Call help/usage function
if [[ "$1" == "-h" || "$1" == "--help" || "$1" == "-help" ]]; then

    usage >&2
    exit 1

fi


#----------------------

# check dependencies

if [[ -z ${MIRACL_HOME} ]];
then

    printf "\n ERROR: MIRACL not initialized .. please run init/setup_miracl.sh  & rerun script \n"
	exit 1

fi

c3dpath=`which c3d`
if [ -z ${c3dpath} ];
then
    abspath_pwd="$( cd "$(dirname "$0")" ; pwd -P )"
    c3dpath="${abspath_pwd}/../../depends/c3d/bin"
    export PATH="$PATH:${abspath_pwd}/../../depends/c3d/bin"
fi

test_c3dpath=`which c3d`
if [ -z ${test_c3dpath} ];
then
    printf "\n ERROR: c3d not initialized .. please setup miracl & rerun script \n"
	exit 1
else
	printf "\n c3d path check: OK... \n"
fi


#----------------------

# get time

START=$(date +%s)


# output log file of script

exec > >(tee -i workflow_sta.log)
exec 2>&1

#---------------------------
#---------------------------

function choose_folder_gui()
{
	local openstrfol=$1
	local _inpathfol=$2

    folderpath=$(${MIRACL_HOME}/conv/miracl_conv_file_folder_gui.py -f folder -s "$openstrfol")

	folderpath=`echo "${folderpath}" | cut -d ':' -f 2 | sed -e 's/^ "//' -e 's/"$//'`

#	folderpath=`cat path.txt`

	eval ${_inpathfol}="'$folderpath'"

#	rm path.txt

}

function choose_file_gui()
{
	local openstrfil=$1
	local _inpathfil=$2

    filepath=$(${MIRACL_HOME}/conv/miracl_conv_file_folder_gui.py -f file -s "$openstrfil")

	filepath=`echo "${filepath}" | cut -d ':' -f 2 | sed -e 's/^ "//' -e 's/"$//'`

	eval ${_inpathfil}="'$filepath'"

}


# Select Mode : GUI or script

if [[ "$#" -gt 1 ]]; then

	printf "\n Running in script mode \n"

  printf "\n Reading input parameters \n"

  # Custom arg parser
  while :; do
    case "$1" in

      -h|--help)
        usage
        exit 0
        ;;

      -f|--folder)
        indir="$2"
        shift
        ;;

      -o|--out_nii)
        nii="$2"
        shift
        ;;

      -l|--seed_label)
        lbl="$2"
        shift
        ;;

      -r|--clar_reg)
        regdir="$2"
        shift
        ;;

      -m|--hemi)
        hemi="$2"
        shift
        ;;

      -g|--dog)
        dog="$2"
        shift
        ;;

      -k|--sigma)
        gauss="$2"
        shift
        ;;

      -a|--angle)
        angle="$2"
        shift
        ;;

      -d|--down)
        down="$2"
        shift
        ;;

      -c|--chan)
        chan="$2"
        shift
        ;;

      --out_dir)
        out_dir="$2"
        shift
        ;;

      -b|--brain_mask)
        brain_mask="$2"
        shift
        ;;

      -u|--lbl_mask)
        lbl_mask="$2"
          shift
        ;;

      -s|--step_length)
        step_length="$2"
        shift
        ;;

      -n|--chan_num)
        chann="$2"
        shift
        ;;

      -p|--chan_pre)
        chanp="$2"
        shift
        ;;

      -x|--vx)
        vx="$2"
        shift
        ;;

      -z|--vz)
        vz="$2"
        shift
        ;;

      --downz)
        downz="$2"
        shift
        ;;

      --dilationfx)
        dilationfx="$2"
        shift
        ;;

      --dilationfy)
        dilationfy="$2"
        shift
        ;;

      --dilationfz)
        dilationfz="$2"
        shift
        ;;

      --rk)
        rk2="$2"
        shift
        ;;

      *)
        break 
    esac
    shift
  done

  ### TEST PARSED ARGS ###
  printf "TEST PARSE ARGS\n"
  printf "f, indir: ${indir}\n"
  printf "o, nii: ${nii}\n"
  printf "l, lbl: ${lbl}\n"
  printf "r, regdir: ${regdir}\n"
  printf "m, hemi: ${hemi}\n"
  printf "g, dog: ${dog}\n"
  printf "k, gauss: ${gauss}\n"
  printf "a, angle: ${angle}\n"
  printf "d, down: ${down}\n"
  printf "c, chan: ${chan}\n"
  printf "q, out_dir: ${out_dir}\n"
  printf "b, brain_mask: ${brain_mask}\n"
  printf "u, lbl_mask: ${lbl_mask}\n"
  printf "s, step_length: ${step_length}\n"
  printf "i (no), convopts: ${convopts}\n"
  printf "n, chann: ${chann}\n"
  printf "p, chanp: ${chanp}\n"
  printf "x, vx: ${vx}\n"
  printf "z, vz: ${vz}\n"
  printf "downz: ${downz}\n"
  printf "dilationfx: ${dilationfx}\n"
  printf "dilationfy: ${dilationfy}\n"
  printf "dilationfz: ${dilationfz}\n"
  printf "rk: ${rk2}\n"

	# Check required input arguments
  
  # If any of the required arguments are missing print an error message
  if [[ "${indir}" == None ]] || [[ "${nii}" == None ]] || [[ "${lbl}" == None ]] || [[ "${regdir}" == None ]];
  then
    usage
    printf "\n---------------------------------\n"
    printf "\nRequired arguments are missing!\n"
  fi
  
  # List which required arguments are missing
	if [[ "${indir}" == None ]];
  then
    printf "\nERROR: input folder (-f) with clarity tifs not specified.\n"
  fi

  if [[ "${nii}" == None ]];
  then
    printf "\nERROR: output nii (-o) not specified.\n"
  fi

  if [[ "${lbl}" == None ]];
  then
    printf "\nERROR: Input seed label (-l) not specified.\n"
  fi

  if [[ "${regdir}" == None ]];
	then
    printf "\nERROR: Input reg dir (-r) not specified.\n"
	fi

  # Print fix to error message and exit with exit code message.
  if [[ "${indir}" == None ]] || [[ "${nii}" == None ]] || [[ "${lbl}" == None ]] || [[ "${regdir}" == None ]];
  then
    ERRCODE=$?
    printf "\nPlease fix the above error(s) by providing the missing arguments. Exiting with code $ERRCODE.\n"
    printf "\n---------------------------------\n\n"
    exit $ERRCODE
  fi

	then
		down=5
  else
    # Check if downsample value is single digit and prepend 0 if true
    printf -v down "%02d" $down
	fi

  if [[ "${hemi}" == None ]] || ([[ "${hemi}" != "split" ]] && [[ "${hemi}" != "combined" ]]);
  then
    printf '\nNOTE: Hemisphere argument (-m) not recognized. Defaulting to "combined".\n'
		hemi="combined"
  fi

    if [[ -z "${chan}" ]];
	then
		chan="virus"
	fi
  if [[ "${dog}" == None ]] || ! [[ "${dog}" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]];
  then
    printf '\nNOTE: Derivative of Gaussian sigma (-g) not recognized. Defaulting to "0.5,1.5".\n'
    dog="0.5,1.5"
  fi

    if [[ -z "${chann}" ]];
	then
		chann=0
	fi
  if [[ "${gauss}" == None ]] || ! [[ "${gauss}" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]];
  then
    printf '\nNOTE: Gaussian smoothing sigma (-k) not recognized. Defaulting to "0.5,2".\n'
    gauss="0.5,2"
  fi

    if [[ -z "${chanp}" ]];
	then
		chanp=""
	fi
  if [[ "${angle}" == None ]] || ! [[ "${angle}" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]];
  then
    printf '\nNOTE: Tracking angle threshold (-a) not recognized. Defaulting to "25,35".\n'
    angle="25,35"
  fi

    if [[ -z "${vx}" ]];
	then
		vx=5
	fi

    if [[ -z "${vz}" ]];
	then
		vz=5
	fi

    if ! [[ "$dilationfx" =~ ^[0-9]+$ ]];
    then
        dilationfx=0
    fi

    if ! [[ "$dilationfy" =~ ^[0-9]+$ ]];
    then
        dilationfy=0
    fi

    if ! [[ "$dilationfz" =~ ^[0-9]+$ ]];
    then
        dilationfz=0
    fi

    if [[ "$dilationfx" -gt 0 ]] && [[ "$dilationfy" -gt 0 ]] && [[ "$dilationfz" -gt 0 ]]; then
        dilationf="${dilationfx}x${dilationfy}x${dilationfz}"
    fi

    if [[ "${step_length}" == "None" ]];
    then
        step_length=0.1
    fi

  if [[ "${out_dir}" == "None" ]]; then
      #out_dir="clarity_sta_${lbl////_}_seed"
      out_dir=""
  fi

    if [[ "${lbl_mask}" == "None" ]];
	then
		lbl_mask=""
	fi

else

	# call gui

	printf "\n No inputs given ... running in GUI mode \n"

    # Get options
#    choose_folder_gui "Open clarity dir (with .tif files) by double clicking then OK" indir

	# options gui
	opts=$(${MIRACL_HOME}/conv/miracl_conv_gui_options.py -t "STA workflow"  \
	        -d "Input tiff folder" "CLARITY final registration folder" \
	        -f "Out nii name (def = clarity)" "Seed label abbreviation" "hemi (combined or split)" \
	           "Derivative of Gaussian (dog) sigma" "Gaussian smoothing sigma" "Tracking angle threshold" \
 	          "Downsample ratio (def = 5)"  "chan # (def = 1)" "chan prefix" \
              "Out chan name (def = AAV)" "Resolution (x,y) (def = 5 um)" "Thickness (z) (def = 5 um)" \
              "Downsample in z (def = 1)" "Dilation factor for x axis (def = 0)" \
               "Dilation factor for y axis (def = 0)"  "Dilation factor for z axis (def = 0)" \
               "Step length (def 0.1)" "Use 2nd order range-kutta method for tracking (def 0)" "Output directory" \
               -v "Brain mask (optional)" "Seeding label mask (optional)" -hf "`usage`")

	# populate array
	arr=()
	while read -r line; do
	   arr+=("$line")
       echo $line
	done <<< "$opts"

    # check required input arguments

    brain_mask="$(echo -e "${arr[0]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    # regdir=`echo "${arr[1]}" | cut -d ':' -f 2 | sed -e 's/^ "//' -e 's/"$//'`
    printf "\n Chosen brain mask: $brain_mask \n"

    lbl_mask="$(echo -e "${arr[1]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${nii}" ]]; then nii='clarity'; fi
    printf "\n Chosen label mask: $lbl_mask \n"

    indir="$(echo -e "${arr[2]}" | cut -d ':' -f 2 | tr -d '[:space:]')"

	if [[ -z "${indir}" ]];
	then
		usage
		echo "ERROR: <input clarity directory> was not chosen"
		exit 1
	fi

	printf "\n Chosen in dir: $indir \n"

    regdir="$(echo -e "${arr[3]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    # regdir=`echo "${arr[1]}" | cut -d ':' -f 2 | sed -e 's/^ "//' -e 's/"$//'`
    printf "\n Chosen reg dir: $regdir \n"

    nii="$(echo -e "${arr[4]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${nii}" ]]; then nii='clarity'; fi
    printf "\n Chosen out nii name: $nii \n"

    lbl="$(echo -e "${arr[5]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    printf "\n Chosen seed label: $lbl \n"

    hemi="$(echo -e "${arr[6]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [ "${hemi}" != "combined" ] || [ "${hemi}" != "split" ] || [ -z "${hemi}" ]; then
        echo "\n NOTE: User must select either 'combined' or 'split' for 'hemi' field. Defaulting to 'combined'"
        hemi="combined"
    fi
    printf "\n Chosen label hemi: $hemi \n"

    dog="$(echo -e "${arr[7]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${dog}" ]]; then dog="0.5,1.5"; fi
    printf "\n Chosen Derivative of Gaussian : $dog \n"

    gauss="$(echo -e "${arr[8]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${gauss}" ]]; then gauss="0.5,2"; fi
    printf "\n Chosen Gaussian smoothing sigma: $gauss \n"

    angle="$(echo -e "${arr[9]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${angle}" ]]; then angle="25,35"; fi
    printf "\n Chosen tracking angle threshold: $angle \n"

    down="$(echo -e "${arr[10]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${down}" ]]; then down=5; fi
    down=$( printf "%02d" $down ) # add leading zeros
    printf "\n Chosen downsample ratio: $down \n"
    
    chann="$(echo -e "${arr[11]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${chann}" ]]; then chann="1"; fi
    printf "\n Chosen channel num: $chann \n"

    chanp="$(echo -e "${arr[12]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${chanp}" ]]; then chanp=""; fi
    printf "\n Chosen channel prefix: $chanp \n"

    chan="$(echo -e "${arr[13]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${chan}" ]]; then chan="AAV"; fi
    printf "\n Chosen chan name: $chan \n"

    vx="$(echo -e "${arr[14]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${vx}" ]]; then vx=5; fi
    printf "\n Chosen vx: $vx \n"

    vz="$(echo -e "${arr[15]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${vz}" ]]; then vz=5; fi
    printf "\n Chosen vz: $vz \n"

    downz="$(echo -e "${arr[16]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${downz}" ]]; then downz=1; fi
    printf "\n Chosen down-sample in z: $downz \n"

    dilationfx="$(echo -e "${arr[17]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${dilationf}" ]]; then dilationfx=0; fi
    dilationfy="$(echo -e "${arr[18]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${dilationf}" ]]; then dilationfy=0; fi    
    dilationfz="$(echo -e "${arr[19]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${dilationf}" ]]; then dilationfz=0; fi

    if [[ "${dilationfx}" -gt 0 ]] && [[ "${dilationfy}" -gt 0 ]] && [[ "${dilationfz}" -gt 0 ]]; then
        dilationf="${dilationfx}x${dilationfy}x${dilationfz}"
        printf "\n Chosen dilation factor (across all dimensions): $dilationf \n"
    else
        printf "\n Dilation not selected, as factor across all dimensions is 0 \n"
    fi

    step_length="$(echo -e "${arr[20]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${step_length}" ]]; then step_length="0.1"; fi
    printf "\n Chosen step length: $step_length \n"

    rk2="$(echo -e "${arr[21]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if ! [[ -z "${rk2}" ]]; then rk2=0; fi

    out_dir="$(echo -e "${arr[22]}" | cut -d ':' -f 2 | tr -d '[:space:]')"
    if [[ -z "${out_dir}" ]]; then 
        out_dir=""; 
    else
        printf "\n Output directory set to $out_dir \n"
    fi

fi

printf "Chosen variables are:\nfolder: ${indir}\nOuput nifti: ${nii}\nSeed label: ${lbl}\nReg folder: ${regdir}\nHemi: ${hemi}\nDownsample ratio: ${down}\nChannel name: ${chan}\nOutput directory: ${out_dir}\nStep length: ${step_length}\nSeed mask: ${lbl_mask}"

# start processing steps

# ---------------------------
# Call conversion to nii

nii_file=${indir}/${nii}_${down}x_down_${chan}_chan.nii.gz

if [[ ! -f ${nii_file} ]]; then

    printf "\n Running conversion to nii with the following command: \n"

    if [[ -n ${chanp} ]]; then
        printf "\n miracl conv tiff_nii -f ${indir} -d ${down} -o ${nii} -dz ${downz} -ch ${chan} -cn ${chann} -cp ${chanp} \n"
        miracl conv tiff_nii -f ${indir} -d ${down} -o ${nii} -dz ${downz} \
                                       -ch ${chan} -cn ${chann} -cp ${chanp} -vx ${vx} -vz ${vz}
    else
        printf "\n miracl conv tiff_nii -f ${indir} -d ${down} -o ${nii} -dz ${downz} -ch ${chan}\n"
        miracl conv tiff_nii -f ${indir} -d ${down} -o ${nii} -dz ${downz} -ch ${chan} -vx ${vx} -vz ${vz}
    fi

else

    printf "\n Nifti file already created for this channel\n"

fi

#---------------------------
# Call extract lbl

reg_lbls=${regdir}/annotation_hemi_${hemi}_??um_clar_space_downsample.nii.gz

if [[ "${hemi}" == "combined" ]]; then
    # get chosen depth
    echo "miracl lbls graph_info -l ${lbl} | grep depth | tr -dc '0-9'"
    depth=`miracl lbls graph_info -l ${lbl} | grep depth | tr -dc '0-9'`

else

    clbl=${lbl:1:${#lbl}}
    if [[ $(miracl lbls graph_info -l $clbl 2>/dev/null) ]];
    then
            echo "miracl lbls graph_info -l ${clbl} | grep depth | tr -dc '0-9'"
            depth=$(miracl lbls graph_info -l $clbl | grep depth | tr -dc '0-9' 2>/dev/null)
   
    elif [[ $(miracl lbls graph_info -l $lbl 2>/dev/null) ]];
    then
            echo "miracl lbls graph_info -l ${lbl} | grep depth | tr -dc '0-9'"
            depth=$(miracl lbls graph_info -l $lbl | grep depth | tr -dc '0-9' 2>/dev/null)
   
    else
            printf "Error: $lbl is not a label id, label name, OR label acronym. Please consult /code/atlases/ara/ara_mouse_structure_graph_hemi_${hemi}.csv to see possible values\n"
            exit 1
    fi

fi


# Generate label mask at depth of ROI
deep_lbls=annotation_hemi_${hemi}_??um_clar_space_downsample_depth_${depth}.nii.gz

if [[ ! -f ${deep_lbls} ]]; then

    printf "\n Generating grand parent labels for ${lbl} at depth ${depth} \n"

    echo "miracl lbls gp_at_depth -l ${reg_lbls} -d ${depth}"
    miracl lbls gp_at_depth -l ${reg_lbls} -d ${depth}

    echo "c3d ${reg_lbls} ${deep_lbls} -copy-transform -o ${deep_lbls}"
    c3d ${reg_lbls} ${deep_lbls} -copy-transform -o ${deep_lbls}

else

    printf "\n Grand parent labels already created at this depth \n"

fi

if [[ -z ${lbl_mask} ]]; then

    lbl_mask="${lbl////_}_mask.nii.gz"

else

    printf "\n Using seed mask selected by user: ${lbl_mask} \n"

fi

if [[ ! -f ${lbl_mask} ]]; then

    printf "\n Running label extraction with the following command: \n"

    printf "\n miracl utils extract_lbl -i ${deep_lbls} -l ${lbl} -m ${hemi} \n"
    miracl utils extract_lbl -i ${deep_lbls} -l ${lbl} -m ${hemi}

    # dilate mask based on dilation factor
    if [[ ${dilationf} ]]; then 
        printf "\n dilating label mask by ${dilationf} voxels across all dimensions with the following command: \n"

        orig_mask="${lbl////_}_mask_orig.nii.gz"  # store the original mask
        cp "$lbl_mask" "$orig_mask"
        printf "\n c3d ${lbl_mask} -dilate 1 ${dilationf}vox -o ${lbl_mask}"

        c3d "${lbl_mask}" -dilate 1 ${dilationf}vox -o "${lbl_mask}"
    fi

    # fslcpgeom "${nii_file}" "${lbl_mask}"
    c3d "${nii_file}" "${lbl_mask}" -copy-transform -o "${lbl_mask}"

else

    printf "\n Label mask already created \n"

fi

#---------------------------
# Call create brain mask

if [[ ! -z ${brain_mask} ]]; then

    brain_mask=clarity_brain_mask.nii.gz

else

    printf "\n Using brain mask input by user: ${brain_mask} \n"

fi


if [[ ! -f ${brain_mask} ]]; then

    printf "\n Running brain mask creation with the following command: \n"

    printf "\n miracl utilfn brain_mask -i ${nii_file} \n"
    miracl utils brain_mask -i ${nii_file}

else

    printf "\n Brain mask already created \n"

fi

#---------------------------
# Call STA

# Call lbl stats

lbl_stats=virus_signal_stats_depth_${depth}.csv

if [[ ! -f ${lbl_stats} ]]; then

    printf "\n Computing signal statistics with the following command: \n"

    printf "\n miracl lbls stats -i ${nii_file} -l ${deep_lbls} -o ${lbl_stats} -m ${hemi} -d ${depth} -s Max \n"
    miracl lbls stats -i ${nii_file} -l ${deep_lbls} -o ${lbl_stats} -m ${hemi} -d ${depth} -s Max

else

    printf "\n Signal statistics already computed at this depth \n"

fi

# generate signal graph for virus signal connectivity
# signal_graph=virus_signal_connectivity_graph_depth_${depth}.html

# if [[ ! -f ${signal_graph} ]]; then
#     printf " \n Generating virus signal connectivity graph with the following command: \n "

#     printf "\n miracl sta conn_graph -l ${lbl_stats} -s ${hemi} -r ${lbl} -o ${signal_graph} \n "
#     miracl sta conn_graph -l ${lbl_stats} -s ${hemi} -r ${lbl} -o ${signal_graph}
# else
#     printf "\n Virus signal connectivity graph already computed at this depth \n"
# fi

#---------------------------

# set output directory based on label seed if not done as initial input
if [[ -z "${out_dir}" ]]; then
    out_dir="clarity_sta_${lbl////_}_seed"
fi

# gen tract density map

# loop over all derivative of gaussian and gaussian smoothing values
for dog_sigma in ${dog//,/ }; do

    for gauss_sigma in ${gauss//,/ }; do

        for angle_val in ${angle//,/ }; do

            for step in ${step_length//,/ }; do
            
                sta_dir=${out_dir}/dog${dog_sigma}gau${gauss_sigma}step${step}
                tracts=${sta_dir}/fiber_ang${angle_val}.trk
                dens_map=${sta_dir}/sta_streamlines_density_map.nii.gz
                dens_map_clar=${sta_dir}/sta_streamlines_density_map_clar_space_angle_${angle_val}.nii.gz
                ga_vol=${sta_dir}/ga.nii.gz

                #---------------------------
                # Call STA

                printf "\n Running STA with the following command: \n"
                if [[ ! -f "${tracts}" ]]; then
                    if [[ -n "${rk2}" ]]; then
                        printf "\n miracl sta track_tensor -i ${nii_file} -b clarity_brain_mask.nii.gz -s ${lbl_mask}  \
                                   -dog ${dog_sigma} -gauss ${gauss_sigma} -angle ${angle_val} -sl ${step} -o ${out_dir} -sl -r \n"
                        miracl sta track_tensor -i ${nii_file} -b clarity_brain_mask.nii.gz -s ${lbl_mask} \
                                                         -g ${dog_sigma} -k ${gauss_sigma} -a ${angle_val} -sl ${step} -o ${out_dir} -r
                    else
                        printf "\n miracl sta track_tensor -i ${nii_file} -b clarity_brain_mask.nii.gz -s ${lbl_mask}  \
                                   -dog ${dog_sigma} -gauss ${gauss_sigma} -angle ${angle_val} -sl ${step} -o ${out_dir} \n"
                        miracl sta track_tensor -i ${nii_file} -b clarity_brain_mask.nii.gz -s ${lbl_mask} \
                                                         -g ${dog_sigma} -k ${gauss_sigma} -a ${angle_val} -sl ${step} -o ${out_dir}
                    fi
                else
                    printf "\n Tracts already generated \n "
                fi

                
                # Generate tract density map
                if [[ ! -f ${dens_map_clar} ]]; then

                    printf "\n Generating tract density map with the following command: \n"

                    printf "\n miracl sta tract_density -t ${tracts} -r ${ga_vol} -o ${dens_map} \n"
                    miracl sta tract_density -t ${tracts} -r ${ga_vol} -o ${dens_map}

                    echo "c3d ${nii_file} ${dens_map} -copy-transform ${dens_map_clar}"
                    c3d ${nii_file} ${dens_map} -copy-transform -o ${dens_map_clar}

                else

                    printf "\n Tract density map already generated \n "

                fi

                # gen label stats for density
                dens_stats=${sta_dir}/sta_streamlines_density_stats_depth_${depth}_angle_${angle_val}.csv

                if [[ ! -f ${dens_stats} ]]; then
                    printf "\n Computing tract density statistics with the following command: \n"

                    printf "\n miracl lbls stats -i ${dens_map_clar} -l ${deep_lbls} -o ${dens_stats} -m ${hemi} -d ${depth} \n"
                    miracl lbls stats -i ${dens_map_clar} -l ${deep_lbls} -o ${dens_stats} -m ${hemi} -d ${depth}

                    printf "\n Generating figure of tract density statistics with the following command: \n"

                    printf "\n miracl stats plot_subj -i ${dens_stats} \n"
                    miracl stats plot_subj -i ${dens_stats}

                else
                    printf "\n Tract density statistics already computed at this depth \n"
                fi

                tckmap=$( which tckmap )
                tract_tck=${sta_dir}/fiber_ang${angle_val}.tck
                endpoints="${sta_dir}/sta_endpoints_clar_space_angle_${angle_val}.nii.gz"
                endpoints_stats="${sta_dir}/sta_endpoints_density_stats_depth_${depth}_angle_${angle_val}.csv"
                # generate endpoints, stats and chart iff tckmap exists, and 
                if [[ ! -f "${endpoints_stats}" ]] && [[ -n "${tckmap}" ]]; then
                    # generate tck file for endpoints
                    printf "\n Converting tracts from trk to tck using the following command: \n"

                    printf "\n miracl conv trk -ot tck ${tracts} \n"
                    miracl conv trk -t "${tracts}"

                    if [[ ! -f "${endpoints}" ]]; then
                        # generate endpoints
                        printf "\n Using tck image to generate endpoints using the following command: \n"


                        printf "\n miracl sta tract_endpoints -t ${tract_tck} -r ${ga_vol} -o ${endpoints} \n"
                        miracl sta tract_endpoints -t "${tract_tck}" -r "${ga_vol}" -o "${endpoints}"

                    fi
                    printf "\n Computing tract endpoints statistics with the following command: \n"

                    printf "\n miracl lbls stats -i ${endpoints} -l ${deep_lbls} -o ${endpoints_stats} -m ${hemi} -d ${depth} \n"
                    miracl lbls stats -i ${endpoints} -l ${deep_lbls} -o ${endpoints_stats} -m ${hemi} -d ${depth}

                    printf "\n Generating figure of tract endpoint statistics with the following command: \n"

                    printf "\n miracl stats plot_subj -i ${endpoints_stats} \n"
                    miracl stats plot_subj -i ${endpoints_stats}
                else
                    printf "\n Tract endpoints statistics already computed at this depth. Otherwise, you may not have tckmap. \n"
                fi

                # # gen force graph for tract density
                # tract_graph=${sta_dir}/sta_streamlines_density_connectivity_graph_depth_${depth}_angle_${angle_val}.html

                # if [[ ! -f ${tract_graph} ]]; then
                #     printf " \n Generating virus signal connectivity graph with the following command: \n "

                #     printf "\n miracl sta conn_graph -l ${dens_stats} -s ${hemi} -r ${lbl} -o ${tract_graph} \n "
                #     miracl sta conn_graph -l ${dens_stats} -s ${hemi} -r ${lbl} -o ${tract_graph}
                # else
                #     printf "\n Tract density connectivity graph already computed at this depth \n"
                # fi

            done

        done
    done
done

# get script timing
END=$(date +%s)
DIFF=$((END-START))
DIFF=$((DIFF/60))

miracl utils end_state -f "STA and signal analysis " -t "$DIFF minutes"

# TODOs
# streamline after reg
# add assert if nii and lbls are same size
# check registered labels space and res
