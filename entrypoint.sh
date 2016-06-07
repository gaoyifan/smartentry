#!/bin/bash

[[ $DEBUG == true ]] && set -x

PWD_ORGI=$PWD

case ${1} in
    build)
        if [[ -f $BUILD_SCRIPT ]]; then
            source $BUILD_SCRIPT
        fi
	set +e
        if [[ -n $MD5_CHECKLIST ]] ; then
            cd $TEMPLATES_DIR
            TEMPLATE_VARIABLES=$(find . -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | xargs -n 1 echo | sort | uniq ) 
            find . -type f | 
            while read file; do
                file_dst=${file#*.} ;
                [[ -f $file_dst ]] && md5sum $file_dst >> $MD5_CHECKLIST
            done
        fi
        if [[ -n $ATTRIBUTE_FIX_LIST ]] && [[ $ATTRIBUTE_AUTO_FIX_ENABLE != false ]]; then
            cd $TEMPLATES_DIR 
            find . -type f -o -type d |
            while read file; do
                file_dst=${file#*.} ;
                [[ -e $file_dst ]] && stat -c "%a	%U	%G	$(realpath $file_dst)" $file_dst >> ${ATTRIBUTE_FIX_LIST}.add
            done
            [[ -f ${ATTRIBUTE_FIX_LIST} ]] && cat ${ATTRIBUTE_FIX_LIST} >> ${ATTRIBUTE_FIX_LIST}.add
            mv ${ATTRIBUTE_FIX_LIST}.add ${ATTRIBUTE_FIX_LIST}
        fi
        ;;
    *)
        [[ -f $DEFAULT_ENV ]] && source $DEFAULT_ENV

        if [[ -d $TEMPLATES_DIR ]] && [[ $APPLY_TEMPLATES_ENABLE != false ]]; then
            cd $TEMPLATES_DIR
            find . -mindepth 1 -type d | while read dir; do mkdir -p ${dir#*.} ; done
            TEMPLATE_VARIABLES=$(find . -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | xargs -n 1 echo | sort | uniq)
            find . -type f | 
            while read file; do
                file_dst=${file#*.}
                if [[ -f $MD5_CHECKLIST ]]; then
                    cat $MD5_CHECKLIST | grep $file_dst | md5sum -c --quiet > /dev/null 2>&1 && cp $file $file_dst ;
                    [[ ! -f $file_dst ]] && cp $file $file_dst ;
                else
                    cp $file $file_dst ;
                fi
                [[ -n $TEMPLATE_VARIABLES ]] && echo $TEMPLATE_VARIABLES | xargs -n 1 echo | 
                while read variable; do
                    eval sed -i "s/{{$variable}}/\${$variable}/g" $file_dst ;
                done
            done

            find . -type l |
            while read link; do
                link_dst=${link#*.}
                cp -d $link $link_dst
            done
        fi

        if [[ -f $ATTRIBUTE_FIX_LIST ]] && [[ $APPLY_ATTRIBUTE_FIX_ENABLE != false ]]; then
            cat $ATTRIBUTE_FIX_LIST | awk '{ printf("chmod %s %s\n",$1,$4); }' | sh
            cat $ATTRIBUTE_FIX_LIST | awk '{ printf("chown %s:%s %s\n",$2,$3,$4); }' | sh
        fi

        cd $PWD_ORGI
        exec "$@"
        ;;
esac
