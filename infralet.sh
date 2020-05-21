#!/usr/bin/env bash

export INFRALET_VERSION="0.0.14"
export RUN_PATH="$(pwd)"
export RUN_CMD=( $@ )

# Printing colored text
# @param $1 expression
# @param $2 color
# @param $3 arrow
colored_echo() {

    local MESSAGE="$1";
    local COLOR="$2";
    local ARROW="$3";

    if ! [[ $COLOR =~ '^[0-9]$' ]] ; then
       case $(echo $COLOR | tr '[:upper:]' '[:lower:]') in
        black) COLOR=0 ;;
        red) COLOR=1 ;;
        green) COLOR=2 ;;
        yellow) COLOR=3 ;;
        blue) COLOR=4 ;;
        magenta) COLOR=5 ;;
        cyan) COLOR=6 ;;
        white|*) COLOR=7 ;; # white or invalid color
       esac
    fi

    if [[ -t 1 ]]; then
        tput bold;
        tput setaf "$COLOR";
        echo "$ARROW $MESSAGE";
        tput sgr0;
    else
        echo "$ARROW $MESSAGE";
    fi

}

# Print info message
# @param $1 message
info() {
    colored_echo "$1" blue "=>"
}

# Print warning message
# @param $1 message
warning() {
    colored_echo "$1" yellow "=>"
}

# Print success message
# @param $1 message
success() {
    colored_echo "$1" green "=>"
}

# Print error message
# @param $1 message
error() {
    colored_echo "$1" red "=>"
}

# Ask for a response
# @param $1 variable name
# @param $2 default value
# @param $3 question
ask() {

    local VARIABLE="$1"
    local DEFAULT="$2"
    local QUESTION="$3"
    local EXTRA=""

    if [ ! -z "$DEFAULT" ]; then
        EXTRA=" [Default: $DEFAULT]"
    fi

    if [[ ${!VARIABLE} == "" ]] ; then
        read -p "$QUESTION$EXTRA: " ANWSER
        ANWSER="${ANWSER:-${DEFAULT}}"
        export "$VARIABLE=$ANWSER"
    fi

}

# Ask for a yes/no response
# Return N if false and Y if true
# @param $1 variable name
# @param $2 default value
# @param $3 question
ask_yes_no() {

    local VARIABLE="$1"
    local DEFAULT="$2"
    local QUESTION="$3"

    while true; do
        ask $VARIABLE $DEFAULT "$QUESTION (Y/N)"
        case ${!VARIABLE} in
            [Yy]*) export "$VARIABLE=Y"; return 0 ;;
            [Nn]*) export "$VARIABLE=N"; return 1 ;;
        esac
    done

}

# Ask for sudo password
ask_sudo_password() {

    if [ ${EUID:-$(id -u)} -eq 0 ]; then
        success "Sudo credentials OK."
    else
        error "Running as not sudo, please use: sudo infralet [command]..."
        exit 1;
    fi

}

# Normalize a file path and return desired info
# @param $1 file
# @param $2 type
normalize() {

    local FILE="$1"
    local TYPE="$2"
    local REAL=$(realpath -s "$FILE")

    if [ "$TYPE" == "dir" ]; then
        REAL=$(dirname "$REAL")
    elif [ "$TYPE" == "name" ]; then
        REAL=$(basename "$REAL")
    fi

    echo "$REAL"
}

