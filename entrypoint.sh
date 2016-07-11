#!/bin/bash

[[ $DEBUG == true ]] && set -x

PWD_ORGI=$PWD

ASSETS_DIR=${ASSETS_DIR:-"/etc/docker-assets"}
ROOTFS_DIR=${ROOTFS_DIR:-"$ASSETS_DIR/rootfs"}
CHECKLIST_FILE=${CHECKLIST_FILE:-"$ASSETS_DIR/checklist.md5"}
DEFAULT_ENV_FILE=${DEFAULT_ENV_FILE:-"$ASSETS_DIR/default_env.sh"}
CHMOD_FILE=${CHMOD_FILE:-"$ASSETS_DIR/chmod.list"}
BUILD_SCRIPT=${BUILD_SCRIPT:-"$ASSETS_DIR/build.sh"}
PRE_RUN_SCRIPT=${PRERUN_SCRIPT:="$ASSETS_DIR/pre_run.sh"}
VOLUMES_LIST=${VOLUMES_LIST:="$ASSETS_DIR/volumes.list"}
VOLUMES_ARCHIVE=${VOLUMES_ARCHIVE:="$ASSETS_DIR/volumes.tar"}
INITIALIZED_FLAG=${INITIALIZED_FLAG:="$ASSERS_DIR/initialized.flag"}

ENTRY_PROMPT=${ENTRY_PROMPT:="entrypoint> "}

case ${1} in
    build)
        # run user defined script
        if [[ -f $BUILD_SCRIPT ]]; then
        echo "$ENTRY_PROMPT running build.sh"
            source $BUILD_SCRIPT
        fi

        set +e

        # generate MD5 list for target files of rootfs, to keep user's modification when docker restart 
        if [[ -d $ROOTFS_DIR ]] && [[ $KEEP_USER_MODIFICATION_ENABLE != false ]] ; then
        echo "$ENTRY_PROMPT generate MD5 list"
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
            echo "$ENTRY_PROMPT chmod for rootfs"
            cd $ROOTFS_DIR 
            find . -type f -o -type d |
            while read file; do
                file_dst=${file#*.} ;
                [[ -e $file_dst ]] && stat -c "%a	%U	%G	$(realpath $file_dst)" $file_dst >> ${CHMOD_FILE}.add
            done
            [[ -f ${CHMOD_FILE} ]] && cat ${CHMOD_FILE} >> ${CHMOD_FILE}.add
            mv ${CHMOD_FILE}.add ${CHMOD_FILE}
        fi

        # init volume data
        if [[ -f $VOLUMES_LIST ]]; then
            echo "$ENTRY_PROMPT save volume data"
            cat $VOLUMES_LIST | xargs tar -rf $VOLUMES_ARCHIVE
        fi

        ;;

    *)
        # set default environment variable
        if [[ -f $DEFAULT_ENV_FILE ]] ; then
            echo "$ENTRY_PROMPT apply default environment variable"
            source $DEFAULT_ENV_FILE
        fi

        # set env: HAVE_INITIALIZED
        if [[ -f $INITIALIZED_FLAG ]]; then
            export HAVE_INITIALIZED=true
        else
            export HAVE_INITIALIZED=false
            touch $INITIALIZED_FLAG
        fi

        # init volume data
        if [[ -f $VOLUMES_ARCHIVE ]] && [[ $INIT_VOLUMES_DATA_ENABLE == true ]] && [[ $HAVE_INITIALIZED == false ]]; then
            echo "$ENTRY_PROMPT init volume data"
            tar -C / -xf $VOLUMES_ARCHIVE
        fi

        # patch file; apply template
        if [[ -d $ROOTFS_DIR ]] && [[ $ROOTFS_ENABLE != false ]]; then
            echo "$ENTRY_PROMPT patch template files"
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
            echo "$ENTRY_PROMPT fix file mode"
            cat $CHMOD_FILE | awk '{ printf("chmod %s %s\n",$1,$4); }' | sh
            cat $CHMOD_FILE | awk '{ printf("chown %s:%s %s\n",$2,$3,$4); }' | sh
        fi

        # pre-running script
        if [[ -f $PRE_RUN_SCRIPT ]]; then
            echo "$ENTRY_PROMPT pre-running script"
            source $PRE_RUN_SCRIPT
        fi

        # main program
        echo "$ENTRY_PROMPT running main program"
        cd $PWD_ORGI
        exec "$@"
        ;;
esac
