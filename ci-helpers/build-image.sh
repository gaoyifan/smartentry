#!/bin/bash

image=$1
tag=$2
platform=$3
source_image=${4:-$image}
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

workdir=$(mktemp -d)
cp -r . $workdir
cat << EOF > $workdir/Dockerfile
FROM $source_image:$tag
LABEL maintainer "Yifan Gao <docker@yfgao.com>"
ENV ASSETS_DIR="/opt/smartentry/HEAD"
$EXTRA_CMD
COPY smartentry.sh /sbin/smartentry.sh
ENTRYPOINT ["/sbin/smartentry.sh"]
CMD ["run"]
EOF
cd $workdir
docker buildx build \
    -t smartentry/$image:$tag \
    --platform $platform \
    $DOCKER_PUSH .

[[ -n $version ]] && docker buildx build \
    -t smartentry/$image:$tag$version \
    --platform $platform \
    $DOCKER_PUSH .

[[ $SKIP_REMOVE == true ]] || docker buildx prune -a -f
