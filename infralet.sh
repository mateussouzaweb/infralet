#!/usr/bin/env bash

export INFRALET_VERSION="0.0.2"
export INFRALET_RUN_PATH="$(pwd)"

##
## PRINT FUNCTIONS
##

# Printing colored text
# @param $1 expression
# @param $2 color
__colored_echo() {

    local MESSAGE="$1";
    local COLOR="$2";

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
        echo "$MESSAGE";
        tput sgr0;
    else
        echo "$MESSAGE";
    fi

}

# Print info message
# @param $1 message
__info() {
    __colored_echo "$1" blue
}

# Print warning message
# @param $1 message
__warning() {
    __colored_echo "$1" yellow
}

# Print success message
# @param $1 message
__success() {
    __colored_echo "$1" green
}

# Print error message
# @param $1 message
__error() {
    __colored_echo "$1" red
}

##
## ASK FUNCTIONS
##

# Ask for a response
# @param $1 variable name
# @param $2 default value
# @param $3 question
__ask() {

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
__ask_yes_no() {

    local VARIABLE="$1"
    local DEFAULT="$2"
    local QUESTION="$3"

    while true; do
        __ask $VARIABLE $DEFAULT "$QUESTION (Y/N)"
        case ${!VARIABLE} in
            [Yy]*) export "$VARIABLE=Y"; return 0 ;;
            [Nn]*) export "$VARIABLE=N"; return 1 ;;
        esac
    done

}

##
## PATH AND FILE FUNCTIONS
##

