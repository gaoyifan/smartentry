#!/bin/bash

[[ $DEBUG == true ]] && set -x

pwd_orig=$PWD
entry_prompt=${entry_prompt:-"smartentry> "}

export ASSETS_DIR=${ASSETS_DIR:-"/opt/smartentry/HEAD"}
export ENV_FILE=${ENV_FILE:-"$ASSETS_DIR/env"}
export ENABLE_OVERRIDE_ENV=${ENABLE_OVERRIDE_ENV:-"false"}

declare -a required_envs
if [[ -f $ENV_FILE ]]; then
    echo "$entry_prompt setting environment virables"
    while read env; do
        env_name=$(eval echo ${env%%=*})
        env_value=$(eval echo ${env#*=})
        if [[ -n $env_name ]]; then
            if ! ( echo $env | grep = > /dev/null ) ; then
                required_envs+=($env_name)
            else
                if [[ $ENABLE_OVERRIDE_ENV == true ]] || [[ -z ${!env_name} ]]; then
                    export $env_name=$env_value
                fi
            fi
        fi
    done < $ENV_FILE
fi

export ROOTFS_DIR=${ROOTFS_DIR:-"$ASSETS_DIR/rootfs"}
export CHECKLIST_FILE=${CHECKLIST_FILE:-"$ASSETS_DIR/checklist.md5"}
export PRE_ENTRY_SCRIPT=${PRE_ENTRY_SCRIPT:-"$ASSETS_DIR/pre-entry.sh"}
export CHMOD_FILE=${CHMOD_FILE:-"$ASSETS_DIR/chmod.list"}
export RUN_SCRIPT=${RUN_SCRIPT:-"$ASSETS_DIR/run"}
export BUILD_SCRIPT=${BUILD_SCRIPT:-"$ASSETS_DIR/build"}
export PRE_RUN_SCRIPT=${PRERUN_SCRIPT:-"$ASSETS_DIR/pre-run"}
export VOLUMES_LIST=${VOLUMES_LIST:-"$ASSETS_DIR/volumes.list"}
export VOLUMES_ARCHIVE=${VOLUMES_ARCHIVE:-"$ASSETS_DIR/volumes.tar"}
export INITIALIZED_FLAG=${INITIALIZED_FLAG:-"/var/run/smartentry.initialized"}
export DOCKER_SHELL=${DOCKER_SHELL:-"/bin/bash"}

export ENABLE_KEEP_USER_MODIFICATION=${ENABLE_KEEP_USER_MODIFICATION:-"true"}
export ENABLE_CHMOD_AUTO_FIX=${ENABLE_CHMOD_AUTO_FIX:-"true"}
export ENABLE_INIT_VOLUMES_DATA=${ENABLE_INIT_VOLUMES_DATA:-"true"}
export ENABLE_ROOTFS=${ENABLE_ROOTFS:-"true"}
export ENABLE_CHMOD_FIX=${ENABLE_CHMOD_FIX:-"true"}
export ENABLE_UNSET_ENV_VARIBLES=${ENABLE_UNSET_ENV_VARIBLES:-"true"}
export ENABLE_PRE_RUN_SCRIPT=${ENABLE_PRE_RUN_SCRIPT:-"true"}
export ENABLE_FORCE_INIT_VOLUMES_DATA=${ENABLE_FORCE_INIT_VOLUMES_DATA:-"false"}
export ENABLE_FIX_OWNER_OF_VOLUMES=${ENABLE_FIX_OWNER_OF_VOLUMES:-"false"}
export ENABLE_FIX_OWNER_OF_VOLUMES_DATA=${ENABLE_FIX_OWNER_OF_VOLUMES_DATA:-"false"}
export ENABLE_MANDATORY_CHECK_ENV=${ENABLE_MANDATORY_CHECK_ENV:-"true"}


case ${1} in
    build)
        # run user defined script
        if [[ -f $BUILD_SCRIPT ]]; then
            echo "$entry_prompt running build script"
            $BUILD_SCRIPT || exit 1
        fi

        set +e

        # generate MD5 list for target files of rootfs, to keep user's modification when docker restart 
        if [[ $ENABLE_ROOTFS == true ]] && [[ -d $ROOTFS_DIR ]] && [[ $ENABLE_KEEP_USER_MODIFICATION == true ]] ; then
            echo "$entry_prompt generate MD5 list"
            cd $ROOTFS_DIR
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
            [[ -f ${CHMOD_FILE}.add ]] && mv ${CHMOD_FILE}.add ${CHMOD_FILE}
        fi

        # save volume data
        if [[ -f $VOLUMES_LIST ]]; then
            echo "$entry_prompt save volume data"
            cat $VOLUMES_LIST |
            while read volume; do
                if [[ ! -e $volume ]]; then
                    >&2 echo "$entry_prompt WARNING: volume $volume doesn't exist, created an empty dir."
                    mkdir -p $volume
                fi
                tar -rPf $VOLUMES_ARCHIVE $volume
            done
        fi

        ;;

        # run a program
        *)
        # set env: HAVE_INITIALIZED
        if [[ -f $INITIALIZED_FLAG ]]; then
            export HAVE_INITIALIZED=true
        else
            export HAVE_INITIALIZED=false
            touch $INITIALIZED_FLAG
        fi

        # pre-entry script
        if [[ -f $PRE_ENTRY_SCRIPT ]] ; then
            echo "$entry_prompt running pre-entry script"
            source $PRE_ENTRY_SCRIPT
        fi

        # mandatory check required env
        if [[ $ENABLE_MANDATORY_CHECK_ENV == true ]] && [[ ${#required_envs[@]} != 0 ]]; then
            echo "$entry_prompt checking required environment variables"
            for required_env in ${required_envs[@]}; do
                if [[ -z ${!reqiured_env} ]]; then
                    >&2 echo "$entry_prompt environment value $required_env doesn't exist. program exit."
                    exit 2
                fi
            done
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
            if [[ $DOCKER_GID ]] && [[ $DOCKER_GID != 0 ]]; then
                >&2 echo "$entry_prompt ERROR: only set DOCKER_GID=$DOCKER_GID, but DOCKER_USER or DOCKER_UID not found. exit."   
            else
                export DOCKER_GID=0
            fi
            export DOCKER_HOME=${DOCKER_HOME:-"`getent passwd root | cut -d: -f6`"}
        fi
        if [[ $DOCKER_HOME ]]; then
            sed -i "s|^\([^:]*:[^:]*:$DOCKER_UID:[^:]*:[^:]*\):[^:]*:\([^:]*\)$|\1:$DOCKER_HOME:\2|g" /etc/passwd
        fi

        # init volume data
        if [[ -f $VOLUMES_ARCHIVE ]] && [[ $ENABLE_INIT_VOLUMES_DATA == true ]] && [[ $HAVE_INITIALIZED == false ]]; then
            echo "$entry_prompt init volume data"
            cat $VOLUMES_LIST |
            while read volume; do
                # empty directory or directory not exist
                if [ ! "`ls -A $volume 2> /dev/null`" ] && [ ! -f $volume ] || [ $ENABLE_FORCE_INIT_VOLUMES_DATA == true ]; then
                    tar -C / -xPf $VOLUMES_ARCHIVE $volume
                    if [[ $DOCKER_UID != 0 ]]; then
                        [[ $ENABLE_FIX_OWNER_OF_VOLUMES == true ]] && chown $DOCKER_UID:$DOCKER_GID $volume
                        [[ $ENABLE_FIX_OWNER_OF_VOLUMES_DATA == true ]] && chown -R $DOCKER_UID:$DOCKER_GID $volume
                    fi
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

            TEMPLATE_VARIABLES=$(find . -type f -exec grep -o '{{[A-Za-z0-9_]\+}}' {} \; | awk -vRS='}}' '{gsub(/.*\{\{/,"");print}' | xargs -n 1 echo | sort | uniq)
            find . -type f | 
            while read file; do
                file_dst=${file#*.}
                if [[ $ENABLE_KEEP_USER_MODIFICATION ]]; then
                    [[ -f $CHECKLIST_FILE ]] && cat $CHECKLIST_FILE | grep $file_dst | md5sum -c 2> /dev/null | grep 'OK$' > /dev/null && cp $file $file_dst ;
                    [[ ! -f $file_dst ]] && cp $file $file_dst ;
                else
                    cp $file $file_dst ;
                fi
                [[ -n $TEMPLATE_VARIABLES ]] && echo $TEMPLATE_VARIABLES | xargs -n 1 echo | 
                while read variable; do
                    variable_literal=$(echo ${!variable} | sed 's:/:\\/:g')
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
            echo "$entry_prompt pre-run script"
            $PRE_RUN_SCRIPT
        fi

        docker_uid=$DOCKER_UID
        docker_gid=$DOCKER_GID
        docker_user=$DOCKER_USER
        docker_shell=$DOCKER_SHELL
        run_script=$RUN_SCRIPT

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
        echo "$entry_prompt running main program(UID=$docker_uid GID=$docker_gid USER=$docker_user)"
        cd $pwd_orig
        if [[ $1 == run ]]; then
            shift
            if [[ -f $run_script ]]; then
                cmd="exec $run_script $@"
            else
                >&2 echo "$entry_prompt ERROR: run script not exist. exit."
            fi
        else
            cmd=`echo $@`
        fi

        if [[ $docker_user == root ]]; then
            $cmd
        else
            exec su -m -s $docker_shell -c "$cmd" $docker_user
        fi

        ;;
esac
