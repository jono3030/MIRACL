#!/bin/bash
# Maged Goubran @ 2016, mgoubran@stanford.edu 

# Sets up MIRACL environment 

printf "\n Setting up MIRACL PATH  \n"
printf "\n Appending MIRACL HOME to ~/.bashrc \n" 

miraclpath="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#miraclpath="$(dirname "$initdir")"

echo "#--- MIRACL HOME ----" >> ~/.bashrc

printf "\nexport MIRACL_HOME=`echo $miraclpath`\n" >> ~/.bashrc

cat <<\EOF >> ~/.bashrc


#--- MIRACL path ----
export PATH=${MIRACL_HOME}:$PATH
for i in ${MIRACL_HOME}/* ; do export PATH=${i}:$PATH ; done

#--------------------

#--- MIRACL dependencies ----

#---ANTS---
export ANTSPATH="${MIRACL_HOME}/depends/ants"
export PATH=${MIRACL_HOME}/depends/ants:$PATH

#---C3D---
export PATH=${MIRACL_HOME}/depends/c3d/bin:$PATH
source ${MIRACL_HOME}/depends/c3d/share/bashcomp.sh

#--------------------

#--- Allen atlas alias ----
export aradir="${MIRACL_HOME}/atlases/ara"

# Templates (atlas images)
export allen10="${MIRACL_HOME}/atlases/ara/template/average_template_10um.nii.gz"
export allen25="${MIRACL_HOME}/atlases/ara/template/average_template_25um.nii.gz"
export allen50="${MIRACL_HOME}/atlases/ara/template/average_template_50um.nii.gz"

# Annotations (labels)
export lbls10="${MIRACL_HOME}/atlases/ara/annotation/annotation_hemi_combined_10um.nii.gz"
export lbls25="${MIRACL_HOME}/atlases/ara/annotation/annotation_hemi_combined_25um.nii.gz"
export lbls50="${MIRACL_HOME}/atlases/ara/annotation/annotation_hemi_combined_50um.nii.gz"

# Grand-parents labels
export gplbls25="${MIRACL_HOME}/atlases/ara/annotation/annotation_hemi_combined_25um_parent-level_3.nii.gz"
export gplbls50="${MIRACL_HOME}/atlases/ara/annotation/annotation_hemi_combined_50um_parent-level_3.nii.gz"

# ITK-snap LUT
export snaplut="${MIRACL_HOME}/atlases/ara/ara_snaplabels_lut.txt"
# Freeview LUT
export freelut="${MIRACL_HOME}/atlases/ara/ara_freeviewlabels_lut.txt"

#--------------------

EOF

printf "\n MIRACL HOME: `echo $miraclpath` \n"

printf "\n Exporting variables \n"

exec bash