# manipulate file by symlink, copy or append
# @param $1 type
# @param $2 source
# @param $3 destination
manipulate_file() {

    local TYPE="$1"
    local SOURCE=$(normalize "$2")
    local DESTINATION=$(normalize "$3")

    local TEMPORARY="/tmp/.infralet"
    local OVERWRITTEN=""

    # Check source file
    if [ -z "$SOURCE" -o ! -f "$SOURCE" ]; then
        error "Command $TYPE failed. Source file does not exists: $SOURCE"
        exit 1;
    fi

    # Check if source is symbolic
    if [ -h "$SOURCE" ]; then
         error "Command $TYPE failed. Source file is symbolic link: $SOURCE"
        exit 1;
    fi

    # Check source is equal destination
    if [ "$SOURCE" == "$DESTINATION" ]; then
        error "Command $TYPE failed. Source file is the same as destination: $SOURCE"
        exit 1;
    fi

    # Check destination for append
    if [ "$TYPE" == "append" ] && [ -z "$DESTINATION" -o ! -f "$DESTINATION" ]; then
        error "Command $TYPE failed. Destination file does not exists: $DESTINATION"
        exit 1;

    # Clean destination for copy and symlink
    elif [ "$TYPE" != "append" ]; then

        if [ -e "$DESTINATION" ] || [ -h "$DESTINATION" ]; then
            OVERWRITTEN="(Overwritten)"
            if ! rm -r "$DESTINATION"; then
                error "Command $TYPE error. Failed to remove existing file(s) at $DESTINATION."
                exit 1;
            fi
        fi

    fi

    # Copy
    if [ "$TYPE" == "copy" ]; then

        if cp "$SOURCE" "$DESTINATION"; then
            success "Copied $SOURCE to $DESTINATION. $OVERWRITTEN"
        else
            error "Copy of $SOURCE to $DESTINATION failed."
            exit 1;
        fi

        replace_variables $DESTINATION

    # Append
    elif [ "$TYPE" == "append" ]; then

        cat <<< "
$(cat $SOURCE)" > $TEMPORARY && \
        replace_variables $TEMPORARY && \
        cat $TEMPORARY >> $DESTINATION && \
        rm $TEMPORARY

        success "Content of $SOURCE added to $DESTINATION."

    # Symlink
    elif [ "$TYPE" == "symlink" ]; then

        if ln -s "$SOURCE" "$DESTINATION"; then
            success "Symlinked $DESTINATION to $SOURCE. $OVERWRITTEN"
        else
            error "Symlinking $DESTINATION to $SOURCE failed."
            exit 1;
        fi

    fi

}

# Copy file to a location
# Also replace variables inside a file
# @param $1 source
# @param $2 destination
copy() {
    manipulate_file "copy" "$1" "$2"
}

# Append content on file
# Also replace variables inside the file
# @param $1 source
# @param $2 destination
append() {
    manipulate_file "append" "$1" "$2"
}

# Make symbolic link
# @param $1 source
# @param $2 destination
symlink() {
    manipulate_file "symlink" "$1" "$2"
}

# Replace match on string
# @param $1 search
# @param $2 replace
# @param $3 string
str_replace(){

    local SEARCH="$1"
    local REPLACE="$2"
    local STRING="$3"

    if [ -z "$STRING" ]; then
        STRING=$(</dev/stdin)
    fi

    echo $(echo "$STRING" | awk '{gsub("'$SEARCH'","'$REPLACE'"); print}')
}

