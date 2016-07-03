#!/bin/bash

[[ $DEBUG == true ]] && set -x

PWD_ORGI=$PWD

ASSETS_DIR=${ASSETS_DIR:-"/etc/docker-assets"}
ROOTFS_DIR=${ROOTFS_DIR:-"$ASSETS_DIR/rootfs"}
CHECKLIST_FILE=${CHECKLIST_FILE:-"$ASSETS_DIR/checklist.md5"}
DEFAULT_ENV_FILE=${DEFAULT_ENV_FILE:-"$ASSETS_DIR/default_env.sh"}
CHMOD_FILE=${CHMOD_FILE:-"$ASSETS_DIR/chmod.list"}
BUILD_SCRIPT=${BUILD_SCRIPT:-"$ASSETS_DIR/build.sh"}
VOLUME_INIT_LIST=${VOLUME_INIT_LIST:-"$ASSETS_DIR/volume_init.list"}
PRE_RUN_SCRIPT=${PRERUN_SCRIPT:="$ASSETS_DIR/pre_run.sh"}

case ${1} in
    build)
        # run user defined script
        if [[ -f $BUILD_SCRIPT ]]; then
            source $BUILD_SCRIPT
        fi

        set +e

        # generate MD5 list for target files of rootfs, to keep user's modification when docker restart 
        if [[ -d $ROOTFS_DIR ]] && [[ $KEEP_USER_MODIFICATION_ENABLE != false ]] ; then
            cd $ROOTFS_DIR
            TEMPLATE_VARIABLES=$(find . -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | xargs -n 1 echo | sort | uniq ) 
            find . -type f | 
            while read file; do
                file_dst=${file#*.} ;
                [[ -f $file_dst ]] && md5sum $file_dst >> $CHECKLIST_FILE
            done
        fi

        # chmod for rootfs
        if [[ -d $ROOTFS_DIR ]] && [[ $CHMOD_AUTO_FIX_ENABLE != false ]]; then
            cd $ROOTFS_DIR 
            find . -type f -o -type d |
            while read file; do
                file_dst=${file#*.} ;
                [[ -e $file_dst ]] && stat -c "%a	%U	%G	$(realpath $file_dst)" $file_dst >> ${CHMOD_FILE}.add
            done
            [[ -f ${CHMOD_FILE} ]] && cat ${CHMOD_FILE} >> ${CHMOD_FILE}.add
            mv ${CHMOD_FILE}.add ${CHMOD_FILE}
        fi
        ;;
    *)
        # set default environment variable
        [[ -f $DEFAULT_ENV_FILE ]] && source $DEFAULT_ENV_FILE

        # patch file; apply template
        if [[ -d $ROOTFS_DIR ]] && [[ $ROOTFS_ENABLE != false ]]; then
            cd $ROOTFS_DIR
            find . -mindepth 1 -type d | while read dir; do mkdir -p ${dir#*.} ; done
            TEMPLATE_VARIABLES=$(find . -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | xargs -n 1 echo | sort | uniq)
            find . -type f | 
            while read file; do
                file_dst=${file#*.}
                if [[ -f $CHECKLIST_FILE ]]; then
                    cat $CHECKLIST_FILE | grep $file_dst | md5sum -c --quiet > /dev/null 2>&1 && cp $file $file_dst ;
                    [[ ! -f $file_dst ]] && cp $file $file_dst ;
                else
                    cp $file $file_dst ;
                fi
                [[ -n $TEMPLATE_VARIABLES ]] && echo $TEMPLATE_VARIABLES | xargs -n 1 echo | 
                while read variable; do
                    variable_literal=$(eval echo \${$variable} | sed 's:/:\\/:g')
                    sed -i "s/{{$variable}}/$variable_literal/g" $file_dst ;
                done
            done

            find . -type l |
            while read link; do
                link_dst=${link#*.}
                cp -d $link $link_dst
            done
        fi

        # fix file mode
        if [[ -f $CHMOD_FILE ]] && [[ $CHMOD_FIX_ENABLE != false ]]; then
            cat $CHMOD_FILE | awk '{ printf("chmod %s %s\n",$1,$4); }' | sh
            cat $CHMOD_FILE | awk '{ printf("chown %s:%s %s\n",$2,$3,$4); }' | sh
        fi

        # pre-running script
        if [[ -f $PRE_RUN_SCRIPT ]]; then
            source $PRE_RUN_SCRIPT
        fi

        # main program
        cd $PWD_ORGI
        exec "$@"
        ;;
esac
