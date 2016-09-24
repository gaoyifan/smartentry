#!/bin/bash

find $1 -type f -exec grep -Z -P -o '(?<={{).+?(?=}})' {} \; | 
xargs -0 -n 1 echo | 
sort | 
uniq
