#!/usr/bin/env sh

SizeChecker(){
    # adding a tiny delay here to to give the kernel a bit time to
    # report new sizes correctly after a terminal resize
    # this reduces "flickering" of GenerateSizeDependendOutput() items
    # after a terminal re-size
    sleep 0.1
    console_height=$(stty size | awk '{ print $1 }')
    console_width=$(stty size | awk '{ print $2 }')

  # Below Pico. Gives you nothing...
  if [ "$console_width" -lt "20" ] || [ "$console_height" -lt "10" ]; then
    # Nothing is this small, sorry
    padd_size="ants"
  # Below Nano. Gives you Pico.
  elif [ "$console_width" -lt "24" ] || [ "$console_height" -lt "12" ]; then
    padd_size="pico"
  # Below Micro, Gives you Nano.
  elif [ "$console_width" -lt "30" ] || [ "$console_height" -lt "16" ]; then
    padd_size="nano"
  # Below Mini. Gives you Micro.
  elif [ "$console_width" -lt "40" ] || [ "$console_height" -lt "18" ]; then
    padd_size="micro"
  # Below Tiny. Gives you Mini.
  elif [ "$console_width" -lt "53" ] || [ "$console_height" -lt "20" ]; then
      padd_size="mini"
  # Below Slim. Gives you Tiny.
  elif [ "$console_width" -lt "60" ] || [ "$console_height" -lt "21" ]; then
      padd_size="tiny"
  # Below Regular. Gives you Slim.
  elif [ "$console_width" -lt "80" ] || [ "$console_height" -lt "26" ]; then
    if [ "$console_height" -lt "22" ]; then
      padd_size="slim"
    else
      padd_size="regular"
    fi
  # Mega
  else
    padd_size="mega"
  fi
}

clear
setterm -cursor off
trap "{ setterm -cursor on ; echo "" ; exit 0 ; }" INT TERM EXIT

while true; do
    # Clear to end of screen (below the drawn dashboard)
    tput ed

    # Move the cursor to top left of console to redraw
    tput cup 0 0


    console_width=$(tput cols)
    console_height=$(tput lines)
    SizeChecker

    echo "Columns: ${console_width}\033[0K"
    echo "Lines: ${console_height}\033[0K"
    echo ""
    echo "Padd_size ${padd_size}\033[0K"

done

# Hint: to resize another terminal (e.g. connected via SSH)
# printf '\e[8;16;30t' > /dev/pts/0
# The device file descriptor can be obtained by `tty``
