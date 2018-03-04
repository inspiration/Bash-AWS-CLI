#!/bin/bash

function usage() {
  echo "Deletes AWS users"
  echo ""
  echo " Command line:"
  echo "    ./delete_users.sh <Users file> <Group name> <AWS profile>"
  echo ""
  echo " Parameters:"
  echo "    Users file:    text file containing a user id per line, no empty lines"
  echo "    Group name:    name of the AWS group to remove users from"
  echo "    AWS profile:   name of the AWS profile to use"
  echo ""
}

function info() {
  echo "[INFO] $@" 1>&2
}

function error() {
  echo "[ERROR] $@" 1>&2
}

function fail() {
    echo "[ERROR] $@" 1>&2
    exit 1
}

function die() {
    local retCode=$?
    echo "[ERROR] $@" 1>&2
    if [[ $retCode == 0 ]] ; then
        retCode=1
    fi
    exit $retCode
}

userIds="$1"
groupName="$2"
profile="$3"

jq=./jq-win64.exe

rm -rf ./temp || die "Failed to clean local temp dir"

mkdir -p temp || die "Failed to craete temp dir"

if [ -z "$userIds" ]
  then
    usage
    fail "No users ids file provided"
fi

if [ -z "$groupName" ]
  then
    usage
    fail "No group name provided"
fi

if [ -z "$profile" ]
  then
    usage
    fail "No AWS profile provided"
fi

if [ -f $userIds ]
  then
    info "Loading user ids from: $userIds"     
  else
    fail "User ids file does not exist: $userIds"
fi

info "Processing users"

while read userId
do
  if [ -z $userId ] 
    then
      info "Skipping blank user id"
    else
      info "Processing user: $userId"

      # See if the user exists
      aws iam get-user \
        --user-name $userId \
        --profile $profile &> /dev/null

      userExists=$?

      if [[ $userExists == 0 ]]
        then
          info "User exists: $userId removing from group: $groupName"

          aws iam remove-user-from-group \
            --user-name $userId \
            --group-name $groupName \
            --profile $profile \
              || error "Failed to remove user: $userId from group: $groupName, continuing"

          info "Listing access keys for user: $userId"

          aws iam list-access-keys \
            --user-name $userId \
            --profile $profile > ./temp/keys.json \
               || error "Failed to list access keys for user: $userId"

          cat ./temp/keys.json | $jq -r .AccessKeyMetadata[].AccessKeyId > ./temp/keys.txt

          dos2unix ./temp/keys.txt || die "Converting to unix format failed"

          while read key
          do
            info "Deleting access key: $key"
            aws iam delete-access-key \
              --user-name "$userId" \
              --access-key-id "$key" \
              --profile $profile \
                || die "Failed to delete access key: $key for user: $userId"
          done < ./temp/keys.txt

          aws iam delete-user \
            --user-name "$userId" \
            --profile $profile \
              || die "Failed to delete user: $userId"

        else
          info "Skipping user did not exist: $userId"
      fi
  fi
done < $userIds

rm -rf ./temp || die "Failed to remove temp dir"
