#!/usr/bin/env bash
folder="${1:-/}"
threshold="${2:-90}"
if ! [[ "$threshold" =~ ^[0-9]+$ ]]; then
        echo "Threshold should be int number"
        exit 1
fi
if ! [[ -d "$folder" ]]; then
	echo "Error: directory '$folder' not found"
	exit 1
fi

usage=$(df --output=pcent "$folder" | tail -n 1 | tr -d ' %')

echo "Partition $folder filled in on $usage%, threshold $threshold%"

if ((usage > threshold )); then 
	echo "Need archive"
else
	echo "All good"
fi

