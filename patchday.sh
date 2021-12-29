#!/bin/bash
capsule='capsule.local.net'

precheck() {
  grep ' :use_sessions:' ~/.hammer/cli.modules.d/foreman.yml > /dev/null || \
  echo ':foreman:
 :use_sessions: true' >  ~/.hammer/cli.modules.d/foreman.yml
  hammer --interactive no organization list > /dev/null || hammer auth login basic -u `whoami`
}

prepare() {
  rm -f ~/.hammer/defaults.yml
  #hammer defaults delete --param-name organization
  #hammer defaults add --param-name organization --param-value "$org"
  #hammer defaults add --param-name location --param-value "$LOC"
  #hammer --csv --no-headers organization list 2>/dev/null | cut -d "," -f 3 > /tmp/org.csv 2>&1
  echo "prepare Organization list"
  hammer --csv --no-headers organization list | cut -d "," -f 3 > /tmp/org.csv 
  echo "prepare Life Cycle Enviroment list"
  hammer --csv --no-headers lifecycle-environment list > /tmp/les.csv
  echo "prepare Content View list"
  hammer --csv --no-headers content-view list  > /tmp/cvs.csv
  echo "prepare Content View versions list"
  hammer --csv --no-headers content-view version list > /tmp/cvvs.csv
  #get Content Views
  cv=$(grep false /tmp/cvs.csv | cut -d "," -f 1 | sort -n)
  #get Composite Content Views id
  ccv=$(grep true /tmp/cvs.csv | cut -d "," -f 1 | sort -n)
  #get organisation
  org=$(tail -1 /tmp/org.csv)
  hammer defaults add --param-name organization --param-value "$org"
  }

cleanup() {
  rm -f /tmp/les.csv
  rm -f /tmp/cvs.csv
  rm -f /tmp/cvvs.csv
  rm -f /tmp/org.csv
  #/bin/true
  }

listcvs () {
  echo "List Content-view versions"
  #cat /tmp/cvvs.csv | while IFS=',' read -r id name version description lce #CentOs/hammer 0.19
  cat /tmp/cvvs.csv | while IFS=',' read -r id name version comment lce #RedHat/hammer 0.17
  do
    #echo "lce is $lce"
    echo $lce | tr -d '"'| sed s/Library,//g | sed s/Library//g | while IFS=',' read -r lce1 lce2 lce3 lce4
    do
    if [ ! -z "$lce1" ]; then
      echo "ID: $id Name: $name Version: $version LCE: 1: $lce1 2: $lce2 3: $lce3 4: $lce4"
    fi
    done
  done
  }

updatecv() {
  echo "Publish new versions of Content Views"
   for i in $cv
    do
     echo "Publish new version Content View id $i $comment"
     hammer content-view publish --id "$i" --description "$comment" #--async
    done
  }

updateccv() {
  #echo "$ccv"
  echo "Publish new versions of Composite Content Views"
   for i in $ccv
    do
     echo "Publish new version Composite Content View id $i $comment"
     hammer content-view publish --id "$i" --description "$comment" #--async
    done
  }

promote() {
  #find the LiveCyleEnvironment which matches our searchstring
  matchenv=$1
  #cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$matchenv"
  cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$matchenv" | while read env2
  do
  echo ""
  echo "current LifeCycleEnvironment is $env2"
    #Skip for LifeCycleEnvironment Library, Hund
    if [[ "$env2" = @('Library'|'Hund') ]]; then
       echo "skipping LifeCycleEnvironment $env2"
       continue
    fi
    #find the contentview used by the LiveCyleEnvironment
    contentview=$(grep -i "$env2" /tmp/cvvs.csv | grep -v 'Default Organization View' | cut -d "," -f 2 | rev | cut -d ' ' -f 1 --complement | rev)
    echo "environment $env2 is using contentview $contentview"
    #Find the latest Version of this Contentview
    versid=$(grep "$contentview" /tmp/cvvs.csv| cut -d ',' -f1 | sort -nr | head -n1)
    echo "latest version of contentview $contentview is $versid"
           echo "Publish latest version/ID $versid Composite Content View $contentview to Lifecycle environments $env2"
           hammer content-view version promote --id "$versid" --content-view "$contentview" --to-lifecycle-environment "$env2" --force #--async
           #echo "hammer content-view version promote --id \"$versid\" --content-view \"$contentview\" --to-lifecycle-environment \"$env2\" --force #--async"
  done
  }

