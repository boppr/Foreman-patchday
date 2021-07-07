#!/bin/bash



precheck() {
  echo "Checking authentication"
  rm -f /tmp/org.csv
  #for centos/hammer 0.19:
  #hammer --csv --no-headers organization list --organization-id 1 2>/dev/null | cut -d "," -f 3 > /tmp/org.csv 2>&1
  #for redhat/hammer 0.17:
  hammer --csv --no-headers organization list 2>/dev/null | cut -d "," -f 3 > /tmp/org.csv 2>&1
  if [ -s /tmp/org.csv ]
  then
    echo "successfull authenticated"
  else
    echo -e "\ncould not login to Foreman\nplease insert your credentials into the config file:\nvim ~/.hammer/cli.modules.d/foreman.yml"
    exit 1
  fi
  }

prepare () {
  org=$(tail -1 /tmp/org.csv)
  hammer defaults add --param-name organization --param-value "$org"
  #hammer defaults add --param-name location --param-value "$LOC"
  echo "prepare Life Cycle Enviroment list"
  hammer --csv --no-headers lifecycle-environment list > /tmp/les.csv
  echo "prepare Content View list"
  hammer --csv --no-headers content-view list  > /tmp/cvs.csv
  echo "prepare Content View versions list"
  hammer --csv --no-headers content-view version list > /tmp/cvvs.csv
  #set comment for new versions
  comment="Patchday $(date +%b\ %Y)"
  #get Content Views
  cv=$(grep false /tmp/cvs.csv | cut -d "," -f 1 | sort -n)
  #get Composite Content Views id
  ccv=$(grep true /tmp/cvs.csv | cut -d "," -f 1 | sort -n)
  #get organisation
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
     echo "Publish new version Content View $i"
     hammer content-view publish --id "$i" --description "$comment" #--async
    done
  }

updateccv() {
  echo "$ccv"
  echo "Publish new versions of Composite Content Views"
   for i in $ccv
    do
     echo "Publish new version Content View $i"
     hammer content-view publish --id "$i" --description "$comment" #--async
    done
  }

promote() {
  env=$1
  #cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$env"
  cat /tmp/les.csv | cut -d ',' -f 2 | grep -i "$env" | while read env2
  do
  #echo env2 is $env2
    contentview=$(grep -i "$env2" /tmp/cvvs.csv | cut -d "," -f 2 | rev | cut -d ' ' -f 1 --complement | rev)
    #echo contentview is $contentview
    versid=$(grep "$contentview" /tmp/cvvs.csv| cut -d ',' -f1 | sort -nr | head -n1)
    #echo versid is $versid
      grep "$contentview" /tmp/cvvs.csv | while IFS=',' read -r id name version description lce #CentOS/hammer 0.19
      #grep "$contentview" /tmp/cvvs.csv | while IFS=',' read -r id name version lce #RedHat/hammer 0.17
      do
      #echo lce is $lce
        lce2="$(echo $lce | tr -d '"'| sed s/Library,//g | sed s/Library//g),"
        #echo lce2 is $lce2
        echo $lce2 | while read -d ',' lce3
        do
          #echo lce3 is $lce3
          lce4=$(echo "$lce3" | grep -i "$env")
          echo lce4 is $lce4
          if [ ! -z "$lce4" ]; then
           echo "Publish latest version/ID $versid Composite Content View $contentview to Lifecycle environments $lce4"
           hammer content-view version promote --id "$versid" --content-view "$contentview" --to-lifecycle-environment "$lce4" --force #--async
           #echo "hammer content-view version promote --id \"$versid\" --content-view \"$contentview\" --to-lifecycle-environment \"$lce4\" --force #--async"
          fi
        done
      done
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
      hammer capsule content synchronize --lifecycle-environment-id $lceid --name 'capsule.local'
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
    echo -e "Usage:\n -l, --list\n    to list published CV versions\n -c, --create\n    to create new CV version\n -p, --promote DEV/TEST/PROD/Name\n    to promote latest CV version to DEV/TEST/PROD/Name\n -s, --synctocapsule\n    to sync content to porc02\n -a, --aufraeumen\n    to clean up to 6 latest versions of Content Views\n -h, --help\n    to read this"
    exit 1
  ;;
esac

echo -e "\ndo not forget to remove your credentials from the config file:\nvim ~/.hammer/cli.modules.d/foreman.yml"
