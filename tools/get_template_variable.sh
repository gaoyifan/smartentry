#!/bin/bash

find $1 -type f -exec grep -P -o '(?<={{).+?(?=}})' {} \; | 
xargs -n 1 echo | 
sort | 
uniq
