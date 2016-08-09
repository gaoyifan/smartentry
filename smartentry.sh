#!/bin/bash

[[ $DEBUG == true ]] && set -x

pwd_orig=$PWD

export ASSETS_DIR=${ASSETS_DIR:-"/opt/proj/docker"}
export ROOTFS_DIR=${ROOTFS_DIR:-"$ASSETS_DIR/rootfs"}
export CHECKLIST_FILE=${CHECKLIST_FILE:-"$ASSETS_DIR/checklist.md5"}
export DEFAULT_ENV_FILE=${DEFAULT_ENV_FILE:-"$ASSETS_DIR/default-env.sh"}
export CHMOD_FILE=${CHMOD_FILE:-"$ASSETS_DIR/chmod.list"}
export BUILD_SCRIPT=${BUILD_SCRIPT:-"$ASSETS_DIR/build"}
export PRE_RUN_SCRIPT=${PRERUN_SCRIPT:="$ASSETS_DIR/pre-run"}
export VOLUMES_LIST=${VOLUMES_LIST:="$ASSETS_DIR/volumes.list"}
export VOLUMES_ARCHIVE=${VOLUMES_ARCHIVE:="$ASSETS_DIR/volumes.tar"}
export INITIALIZED_FLAG=${INITIALIZED_FLAG:="/initialized.flag"}

export ENABLE_KEEP_USER_MODIFICATION=${ENABLE_KEEP_USER_MODIFICATION:="true"}
export ENABLE_CHMOD_AUTO_FIX=${ENABLE_CHMOD_AUTO_FIX:="true"}
export ENABLE_INIT_VOLUMES_DATA=${ENABLE_INIT_VOLUMES_DATA:="true"}
export ENABLE_ROOTFS=${ENABLE_ROOTFS:="true"}
export ENABLE_CHMOD_FIX=${ENABLE_CHMOD_FIX:="true"}
export ENABLE_UNSET_ENV_VARIBLES=${ENABLE_UNSET_ENV_VARIBLES:="true"}
export ENABLE_PRE_RUN_SCRIPT=${ENABLE_PRE_RUN_SCRIPT:="true"}
export ENABLE_FORCE_INIT_VOLUMES_DATA=${ENABLE_FORCE_INIT_VOLUMES_DATA:="false"}

entry_prompt=${entry_prompt:="smartentry> "}

