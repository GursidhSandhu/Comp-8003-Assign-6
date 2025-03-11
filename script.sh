#!/opt/homebrew/bin/bash

readonly BASE_DIRECTORY="/etc"
readonly STORAGE_DIRECTORY="/Users/gursidhsandhu/Desktop/"

obtain_files() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        echo "Error with directory: $dir"
        exit 1
    fi

    local files=()

    # go through directory and only add files that aren't symbolic links or temp files
    for file in "$dir"/*; do
        [[ -L "$file" ]] && continue  
        [[ "$file" =~ /tmp/ || "$file" =~ /\.swp$/ ]] && continue  

        # recursively call this function for any sub directories
        if [[ -d "$file" ]]; then
            sub_files=($(obtain_files "$file"))
            files=("${files[@]}" "${sub_files[@]}")
        else
            files=("${files[@]}" "$file")  
        fi
    done

    printf "%s\n" "${files[@]}"  
}

generate_hashes() {
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "Error with list of files"
        exit 1
    fi

    local hashes=()

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then  
            hash_value=$(sha256sum "$file" 2>/dev/null)

            # only add the ones where permission was given (since we just want to see hashing in general)
            if [[ -n "$hash_value" ]]; then
            echo "$hash_value"
                hashes+=("$hash_value")
            fi
        fi
    done

    printf "%s\n" "${hashes[@]}"
}

store_hashes() {
    local hashes=("$@")  

    if [[ ${#hashes[@]} -eq 0 ]]; then
        echo "Error with list of hashes"
        exit 1
    fi

    local output_file="${STORAGE_DIRECTORY}etc_hashes.txt"  

    # create file or empty if it already exists
    > "$output_file"  

    # write each hash to file
    for hash in "${hashes[@]}"; do
        echo "$hash" >> "$output_file"
    done

    echo "Hashes successfully saved to $output_file"
}

#helper function used in compare_hashes to just return current hash values
get_current_hashes() {
    local hashesFile="$1"

    if [[ ! -f "$hashesFile" || ! -s "$hashesFile" ]]; then
        echo "Error with hashesFile: File is missing or empty."
        exit 1
    fi

    local currentHashes=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue  
        currentHashes+=("$line")
    done < "$hashesFile"

    printf "%s\n" "${currentHashes[@]}"  
}

compare_hashes() {
    local hashesFile="$1"

    if [[ ! -d "$STORAGE_DIRECTORY" ]]; then
        echo "Error with directory: $STORAGE_DIRECTORY"
        exit 1
    fi

    if [[ ! -f "$hashesFile" || ! -s "$hashesFile" ]]; then
        echo "Error with hashesFile: File is missing or empty."
        exit 1
    fi


    # make these maps (associative arrays) so we can easily compare the hashes
    declare -A currentMap newMap
    local changes=()

    while IFS= read -r line; do
        hash=$(echo "$line" | cut -d' ' -f1)
        filename=$(echo "$line" | cut -d' ' -f2-)
        currentMap["$filename"]="$hash"
    done < <(get_current_hashes "$hashesFile")

    currentFiles=()
    while IFS= read -r file; do
        currentFiles+=("$file")
    done < <(obtain_files "$BASE_DIRECTORY")

    # make the new hashes from current files
    while IFS= read -r line; do
        hash=$(echo "$line" | cut -d' ' -f1)
        filename=$(echo "$line" | cut -d' ' -f2-)
        newMap["$filename"]="$hash"
    done < <(generate_hashes "${currentFiles[@]}")

    # check both maps to see if files were deleted or added
    for file in "${!newMap[@]}"; do
        if [[ -z "${currentMap[$file]}" ]]; then
            changes+=("File added: $file")
        fi
    done

    for file in "${!currentMap[@]}"; do
        if [[ -z "${newMap[$file]}" ]]; then
            changes+=("File deleted: $file")
        fi
    done

    # now check for any changes in files that are in both maps
    for file in "${!newMap[@]}"; do
        if [[ -n "${currentMap[$file]}" && "${currentMap[$file]}" != "${newMap[$file]}" ]]; then
            changes+=("File changed: $file")
        fi
    done

    if [[ ${#changes[@]} -gt 0 ]]; then
        printf "%s\n" "${changes[@]}"
    fi
}


create_report() {
    local changes=("$@")  
    local output_file="${STORAGE_DIRECTORY}integrity_report.txt"

    > "$output_file"

    # If there are changes, write them to the file
    if [[ ${#changes[@]} -gt 0 ]]; then
        for change in "${changes[@]}"; do
            echo "$change" >> "$output_file"
        done
    else
        echo "No changes were found, /etc directory is safe!" >> "$output_file"
    fi

    echo "Report successfully saved to $output_file"
}


display_report() {
    local report_file=("$@")

    if [[ ! -f "$report_file" ]]; then
        echo "Error finding report: $report_file"
        exit 1
    fi

    # just read report file
    while IFS= read -r line; do
        echo "$line"
    done < "$report_file"
}

main(){

# make sure only one argument is given
if [[ $# -ne 1 ]]; then
    echo "Error: Only one command-line argument is allowed."
    echo "Usage: $0 --baseline | --check | --report"
    exit 1
fi

choice="$1"

case "$choice" in
    --baseline)
        
        currentFiles=()
        while IFS= read -r file; do
            currentFiles+=("$file")
        done < <(obtain_files "$BASE_DIRECTORY")

        hashes=()
        while IFS= read -r line; do
            hashes+=("$line")  
        done < <(generate_hashes "${currentFiles[@]}")

        store_hashes "${hashes[@]}"  
        ;;

    --check)
        changes=()
        while IFS= read -r file; do
            changes+=("$file")
        done < <(compare_hashes "${STORAGE_DIRECTORY}etc_hashes.txt" )

        create_report "${changes[@]}"
        ;;
    --report)
        display_report "${STORAGE_DIRECTORY}integrity_report.txt"
        ;;
    *)
        echo "Error with chosen command line argument"
        echo "Usage: $0 --baseline OR --check OR --report"
        exit 1
        ;;
esac
}

main "$@"