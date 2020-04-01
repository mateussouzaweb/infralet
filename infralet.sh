#!/usr/bin/env bash
# set -u

export INFRALET_VERSION="0.0.2"
export RUN_PATH="$(pwd)"
export RUN_VARIABLES=""

#
# Printing colored text
# @param $1 expression
# @param $2 color
# @param $3 arrow
# @return void
#
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

#
# Print info message
# @param $1 message
# @return void
#
info() {
    colored_echo "$1" blue "=>"
}

#
# Print success message
# @param $1 message
# @return void
#
success() {
    colored_echo "$1" green "=>"
}

#
# Print error message
# @param $1 message
# @return void
#
error() {
    colored_echo "$1" red "=>"
}

#
# Ask for a response
# @param $1 variable name
# @param $2 question
# @return something
#
ask() {

    local VARIABLE=$1
    local QUESTION=$2

    if [[ ${!VARIABLE} == "" ]] ; then
        read -p "$QUESTION: " ANWSER
        declare "$VARIABLE=$ANWSER"
    fi

    echo ${!VARIABLE}

}

#
# Ask for a yes/no response
# @param $1 variable name
# @param $2 question
# @return false if N, true if Y
#
ask_yes_no() {

    local VARIABLE=$1
    local QUESTION=$2

    while true; do
        ANWSER=$(ask $VARIABLE "$QUESTION [Y/N]")
        case $ANWSER in
            [Yy]*) echo "y"; return 0 ;;
            [Nn]*) echo "n"; return 1 ;;
        esac
    done

}

#
# Ask for sudo password
# @return void
#
ask_sudo_password() {

    info "Prompting for sudo password..."

    if sudo -v; then
        success "Sudo credentials OK."
    else
        error "Failed to obtain sudo credentials."
        exit 1;
    fi

}

#
# Copy file to a location
# @param $1 source
# @param $2 destination
# @return void
#
copy() {

    local OVERWRITTEN=""

    if [ -e "$2" ] || [ -h "$2" ]; then
        OVERWRITTEN="(Overwritten)"
        if ! rm -r "$2"; then
            error "Failed to remove existing file(s) at $2."
        fi
    fi

    if cp "$1" "$2"; then
        success "Copied $1 to $2. $OVERWRITTEN"
    else
        error "Copy of $1 to $2 failed."
    fi

}

#
# Make symbolic link
# @param $1 source
# @param $2 destination
# @return void
#
symlink() {

    local OVERWRITTEN=""

    if [ -e "$2" ] || [ -h "$2" ]; then
        OVERWRITTEN="(Overwritten)"
        if ! rm -r "$2"; then
            error "Failed to remove existing file(s) at $2."
        fi
    fi

    if ln -s "$1" "$2"; then
        success "Symlinked $2 to $1. $OVERWRITTEN"
    else
        error "Symlinking $2 to $1 failed."
    fi

}

#
# Print the version message
# @return void
#
version() {
    echo "Infralet version $INFRALET_VERSION"
}

#
# Print the help message
# @return void
#
help() {

    echo ""
    echo "Whatever you do, infralet it!"
    echo ""
    echo "infralet version - See the program version"
    echo "infralet help - Print this help message"
    echo "infralet install [module] - Install a user defined module"
    echo "infralet upgrade [module] - Upgrade a user defined module"
    echo ""

}

#
# Activate the variables file
# @param $1 module
# @param $2 variables file
# @return void
#
activate_variables() {

    local MODULE=$1
    local FILE="variables.env"
    local LOCATION=$2

    if [ -z "$LOCATION" ]; then
        if [ -f "$RUN_PATH/$MODULE/$FILE" ]; then
            LOCATION="$RUN_PATH/$MODULE/$FILE"
        else
            LOCATION="$RUN_PATH/$FILE"
        fi
    fi

    if [ ! -f "$LOCATION" ]; then
        error "No $FILE found. You must create or tell the $FILE file"
        exit 1;
    else
        export RUN_VARIABLES=$LOCATION
        info "Using the $FILE file located at: $LOCATION"
    fi

    source $LOCATION

}

#
# Write variables to env file
# @return {void}
#
write_variables() {

    info "Finishing..."
    # TODO: develop
    # if [ -f $RUN_VARIABLES ]; then
    #     echo -e "# $QUESTION:\n$VARIABLE=\"$ANWSER\"\n\n" >> "$RUN_VARIABLES"
    # fi

}

#
# Install a module
# @param $1 module
# @param $2 variables file
# @return void
#
install() {

    local MODULE=$1
    local VARIABLES=$2
    local FILE="install.infra"
    local LOCATION="$RUN_PATH/$MODULE/$FILE"

    if [ -z "$MODULE" ]; then
        error "You must tell the module to be installed."
        exit 1;
    fi

    if [ ! -f "$LOCATION" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION"

    activate_variables $MODULE $VARIABLES
    source $LOCATION
    write_variables

    success "Module installation completed."
    exit 0

}

#
# Upgrade a module
# @param $1 module
# @param $2 variables file
# @return void
#
upgrade() {

    local MODULE=$1
    local VARIABLES=$2
    local FILE="upgrade.infra"
    local LOCATION="$RUN_PATH/$MODULE/$FILE"

    if [ -z "$MODULE" ]; then
        error "You must tell the module to be upgraded."
        exit 1;
    fi

    if [ ! -f "$LOCATION" ]; then
        error "No $FILE found. You must create the $FILE file inside module folder: $MODULE/$FILE"
        exit 1;
    fi

    info "Using the $FILE file located at: $LOCATION"

    activate_variables $MODULE $VARIABLES
    source $LOCATION
    write_variables

    success "Module upgrade completed."
    exit 0

}

if [[ $1 =~ ^(version|help|install|upgrade)$ ]]; then
    "$@"
else
    echo "Invalid infralet subcommand: $1" >&2
    exit 1
fi