# Normalize a file path and return desired info
# @param $1 file
# @param $2 type
__normalize_path() {

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
__manipulate_file() {

    local TYPE="$1"
    local SOURCE=$(__normalize_path "$2")
    local DESTINATION=$(__normalize_path "$3")

    local TEMPORARY="/tmp/.infralet"
    local OVERWRITTEN=""

    # Check source file
    if [ -z "$SOURCE" -o ! -f "$SOURCE" ]; then
        __error "Command $TYPE failed. Source file does not exists: $SOURCE"
        exit 1;
    fi

    # Check if source is symbolic
    if [ -h "$SOURCE" ]; then
        __error "Command $TYPE failed. Source file is symbolic link: $SOURCE"
        exit 1;
    fi

    # Check source is equal destination
    if [ "$SOURCE" == "$DESTINATION" ]; then
        __error "Command $TYPE failed. Source file is the same as destination: $SOURCE"
        exit 1;
    fi

    # Check destination for append
    if [ "$TYPE" == "append" ] && [ -z "$DESTINATION" -o ! -f "$DESTINATION" ]; then
        __error "Command $TYPE failed. Destination file does not exists: $DESTINATION"
        exit 1;

    # Clean destination for copy and symlink
    elif [ "$TYPE" != "append" ]; then

        if [ -e "$DESTINATION" ] || [ -h "$DESTINATION" ]; then
            OVERWRITTEN="(Overwritten)"
            if ! rm -r "$DESTINATION"; then
                __error "Command $TYPE error. Failed to remove existing file(s) at $DESTINATION."
                exit 1;
            fi
        fi

    fi

    # Copy
    if [ "$TYPE" == "copy" ]; then

        if cp "$SOURCE" "$DESTINATION"; then
            __success "Copied $SOURCE to $DESTINATION. $OVERWRITTEN"
        else
            __error "Copy of $SOURCE to $DESTINATION failed."
            exit 1;
        fi

        __replace_variables $DESTINATION

    # Append
    elif [ "$TYPE" == "append" ]; then

        cat <<< "
$(cat $SOURCE)" > $TEMPORARY && \
        __replace_variables $TEMPORARY && \
        cat $TEMPORARY >> $DESTINATION && \
        rm $TEMPORARY

        __success "Content of $SOURCE added to $DESTINATION."

    # Symlink
    elif [ "$TYPE" == "symlink" ]; then

        if ln -s "$SOURCE" "$DESTINATION"; then
            __success "Symlinked $DESTINATION to $SOURCE. $OVERWRITTEN"
        else
            __error "Symlinking $DESTINATION to $SOURCE failed."
            exit 1;
        fi

    fi

}

# Copy file to a location
# Also replace variables inside a file
# @param $1 source
# @param $2 destination
__copy() {
    __manipulate_file "copy" "$1" "$2"
}

# Append content on file
# Also replace variables inside the file
# @param $1 source
# @param $2 destination
__append() {
    __manipulate_file "append" "$1" "$2"
}

# Make symbolic link
# @param $1 source
# @param $2 destination
__symlink() {
    __manipulate_file "symlink" "$1" "$2"
}

##
## VARIABLES FUNCTIONS
##

# Recursive load variables from directory
# @param $1 directory
__load_variables() {

    local FILE="variables.env"
    local DIRECTORY=$(__normalize_path "$1" | __str_replace "$FILE" "")
    local LOCATION=$(echo "$DIRECTORY/$FILE" | __str_replace "//" "/")

    while [ ! -f "$LOCATION" ]; do

        DIRECTORY=$(dirname "$DIRECTORY")
        LOCATION="$DIRECTORY/$FILE"

        if [ "$DIRECTORY" == "$INFRALET_RUN_PATH" ]; then
            break;
        elif [ "$DIRECTORY" == "/" ]; then
            break;
        fi

    done

    if [ ! -f "$LOCATION" ]; then
        __warning "No $FILE found. You must create or tell the $FILE file. Skipping..."
    else
        __info "Using the $FILE file located at: $LOCATION"
        if [ -s "$LOCATION" ]; then
            export $(grep -v '^#' $LOCATION | xargs)
        fi
    fi

}

# Extract and print variables with their default values on stdout
# @param $1 command
__extract_variables() {

    local PARSED=$(echo $1 | sed 's/\.infra$//g')
    local LOCATION=$(__normalize_path "$PARSED" "dir")
    local COMMAND=$(__normalize_path "$PARSED" "name")
    local FILE="$COMMAND.infra"

    if [ ! -f "$LOCATION/$FILE" ]; then
        __error "No $FILE found. You must create the $FILE file inside module folder: $LOCATION/$FILE"
        exit 1;
    fi

    cat $LOCATION/$FILE | awk '/infralet ask |infralet ask_yes_no / {print $0}' | awk 'BEGIN {FPAT = "([^ ]+)|(\"[^\"]+\")"}{for(i=1;i<=NF;i++){gsub(" "," ",$i)} print $3"="$4}'

}

# Replace env variables on file
# To avoid unnecessary escaping, only works with ${VAR} sintax
# @param $1 file
__replace_variables() {

    local FILE=$(__normalize_path "$1")

    if [ ! -f "$FILE" ]; then
        __error "File not found to replace variables: $FILE"
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

##
## HELPER FUNCTIONS
##

# Allow execution only in sudo mode
__only_sudo() {

    if [ ${EUID:-$(id -u)} -eq 0 ]; then
        __success "Sudo credentials OK."
    else
        __error "Running as not sudo, please use: sudo infralet [command]..."
        exit 1;
    fi

}

# Replace match on string
# @param $1 search
# @param $2 replace
# @param $3 string
__str_replace(){

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
# @param $4 full cmd...
__get_param() {

    local PARAM="$1"; shift
    local RESULT="$2"; shift
    local FLAG="$3"; shift

    local CMD=( $@ )
    local LEN=${#CMD[@]}

    if [ "$PARAM" == "_last_" ]; then
        RESULT=${CMD[$LEN-1]}
    elif [ "$PARAM" == "_first_" ]; then
        RESULT=${CMD[0]}
    else
        for (( i=0; i<$LEN; i++ )); do
            if [ "${CMD[ $i ]}" == "$PARAM" -a "$FLAG" == true ]; then
                break
            fi
            if [ "${CMD[$i]}" == "$PARAM" ]; then
                RESULT=${CMD[ ($i + 1) ]}
                break
            fi
        done
    fi

    echo $RESULT

}

##
## RUN FUNCTIONS
##

# Run module command
__run() {

    local PARSED=$(echo $1 | sed 's/\.infra$//g')
    local VARIABLES=$(__get_param "--e" "" "" $@)

    if [ -z "$PARSED" ]; then
        __error "You must tell the command to run."
        exit 1;
    fi

    local LOCATION=$(__normalize_path "$PARSED" "dir")
    local COMMAND=$(__normalize_path "$PARSED" "name")
    local FILE="$COMMAND.infra"

    if [ -z "$VARIABLES" ]; then
        VARIABLES="$LOCATION"
    fi

    if [ ! -f "$LOCATION/$FILE" ]; then
        __error "No $FILE found. You must create the $FILE file inside module folder: $LOCATION/$FILE"
        exit 1;
    fi

    __info "Using the $FILE file located at: $LOCATION/$FILE"

    __load_variables $VARIABLES && \
    cd $LOCATION && \
    source $FILE && \
    cd $INFRALET_RUN_PATH

    __success "Module command completed."

}

# Extract and print variables with their default values on stdout
# @param $1 command
# @param $2 command
# @param $3 command...
__extract() {

    argc=$#
    argv=("$@")

    for (( j=0; j<argc; j++ )); do
        __extract_variables "${argv[j]}"
    done

}

# Print the version message
__version() {
    echo "Infralet version $INFRALET_VERSION"
}

# Print the help message
__help() {

    cat - >&2 <<EOF
Whatever you do, INFRALET it!

== COMMANDS ==

infralet version
    - See the program version.

infralet help
    - Print this help message.

infralet run [command.infra] [--e variables.env]
    - Execute a user defined command file.

infralet extract [command] [command...] [command...]
    - Extract variables created by ask commands.

== HELPERS ==

infralet info
    - Print a info message.

infralet warning
    - Print a warning message.

infralet success
    - Print a success message.

infralet error
    - Print a error message.

infralet ask
    - Ask for a question.

infralet ask_yes_no
    - Ask for a question with a yes/no response.

infralet copy
    - Copy a file to a given location.

infralet append
    - Append the file contents to a given file.

infralet symlink
    - Symbolic link a path to another file.

infralet only_sudo
    - Allow the execution only with the sudo user.

== OTHERS (less used) ==

infralet colored_echo
    - Print a colored message.

infralet normalize_path
    - Normalize a given path.

infralet manipulate_file
    - Manipulate a given file.

infralet load_variables
    - Load variables from file.

infralet extract_variables
    - Extract variables from file.

infralet replace_variables
    - Replace current enviroment variables on the given file with the real value.

infralet str_replace
    - Replace matches on the give string.

infralet get_param
    - Retrieve CLI param.
EOF

}

# Launcher function
infralet() {

    if type "__$1" >/dev/null 2>&1; then
        subcommand=$1; shift
        "__$subcommand" "$@"
    elif [[ ! -z $1 ]]; then
        __error "Invalid infralet subcommand: $1." >&2
        exit 1
    else
        __error "Invalid infralet subcommand. The command is missing." >&2
        exit 1
    fi

}

infralet "$@"