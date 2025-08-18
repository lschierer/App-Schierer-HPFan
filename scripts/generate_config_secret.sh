#!/bin/bash

ALL_NON_RANDOM_WORDS=/usr/share/dict/words

non_random_words=`cat $ALL_NON_RANDOM_WORDS | wc -l`

COUNT=10

TEMP=$(mktemp)

for (( i=1; i<=$COUNT; i++ ));do
  random_number1=$(od -N3 -An -i /dev/urandom | tr -d '[:space:]')
  random_number2=$(( ${random_number1} % ${non_random_words} ))
  #echo "${random_number2}"
  sed -n "${random_number2}p" $ALL_NON_RANDOM_WORDS >> "${TEMP}"
done

SECRET=$( sha256 -q "${TEMP}" )

rm TEMP;

GIT_COMMIT=$( git rev-parse HEAD )
TIME=$( date -u +"%Y-%m-%dT%H:%M:%SZ" )

yq -n ".secrets = [ \"${SECRET}\" ] | .version.git-commit = \"${GIT_COMMIT}\" | .version.build_time = \"${TIME}\" " > app-schierer-h_p_fan.yml
