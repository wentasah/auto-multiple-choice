
try_one() {
  t=$1
  if $t --to-stdout $ARGS $@ > $RESULT_FILE
  then
      echo -e "[ \e[0;32mOK\e[0m ] $t"
      return 0
  else
      echo -e "[\e[0;31mFAIL\e[0m] $t"
      sed ' s/^/       /;' $RESULT_FILE
      return 1
  fi
}
