#!/bin/bash

function usage() {
  echo "Creates AWS users, adds them to a group and downloads credentials"
  echo ""
  echo " Command line:"
  echo "    ./create_users.sh <Users file> <Output dir> <Group name> <AWS profile>"
  echo ""
  echo " Parameters:"
  echo "    Users file:    text file containing a user id per line, no empty lines"
  echo "    Output dir:    directory to write credentials to"
  echo "    Group name:    name of the AWS group to add users to"
  echo "    AWS profile:   name of the AWS profile to use"
  echo ""
}

function info() {
  echo "[INFO] $@" 1>&2
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

jq=./jq-win64.exe

userIds="$1"
outputDir="$2"
groupName="$3"
profile="$4"

if [ -z "$userIds" ]
  then
    usage
    fail "No users ids file provided"
fi

if [ -z "$outputDir" ]
  then
    usage
    fail "No output directory provided"
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

if [ -d $outputDir ]
  then
    info "Output directory exists: $outputDir"
  else
    info "Creating output directory: $outputDir"
    mkdir -p $outputDir || die "Failed to create output directory"
fi

rm -rf ./temp || die "Failed to clean local temp dir"

mkdir -p temp || die "Failed to craete temp dir"

info "Checking for group existence"

# See if the group exists
aws iam get-group \
--group-name $groupName \
--profile $profile &> /dev/null

groupExists=$?

if [[ $groupExists == 0 ]]
  then
    info "Group exists: $groupName"
  else
    info "Creating group: $groupName"
    aws iam create-group \
     --group-name $groupName \
     --profile $profile || die "Failed to create group"
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
          info "User exists: $userId"
        else
          info "Creating user: $userId"
          aws iam create-user \
            --user-name $userId \
            --profile $profile || die "Failed to create user: $userId"
      fi

      info "Adding user: $userId to group: $groupName"
      aws iam add-user-to-group \
        --user-name $userId \
        --group-name $groupName \
        --profile $profile || die "Failed to add user: $userId to group: $groupName"

      info "Creating access key for user: $userId"
      aws iam create-access-key \
        --user-name $userId \
        --profile $profile > ./temp/tempkey.txt || die "Failed to create access key for user: $userId"

      accessKey=$(cat ./temp/tempkey.txt | $jq -r ".AccessKey.AccessKeyId")
      secretKey=$(cat ./temp/tempkey.txt | $jq -r ".AccessKey.SecretAccessKey")
      # info "Found access key: $accessKey and secret: $secretKey" 

      outputFile=$outputDir/$userId.txt

      cat << EOF > $outputFile
accessKey = $accessKey
secretKey = $secretKey
EOF

  fi
done < $userIds

rm -rf ./temp || die "Failed to remove temp dir"
