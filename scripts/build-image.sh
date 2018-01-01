#!/bin/bash

image=$1
tag=$2
source_image=${3:-$image}
version=$(git tag --contains | tr 'v' '-')

if [[ $image == ubuntu ]]; then
    echo $tag | grep -q '-' && exit
elif [[ $image == archlinux ]]; then
    echo $tag | grep -q '-' && exit
elif [[ $image == debian ]]; then
    echo $tag | grep -qP -- '-\d{8}' && exit
elif [[ $image == fedora ]]; then
    EXTRA_CMD="RUN yum install -y tar && yum clean all"
elif [[ $image == alpine ]]; then
    EXTRA_CMD="RUN apk --update add bash tar && rm -rf /var/cache/apk/*"
fi

rocker build -f <(cat << EOF
FROM $source_image:$tag
LABEL maintainer "Yifan Gao <docker@yfgao.com>"
ENV ASSETS_DIR="/opt/smartentry/HEAD"
$EXTRA_CMD
COPY smartentry.sh /sbin/smartentry.sh
ENTRYPOINT ["/sbin/smartentry.sh"]
CMD ["run"]
PUSH smartentry/$image:$tag
EOF
) .
docker tag smartentry/$image:$tag smartentry/$image:$tag$version
[[ $SKIP_PUSH == true ]] || docker push smartentry/$image:$tag
[[ $SKIP_PUSH == true ]] || docker push smartentry/$image:$tag$version
[[ $SKIP_REMOVE == true ]] || docker rmi \
    $source_image:$tag \
    smartentry/$image:$tag \
    smartentry/$image:$tag$version