# Retrieve cli parsed param
# @param $1 param
# @param $2 default
# @param $3 flag
get_param() {

    local PARAM="$1"
    local RESULT="$2"
    local FLAG="$3"
    local LEN=${#RUN_CMD[@]}

    if [ "$PARAM" == "_last_" ]; then
        RESULT=${RUN_CMD[$LEN-1]}
    elif [ "$PARAM" == "_first_" ]; then
        RESULT=${RUN_CMD[0]}
    else
        for (( i=0; i<$LEN; i++ )); do
            if [ "${RUN_CMD[ $i ]}" == "$PARAM" -a "$FLAG" == true ]; then
                break
            fi
            if [ "${RUN_CMD[$i]}" == "$PARAM" ]; then
                RESULT=${RUN_CMD[ ($i + 1) ]}
                break
            fi
        done
    fi

    echo $RESULT

}

# Recursive load variables from directory
# @param $1 directory
load_variables() {

    local FILE="variables.env"
    local DIRECTORY=$(normalize "$1" | str_replace "$FILE" "")
    local LOCATION=$(echo "$DIRECTORY/$FILE" | str_replace "//" "/")

    while [ ! -f "$LOCATION" ]; do

        DIRECTORY=$(dirname "$DIRECTORY")
        LOCATION="$DIRECTORY/$FILE"

        if [ "$DIRECTORY" == "$RUN_PATH" ]; then
            break;
        elif [ "$DIRECTORY" == "/" ]; then
            break;
        fi

    done

    if [ ! -f "$LOCATION" ]; then
        warning "No $FILE found. You must create or tell the $FILE file. Skipping..."
    else
        info "Using the $FILE file located at: $LOCATION"
        if [ -s "$LOCATION" ]; then
            export $(grep -v '^#' $LOCATION | xargs)
        fi
    fi

}

# Extract and print variables with their default values on stdout
# @param $1 command
extract_variables() {

    local PARSED=$(echo "$1" | str_replace ".infra" "")
    local LOCATION=$(normalize "$PARSED" "dir")
    local COMMAND=$(normalize "$PARSED" "name")
    local FILE="$COMMAND.infra"

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $LOCATION/$FILE"
        exit 1;
    fi

    cat $LOCATION/$FILE | awk '/ask |ask_yes_no / {print $0}' | awk 'BEGIN {FPAT = "([^ ]+)|(\"[^\"]+\")"}{for(i=1;i<=NF;i++){gsub(" "," ",$i)} print $2"="$3}'

}

# Replace env variables on file
# To avoid unnecessary scaping, only works with ${VAR} sintax
# @param $1 file
replace_variables() {

    local FILE=$(normalize "$1")

    if [ ! -f "$FILE" ]; then
        error "File not found to replace variables: $FILE"
        exit 1;
    fi

    TPL=$(cat $FILE)

    for ROW in $(env); do

        SAVEIFS=$IFS
        IFS="="
        read KEY VALUE <<< "$ROW"
        IFS=$SAVEIFS

        if [[ "$KEY" =~ ^[A-Z0-9_]+$ ]]; then
            TPL=$(echo "$TPL" | awk '{gsub(/\$\{'"$KEY"'\}/,"'"$VALUE"'"); print}')
        fi

    done;

    echo "$TPL" > "$FILE"

}

# Run module command
execute_command() {

    local VARIABLES=$(get_param "--e")
    local PARSED=$(get_param "_last_" | str_replace ".infra" "")

    if [ -z "$PARSED" ]; then
        error "You must tell the command to run."
        exit 1;
    fi

    local LOCATION=$(normalize "$PARSED" "dir")
    local COMMAND=$(normalize "$PARSED" "name")
    local FILE="$COMMAND.infra"

    if [ -z "$VARIABLES" ]; then
        VARIABLES="$LOCATION"
    fi

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $LOCATION/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION/$FILE"

    load_variables $VARIABLES && \
    cd $LOCATION && \
    source $FILE && \
    cd $RUN_PATH

    success "Module command completed."

}

# Extract and print variables with their default values on stdout
# @param $1 command
# @param $2 command
# @param $3 command...
extract() {

    argc=$#
    argv=("$@")

    for (( j=0; j<argc; j++ )); do
        extract_variables "${argv[j]}"
    done

}

# Print the version message
version() {
    echo "Infralet version $INFRALET_VERSION"
}

# Print the help message
help() {

    cat - >&2 <<EOF
Whatever you do, infralet it!

infralet version
    - See the program version.

infralet help
    - Print this help message.

infralet extract [command] [command...] [command...]
    - Extract variables created by ask commands.

infralet [--e variables.env] [command]
    - Execute a user defined command.
EOF

}

if [[ $1 =~ ^(version|help|extract)$ ]]; then
    "$@"
elif [[ ! -z $1 ]]; then
    execute_command
else
    echo "Invalid infralet subcommand: $1" >&2
    exit 1
fi