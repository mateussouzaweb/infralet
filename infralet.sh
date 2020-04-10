#!/usr/bin/env bash

export INFRALET_VERSION="0.0.11"
export RUN_PATH="$(pwd)"

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

    tput bold;
    tput setaf "$COLOR";
    echo "$ARROW $MESSAGE";
    tput sgr0;

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

# Manipulate file by symlink, copy or append
# @param $1 type
# @param $2 source
# @param $3 destination
manipulate() {

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
    manipulate "copy" "$1" "$2"
}

# Append content on file
# Also replace variables inside the file
# @param $1 source
# @param $2 destination
append() {
    manipulate "append" "$1" "$2"
}

# Make symbolic link
# @param $1 source
# @param $2 destination
symlink() {
    manipulate "symlink" "$1" "$2"
}

# Recursive load variables from directory
# @param $1 directory
load_variables() {

    local DIRECTORY=$(normalize "$1")
    local FILE="variables.env"
    local LOCATION="$DIRECTORY/$FILE"

    while [ ! -f "$LOCATION" ]; do

        DIRECTORY=$(dirname "$DIRECTORY")
        LOCATION="$DIRECTORY/$FILE"

        if [ "$DIRECTORY" == "$RUN_PATH" ]; then
            break;
        fi

    done

    if [ ! -f "$LOCATION" ]; then
        error "No $FILE found. You must create or tell the $FILE file."
        exit 1;
    else
        info "Using the $FILE file located at: $LOCATION"
    fi

    export $(grep -v '^#' $LOCATION | xargs)

}

# Extract and print variables with their default values on stdout
# @param $1 command
# @param $2 module
extract_variables() {

    local FILE="$1.infra"
    local LOCATION=$(normalize "$2")
    local MODULE=$(normalize "$LOCATION" "name")

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
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
# @param $1 module
# @param $2 command
# @param $3 variables
module_command() {

    if [ -z "$1" ]; then
        error "You must tell the module to run command."
        exit 1;
    fi

    if [ -z "$2" ]; then
        error "You must tell the command to run."
        exit 1;
    fi

    local LOCATION=$(normalize "$1")
    local MODULE=$(normalize "$LOCATION" "name")
    local FILE="$2.infra"
    local VARIABLES="$3"

    if [ ! -f "$LOCATION/$FILE" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION/$FILE"

    load_variables $LOCATION && \
    cd $LOCATION && \
    source $FILE && \
    cd $RUN_PATH

    success "Module command completed."

}

# Extract and print variables with their default values on stdout
# @param $1 command
# @param $2 module
# @param $3 module...
extract() {

    argc=$#
    argv=("$@")

    for (( j=1; j<argc; j++ )); do
        extract_variables "$1" "${argv[j]}"
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

infralet extract [command] [module] [module...] [module...]
    - Extract module(s) variables created by ask commands.

infralet [module] [command]
    - Execute a user defined command on module.
EOF

}

if [[ $1 =~ ^(version|help|extract)$ ]]; then
    "$@"
elif [[ ! -z $2 ]]; then
    module_command "$2" "$1" "$3"
else
    echo "Invalid infralet subcommand: $1" >&2
    exit 1
fi