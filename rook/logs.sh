#!/bin/bash

# use the bash_colors.sh file
found_colors="./tools/bash_colors.sh"
up_found_colors="../tools/bash_colors.sh"
if [[ "${DISABLE_COLORS}" == "" ]] && [[ "${found_colors}" != "" ]] && [[ -e ${found_colors} ]]; then
    . ${found_colors}
elif [[ "${DISABLE_COLORS}" == "" ]] && [[ "${up_found_colors}" != "" ]] && [[ -e ${up_found_colors} ]]; then
    . ${up_found_colors}
else
    inf() {
        echo "$@"
    }
    anmt() {
        echo "$@"
    }
    good() {
        echo "$@"
    }
    err() {
        echo "$@"
    }
    critical() {
        echo "$@"
    }
    warn() {
        echo "$@"
    }
fi

use_namespace="rook-ceph"
app_name=$(kubectl -n rook-ceph get pod --ignore-not-found | grep rook-ceph-rgw-s3-storage | awk '{print $1}')

anmt "--------------------------------"
anmt "Tailing Rook Ceph RGW ${app_name} logs with:"
inf ""
good "kubectl logs -n ${use_namespace} ${app_name} -f"
inf ""
kubectl logs -f -n ${use_namespace} ${app_name}
