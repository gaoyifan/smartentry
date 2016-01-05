#!/bin/bash

set -e

[[ $DEBUG == true ]] && set -x

source $DEFAULT_ENV

cd $TEMPLATES_DIR
find . -mindepth 1 -type d | while read dir; do mkdir -p ${dir#*.} ; done
TEMPLATE_VARIABLES=$(find . -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | xargs -n 1 echo | sort | uniq)
find . -type f | while read file; do
  cp $file ${file#*.} ;
  echo $TEMPLATE_VARIABLES | xargs -n 1 echo | while read variable; do
    eval sed -ri "s/\\\\{\\\\{$variable\\\\}\\\\}/\${$variable}/g" ${file#*.} ;
  done
done

[[ -f $ATTRIBUTE_FIX_LIST ]] && cat $ATTRIBUTE_FIX_LIST | awk '{ printf("chmod %s %s",$1,$4); }' | sh
[[ -f $ATTRIBUTE_FIX_LIST ]] && cat $ATTRIBUTE_FIX_LIST | awk '{ printf("chown %s:%s %s",$2,$3,$4); }' | sh

exec "$@"
