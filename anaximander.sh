#!/usr/bin/env bash

# Load oo-bootstrap base code
source "$( cd "${BASH_SOURCE[0]%/*}" && pwd )/lib/oo-bootstrap.sh"

# Import required modules
import util/log
import util/namedParameters

# Set up logging
namespace anaximander

SetupLogs() {
  if [ "$ANAXIMANDER_LOG" == 1 ]
  then
    Log::AddOutput anaximander DEBUG

    Log::AddOutput info INFO

    Log::AddOutput warn WARN

    Log::AddOutput error ERROR
  fi
}

# Reset getopts
OPTIND=1

Help() {
  echo "
Anaximander is a command line tool to generate microservices maps by analyzing the code.
Usage: $(basename "$0") [OPTION]... [TARGET]

    -h, --help        shows this message
    -t, --target      specifies the target location to look in. Default to current dir. Overwrites [TARGET]
    -v, --verbose     shows log messages
"
}

ElementIn () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

function JoinBy { local IFS="$1"; shift; echo "$*"; }


ProcessProject() {
  declare -n PROJECT_ARRAY="$2"

  local IGNORE_FILE="""
.vscode/

node_modules/"""

  local IGNORE_FILE_PATH="$1"/.ignore

  echo -n "$IGNORE_FILE" > "$IGNORE_FILE_PATH"

  local PROJECT_NAME=$(ag --nofilename --nobreak --nocolor -i -o -G 'package\.json' 'name\s*?"\s*?:\s*?"\K[^"]+' "$1")

  local RECEIVES_MATCH=$(ag --nofilename --nobreak --nocolor -i -o '(?s)@MessagePattern\s*?\(.+?\)' "$1") || []

  Log "RECEIVES_MATCH: $RECEIVES_MATCH"
  
  local SENDS_MATCH=$(ag --nofilename --nobreak --nocolor -i -o '(?s)\.send\s*?(<.*>)?\s*\(.+?\)' "$1") || []

  Log "SENDS_MATCH: $SENDS_MATCH"

  rm "$IGNORE_FILE_PATH"

  local sends=$(ExtractArgs "$SENDS_MATCH") || ''
  local receives=$(ExtractArgs "$RECEIVES_MATCH") || ''

  Log "SENDS ARRAY: ${sends[@]}"
  Log "RECEIVES ARRAY: ${receives[@]}"

  echo -n "$PROJECT_NAME," >> $3
  echo -n "$sends," >> $3
  echo "$receives" >> $3

  PROJECT_ARRAY["${PROJECT_NAME}<_:_>sends"]=$sends
  PROJECT_ARRAY["${PROJECT_NAME}<_:_>receives"]=$receives

  Log "RESULTING ARRAY:"

  for x in "${!PROJECT_ARRAY[@]}"; do Log "  [$x]=${PROJECT_ARRAY[$x]}" ; done
}

ExtractArgs() {
  [string] fullMatch

  local BRACKETS_COUNTER=0
  local SINGLE_QUOTE_COUNTER=0
  local DOUBLE_QUOUTE_COUNTER=0
  local ADD_CHARACTER=1

  declare -a ARGUMENTS

  local argument=''

  invalidChars='\s'

  for (( i=0; i<${#fullMatch}; i++ )); do
    local char=${fullMatch:$i:1}
    
    if [[ $char == '(' ]]; then
      if [[ $((BRACKETS_COUNTER++)) > 0 && $ADD_CHARACTER -eq 1 ]]; then
        argument="$argument$char"
      fi
    elif [[ $char == ')' ]]; then
      if [[ $((--BRACKETS_COUNTER)) == 0 ]]; then
        if ElementIn $argument "${ARGUMENTS[@]}"; then
          Log "ARGUMENT: $argument already in array, not adding..."
        else
          ARGUMENTS+=( $argument )
          Log "ARGUMENT ADDED: $argument"
          Log "NEW ARGUMENTS: ${ARGUMENTS[@]}"
        fi;
        argument=''
        ADD_CHARACTER=1
        SINGLE_QUOTE_COUNTER=0
        DOUBLE_QUOUTE_COUNTER=0
      elif [[ $ADD_CHARACTER -eq 1 && $BRACKETS_COUNTER > 0 ]]; then
        argument="$argument$char"
      fi
    elif [[ $char == '"' && ${fullMatch:$((i-1)):1} != "\\" ]]; then
      if [[ $SINGLE_QUOTE_COUNTER -eq 0 && $DOUBLE_QUOUTE_COUNTER -eq 0 ]]; then
        DOUBLE_QUOUTE_COUNTER=$((DOUBLE_QUOUTE_COUNTER+1))
      elif [[ $SINGLE_QUOTE_COUNTER -eq 0 && $DOUBLE_QUOUTE_COUNTER -gt 0 ]]; then
        DOUBLE_QUOUTE_COUNTER=$((DOUBLE_QUOUTE_COUNTER-1))
      fi;
    elif [[ $char == "'" && ${fullMatch:$((i-1)):1} != "\\" ]]; then
      if [[ $DOUBLE_QUOUTE_COUNTER -eq 0 && $SINGLE_QUOTE_COUNTER -eq 0 ]]; then
        SINGLE_QUOTE_COUNTER=$((SINGLE_QUOTE_COUNTER+1))
      elif [[ $DOUBLE_QUOUTE_COUNTER -eq 0 && $SINGLE_QUOTE_COUNTER -gt 0 ]]; then
        SINGLE_QUOTE_COUNTER=$((SINGLE_QUOTE_COUNTER-1))
      fi;
    elif [[ $char == ',' && $SINGLE_QUOTE_COUNTER -eq 0 && $DOUBLE_QUOUTE_COUNTER -eq 0 ]]; then
      ADD_CHARACTER=0
    elif [[ ! $char =~ $invalidChars && $ADD_CHARACTER -eq 1 && $BRACKETS_COUNTER > 0 ]]; then
      argument="$argument$char"
    fi
  done

  JoinBy ';' "${ARGUMENTS[@]}"
}

Main() {

  # parse options
  options=$(getopt -o t:h::v: --long target:,help::,verbose:: --name $(basename "$0") -- "$@")

  # set command sets the positional parameters, so this sets $1 to $options
  eval set -- "$options"

  [ $? -eq 0 ] || {
    subject=error Log "Incorrect options provided"
    Help
    exit 1
  }

  while [ ! -z "$1" ] ; do
    case "$1" in
      -t|--target)
        findTarget=$2 ; shift 2 ;;
      -h|--help)
        Help ; shift ; exit 0 ;;
      -v|--verbose)
        ANAXIMANDER_LOG=1 SetupLogs; shift ;;
      -- ) endOfOptions=1 ; shift ;;
      * )
        Log "endOfOptions - $endOfOptions findTarget - $findTarget"
        if [ $endOfOptions -eq 1 ] && [ -z "$findTarget" ]
        then
          Log "endOfOptions is 1 and findTarget is undefined"
          if [ -d $1 ]
          then
            findTarget=$1
          else
            subject=error Log "Target not valid $1"

            echo "$(UI.Color.Red)Target location is not a valid directory$(UI.Color.Default)" 
            Help ; exit 1
          fi
        fi
        shift ;;
    esac
  done

  if [ -z "$findTarget" ]
  then
    subject=error Log "Target location not specified"

    echo "$(UI.Color.Red)Target location not specified$(UI.Color.Default)"
    Help
    exit
  fi
  
  if ! command -v ag &> /dev/null
  then
    subject=error Log "ag command not found"
    echo "$(UI.Color.Red)It seems that ag is not installed, please refer to the github repo $(UI.Color.Blue)$(UI.Color.Underline)https://github.com/ggreer/the_silver_searcher$(UI.Color.Default)"
    exit
  fi

  OUT_FILE='template/data.csv'

  declare -A PROJECTS

  declare -a folders

  if [ -f "$findTarget/package.json" ]; then
    folders+=("$findTarget")
  fi

  for dir in $(find nest-test/ -name 'package.json'); do
    folders+=("$(dirname $dir)")
  done

  echo "project,sends,receives" > $OUT_FILE
  
  for folder in ${folders[@]}; do
    ProcessProject $folder PROJECTS $OUT_FILE

    Log "TMP PROJECTS"
    for x in "${!PROJECTS[@]}"; do Log "  [$x]=${PROJECTS[$x]}" ; done
  done

  for x in "${!PROJECTS[@]}"; do printf "[%s]=%s\n" "$x" "${PROJECTS[$x]}" ; done

  return 0
}

Main "$@"

exit