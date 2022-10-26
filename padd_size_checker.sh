#!/usr/bin/env sh

SizeChecker(){
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

GenerateOutput() {
    # Clear the screen and move cursor to (0,0).
    # This mimics the 'clear' command.
    # https://vt100.net/docs/vt510-rm/ED.html
    # https://vt100.net/docs/vt510-rm/CUP.html
    # E3 extension `\e[3J` to clear the scrollback buffer (see 'man clear')

    printf '\e[H\e[2J\e[3J'


    echo "Columns: ${console_width}\033[0K"
    echo "Lines: ${console_height}\033[0K"
    echo ""
    echo "Padd_size ${padd_size}\033[0K"
}

CleanExit(){
    # save the return code of the script
    err=$?
    #clear the line
    printf '\e[0K\n'

    # Show the cursor
    # https://vt100.net/docs/vt510-rm/DECTCEM.html
    printf '\e[?25h'

    # if background sleep is running, kill it
    # http://mywiki.wooledge.org/SignalTrap#When_is_the_signal_handled.3F
    kill $sleepPID > /dev/null 2>&1

    exit $err # exit the script with saved $?
}

TerminalResize(){
    # if a terminal resize is trapped, kill the sleep function within the
    # loop to trigger SizeChecker

    kill $sleepPID > /dev/null 2>&1
}

######### MAIN #########

# Hide the cursor.
# https://vt100.net/docs/vt510-rm/DECTCEM.html
printf '\e[?25l'

# Trap on exit
trap 'CleanExit' INT TERM EXIT

# Trap the window resize signal (handle window resize events)
trap 'TerminalResize' WINCH

while :; do

    SizeChecker
    GenerateOutput

    # Sleep infinity
    # sending sleep in the background and wait for it
    # this way the TerminalResize trap can kill the sleep
    # and force a instant re-draw of the dashboard
    # https://stackoverflow.com/questions/32041674/linux-how-to-kill-sleep
    #
    # saving the PID of the background sleep process to kill it on exit and resize
    sleep infinity &
    sleepPID=$!
    wait $!

    # when the sleep is killed by the trap, a new round starts

done

# Hint: to resize another terminal (e.g. connected via SSH)
# printf '\e[8;16;30t' > /dev/pts/0
# The device file descriptor can be obtained by `tty``
