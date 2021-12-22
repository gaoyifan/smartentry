#!/bin/bash

BASEDIR=$(dirname $0)

docker_tags () {
    echo $1 | grep -q '/' && image=$1 || image=library/$1
    tags_js=$(curl -sSL "https://registry.hub.docker.com/v2/repositories/${image}/tags/")
    jq -r '.results[].name' <(echo $tags_js)
    next_page=$(jq -r '.next' <(echo $tags_js) )
    while [[ $next_page ]] && [[ $next_page != null ]]
    do
        tags_js=$(curl -sSL $next_page)
        jq -r '.results[].name' <(echo $tags_js)
        next_page=$(jq -r '.next' <(echo $tags_js) )
    done
}

[[ -z $SKIP_LOGIN ]] && docker login -u "$DOCKER_USER" -p "$DOCKER_PASS"
docker_tags ${SOURCE_IMAGE:-$IMAGE} | parallel --retries 3 -j 8 $BASEDIR/build-image.sh $IMAGE {} $PLATFORM $SOURCE_IMAGE

