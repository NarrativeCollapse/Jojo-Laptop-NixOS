# confirm "Question?": ask, and succeed only on an answer starting with y.
# Added in front of the scripts that ask before changing anything.
confirm() {
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}
