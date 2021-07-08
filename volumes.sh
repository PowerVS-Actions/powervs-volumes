#!/bin/bash

: '
Copyright (C) 2021 IBM Corporation
Licensed under the Apache License, Version 2.0 (the “License”);
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an “AS IS” BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
    Rafael Sene <rpsene@br.ibm.com> - Initial implementation.
'

# Trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
    echo "Bye!"
    exit 0
}

function check_dependencies() {

    DEPENDENCIES=(ibmcloud curl sh wget jq)
    check_connectivity
    for i in "${DEPENDENCIES[@]}"
    do
        if ! command -v "$i" &> /dev/null; then
            echo "$i could not be found, exiting!"
            exit
        fi
    done
}

function check_connectivity() {

    if ! curl --output /dev/null --silent --head --fail http://cloud.ibm.com; then
        echo
        echo "ERROR: please, check your internet connection."
        exit 1
    fi
}

function authenticate() {

    local APY_KEY="$1"

    if [ -z "$APY_KEY" ]; then
        echo "API KEY was not set."
        exit
    fi
    ibmcloud login --no-region --apikey "$APY_KEY" > /dev/null 2>&1
}

function get_all_services() {
	VAR=("$(ibmcloud pi service-list --json | jq -r '.[] | "\(.CRN)"')")
	for crn in "${VAR[@]}"; do
		echo "$crn" >> "$(pwd)"/all-crns-"$1"
	done
}

function set_powervs() {

    local CRN="$1"
    if [ -z "$CRN" ]; then
        echo "CRN was not set."
        exit
    fi
    ibmcloud pi st "$CRN" > /dev/null 2>&1
}

function get_volumes(){
	CRN=()
	while IFS= read -r line; do
		clean_line=$(echo "$line" | tr -d '\r')
		CRN+=("$clean_line")
	done < "$(pwd)"/all-crns-"$1"

    for crn in "${CRN[@]}"; do
        set_powervs "$crn"
        JSON=/tmp/volumes-log.json
        > $JSON

		PVS_ZONE=$(echo "$crn" | awk -F ':' '{print $6}')

        ibmcloud pi volumes --json | jq -r '.Payload.volumes[] | "\(.volumeID),\(.pvmInstanceIDs)"' >> $JSON

        while IFS= read -r line; do
            VOLUME=$(echo "$line" | awk -F ',' '{print $1}')
            RAW_DATA=$(ibmcloud pi volume --json "$VOLUME")
            if [[ ! "$RAW_DATA" == *"Failed to show volume"* ]]; then
                RAW_DATA_JQ=$(echo "$RAW_DATA" | jq -r '[.size,.diskType] | @csv' | tr -d "\"")

                SIZE=$(echo "$RAW_DATA_JQ" | awk -F ',' '{print $1}')
                TIER=$(echo "$RAW_DATA_JQ" | awk -F ',' '{print $2}')
                if [ -z "$SIZE" ]; then
                    SIZE=0
                fi
                if [ -z "$TIER" ]; then
                    TIER=none
                fi
                echo "$VOLUME,$2,$1,$PVS_ZONE,$TIER,$SIZE" >> "$(pwd)"/all-volumes.csv
            fi
        done < "$JSON"
    done
    cat ./all-volumes.csv
}

function run() {

	ACCOUNTS=()
	while IFS= read -r line; do
		clean_line=$(echo "$line" | tr -d '\r')
		ACCOUNTS+=("$clean_line")
	done < ./cloud_accounts

    rm -f "$(pwd)"/all-crns*

	for i in "${ACCOUNTS[@]}"; do
		IBMCLOUD=$(echo "$i" | awk -F "," '{print $1}')
		IBMCLOUD_ID=$(echo "$IBMCLOUD" | awk -F ":" '{print $1}')
		IBMCLOUD_NAME=$(echo "$IBMCLOUD" | awk -F ":" '{print $2}')
		API_KEY=$(echo "$i" | awk -F "," '{print $2}')

		if [ -z "$API_KEY" ]; then
		    echo
			echo "ERROR: please, set your IBM Cloud API Key."
			echo "		 e.g ./vms-age.sh API_KEY"
			echo
			exit 1
		else
			check_dependencies
			check_connectivity
			authenticate "$API_KEY"
			get_all_services "$IBMCLOUD_ID"
            get_volumes "$IBMCLOUD_ID" "$IBMCLOUD_NAME"
		fi
	done
}

run "$@"