case ${1} in
    build)
        # run user defined script
        if [[ -f $BUILD_SCRIPT ]]; then
            echo "$entry_prompt running build script"
            $BUILD_SCRIPT
        fi

        set +e

        # generate MD5 list for target files of rootfs, to keep user's modification when docker restart 
        if [[ -d $ROOTFS_DIR ]] && [[ $ENABLE_KEEP_USER_MODIFICATION == true ]] ; then
            echo "$entry_prompt generate MD5 list"
            cd $ROOTFS_DIR
            TEMPLATE_VARIABLES=$(find . -type f -exec awk -vRS='}}' '/\{\{/{gsub(/.*\{\{/,"");print}' {} \; | xargs -n 1 echo | sort | uniq ) 
            find . -type f | 
            while read file; do
                file_dst=${file#*.} ;
                [[ -f $file_dst ]] && md5sum $file_dst >> $CHECKLIST_FILE
            done
        fi

        # chmod for rootfs
        if [[ -d $ROOTFS_DIR ]] && [[ $ENABLE_CHMOD_AUTO_FIX == true ]]; then
            echo "$entry_prompt chmod for rootfs"
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
            echo "$entry_prompt save volume data"
            cat $VOLUMES_LIST | xargs tar -rPf $VOLUMES_ARCHIVE
        fi

        ;;

    *)
        # set default environment variable
        if [[ -f $DEFAULT_ENV_FILE ]] ; then
            echo "$entry_prompt apply default environment variable"
            source $DEFAULT_ENV_FILE
        fi

        # set env: DOCKER_UID, DOCKER_GID, DOCKER_USER
        if [[ $DOCKER_UID ]]; then
            # UID exist in passwd
            if [[ `getent passwd $DOCKER_UID` ]] ; then 
                export DOCKER_USER=`getent passwd $DOCKER_UID | cut -d: -f1`
                export DOCKER_GID=`getent passwd $DOCKER_UID | cut -d: -f4`
                export DOCKER_HOME=`getent passwd $DOCKER_UID | cut -d: -f6`
            else
                export DOCKER_USER=${DOCKER_USER:-"docker-inner-user"}
                export DOCKER_GID=${DOCKER_GID:-"$DOCKER_UID"}
                export DOCKER_HOME=${DOCKER_HOME:-"/var/empty"}
                echo "$DOCKER_USER:x:$DOCKER_UID:$DOCKER_GID::$DOCKER_HOME:/bin/sh" >> /etc/passwd
            fi
        elif [[ $DOCKER_USER ]]; then
            # assert: user exist in passwd
            if [[ ! `getent passwd $DOCKER_USER` ]]; then
                >&2 echo "$entry_prompt ERROR: user=$DOCKER_USER not found in passwd. exit." ; 
                exit
            fi
            export DOCKER_UID=`id -u $DOCKER_USER`
            export DOCKER_GID=`id -g $DOCKER_USER`
            passwd_home=`getent passwd $DOCKER_UID | cut -d: -f6`
            [[ $passwd_home ]] && export DOCKER_HOME=$passwd_home
        else
            export DOCKER_USER=root
            export DOCKER_UID=0
            export DOCKER_GID=0
            export DOCKER_HOME=${DOCKER_HOME:-"/var/empty"}
        fi

        # set env: HAVE_INITIALIZED
        if [[ -f $INITIALIZED_FLAG ]]; then
            export HAVE_INITIALIZED=true
        else
            export HAVE_INITIALIZED=false
            touch $INITIALIZED_FLAG
        fi

        # init volume data
        if [[ -f $VOLUMES_ARCHIVE ]] && [[ $ENABLE_INIT_VOLUMES_DATA == true ]] && [[ $HAVE_INITIALIZED == false ]]; then
            echo "$entry_prompt init volume data"
            cat $VOLUMES_LIST |
            while read volume; do
                # empty directory or directory not exist
                if [ ! "`ls -A $volume 2> /dev/null`" ] && [ ! -f $volume ] || [ $ENABLE_FORCE_INIT_VOLUMES_DATA == true ]; then
                    tar -C / -xPf $VOLUMES_ARCHIVE $volume
                fi
            done
        fi

        # patch file; apply template
        if [[ -d $ROOTFS_DIR ]] && [[ $ENABLE_ROOTFS == true ]]; then
            echo "$entry_prompt patch template files"
            cd $ROOTFS_DIR

            find . -mindepth 1 -type d | 
            while read dir; do 
                mkdir -p ${dir#*.} ; 
            done

            TEMPLATE_VARIABLES=$(find . -type f -exec awk -vRS='}}' '/\{\{/{gsub(/.*\{\{/,"");print}' {} \; | xargs -n 1 echo | sort | uniq)
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
        if [[ -f $CHMOD_FILE ]] && [[ $ENABLE_CHMOD_FIX == true ]]; then
            echo "$entry_prompt fix file mode"
            cat $CHMOD_FILE | awk '{ printf("chmod %s %s\n",$1,$4); }' | sh
            cat $CHMOD_FILE | awk '{ printf("chown %s:%s %s\n",$2,$3,$4); }' | sh
        fi

        # pre-running script
        if [[ -f $PRE_RUN_SCRIPT ]] && [[ $ENABLE_PRE_RUN_SCRIPT == true ]]; then
            echo "$entry_prompt pre_running script"
            $PRE_RUN_SCRIPT
        fi

        docker_uid=$DOCKER_UID
        docker_gid=$DOCKER_GID
        docker_user=$DOCKER_USER

        # unset all environment varibles
        if [[ $ENABLE_UNSET_ENV_VARIBLES == true ]]; then
            term_orig=$TERM
            path_orig=$PATH
            home_orig=$HOME
            shlvl_orig=$SHLVL

            for i in $(env | awk -F"=" '{print $1}') ; do
                unset $i; 
            done

            export TERM=$term_orig
            export PATH=$path_orig
            export HOME=$home_orig
            export SHLVL=$shlvl_orig
        fi

        # run main program
        echo "$entry_prompt running main program"
        cd $pwd_orig

        if [[ $docker_uid != 0 ]]; then
            echo "$entry_prompt running with UID=$docker_uid GID=$docker_gid USER=$docker_user"
            su -m -c "$@" $docker_user
            exit
        fi

        exec "$@"

        ;;
esac