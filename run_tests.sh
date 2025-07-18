#!/usr/bin/env bash

file_dir=$(dirname $(realpath $0))

test_dir="$file_dir"
if [ $# -ge 1 ]; then
    test_dir="$file_dir/$1"
fi

if [[ -d "$test_dir" ]]; then
    error=false
    echo "Running all tests in $test_dir"
    file_list=$(find "$test_dir" -not -wholename "*.zig-cache*" -and -name "*.zig" | xargs)
    for file in $file_list; do
        echo "Testing $file"
        zig test "$file"
        if [[ $? -ne 0 ]]; then
            error=true
        fi
    done
    if [[ "$error" == true ]]; then
        exit 1;
    else
        exit 0;
    fi
else
    echo "Directory $test_dir does not exist"
    exit 1
fi