rollback() {
  #find the LiveCyleEnvironment which matches our searchstring
  matchenv=$1
  #cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$matchenv"
  cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$matchenv" | while read env2
  do
  echo ""
  echo "current LifeCycleEnvironment is $env2"
    #Skip for LifeCycleEnvironment Library, Hund
    if [[ "$env2" = @('Library'|'Hund') ]]; then
       echo "skipping LifeCycleEnvironment $env2"
       continue
    fi
    #find the contentview used by the LiveCyleEnvironment
    contentview=$(grep -i "$env2" /tmp/cvvs.csv | grep -v 'Default Organization View' | cut -d "," -f 2 | rev | cut -d ' ' -f 1 --complement | rev)
    echo "environment $env2 is using contentview $contentview"
    #Find the prelatest Version of this Contentview
    versid=$(grep "$contentview" /tmp/cvvs.csv| cut -d ',' -f1 | sort -nr | head -n2 | tail -1)
    echo "latest version of contentview $contentview is $versid"
           echo "Publish latest version/ID $versid Composite Content View $contentview to Lifecycle environments $env2"
           hammer content-view version promote --id "$versid" --content-view "$contentview" --to-lifecycle-environment "$env2" --force #--async
           #echo "hammer content-view version promote --id \"$versid\" --content-view \"$contentview\" --to-lifecycle-environment \"$env2\" --force #--async"
  done
  }

aufraeumen() {
   grep true /tmp/cvs.csv | cut -d "," -f 2 | while read i
    do
     echo "aufraeumen of Composite Content View $i"
     hammer content-view purge --name "$i" --count 6
    done
   grep false /tmp/cvs.csv | cut -d "," -f 2 | while read i
    do
     echo "aufraeumen of Content View $i"
     hammer content-view purge --name "$i" --count 6
    done
  }

synctocapsule() {
  cat /tmp/les.csv | cut -d ',' -f 1 | sort | while read lceid
    do
      hammer capsule content synchronize --lifecycle-environment-id $lceid --name "$capsule"
    done
  }

case $1 in
  -l | --list)
    precheck
    prepare
    listcvs
    cleanup
  ;;
  -c | --create)
    #set comment for new versions
    if [ -z "${2}" ]; then
      #echo "Comment is unset or set to the empty string"
      comment="Patchday $(date +%b\ %Y)"
    else 
      comment="$2 $(date +%b\ %Y)"
    fi
    #echo "comment is $comment"
    precheck
    prepare
    updatecv
    updateccv
    cleanup
  ;;
  -p | --promote)
    precheck
    prepare
    promote $2
    cleanup
  ;;
  -r | --rollback)
    precheck
    prepare
    rollback $2
    cleanup
  ;;
  -s | --synctocapsule)
    precheck
    prepare
    synctocapsule
    cleanup
  ;;
  -a | --aufraeumen)
    precheck
    prepare
    aufraeumen
    cleanup
  ;;
  * | -h | --help)
    echo -e "Usage:\n -l, --list\n    to list published CV versions\n -c, --create (description)\n    to create new CV version, decription is optional\n -p, --promote (searchstring like DEV/TEST/PROD)\n    to promote latest CV version to optional searchstring like DEV/TEST/PROD, if missing to all\n -r, --rolback (searchstring)\n    roll back CV to previous version\n -s, --synctocapsule\n    to sync content to $capsule\n -a, --aufraeumen\n    to clean up to 6 latest versions of Content Views\n -h, --help\n    to read this"
    exit 1
  ;;
esac
