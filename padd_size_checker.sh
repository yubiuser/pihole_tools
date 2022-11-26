#!/usr/bin/env sh

SizeChecker(){
    console_height=$(stty size | awk '{ print $1 }')
    console_width=$(stty size | awk '{ print $2 }')

    # Mega
    if [ "$console_width" -ge "80" ] && [ "$console_height" -ge "26" ]; then
        padd_size="mega"
        width=80
        height=26
    # Below Mega. Gives you Regular.
    elif [ "$console_width" -ge "60" ] && [ "$console_height" -ge "22" ]; then
        padd_size="regular"
        width=60
        height=22
    # Below Regular. Gives you Slim.
    elif [ "$console_width" -ge "60" ] && [ "$console_height" -ge "21" ]; then
        padd_size="slim"
        width=60
        height=21
    # Below Slim. Gives you Tiny.
    elif [ "$console_width" -ge "53" ] && [ "$console_height" -ge "20" ]; then
        padd_size="tiny"
        width=53
        height=20
    # Below Tiny. Gives you Mini.
    elif [ "$console_width" -ge "40" ] && [ "$console_height" -ge "18" ]; then
        padd_size="mini"
        width=40
        height=18
    # Below Mini. Gives you Micro.
    elif [ "$console_width" -ge "30" ] && [ "$console_height" -ge "16" ]; then
        padd_size="micro"
        width=30
        height=16
    # Below Micro, Gives you Nano.
    elif [ "$console_width" -ge "24" ] && [ "$console_height" -ge "12" ]; then
        padd_size="nano"
        width=24
        height=12
    # Below Nano. Gives you Pico.
    elif [ "$console_width" -ge "20" ] && [ "$console_height" -ge "10" ]; then
        padd_size="pico"
        width=20
        height=10
    # Below Pico. Gives you nothing...
    else
        # Nothing is this small, sorry
        padd_size="ant"
        width=0
        height=0
    fi
}

GenerateOutput() {
    # Clear the screen and move cursor to (0,0).
    # This mimics the 'clear' command.
    # https://vt100.net/docs/vt510-rm/ED.html
    # https://vt100.net/docs/vt510-rm/CUP.html
    # E3 extension `\e[3J` to clear the scrollback buffer (see 'man clear')

    printf '\e[H\e[2J\e[3J'

    # draw the PADD field
    row=1
    column=1
    while [ "$row" -le ${height} ]
    do
        while [ "$column" -le ${width} ]
        do
            if [ "$row" = 1 ] || [ "$row" = "${height}" ] || [ "$column" = 1 ] || [ "$column" = "${width}" ]; then
                printf "*"
            else
                printf " "
            fi
            column=$((column+1))
        done
        # don't add a new line below the PADD field
        if [ "$row" -lt "${height}" ]; then
            echo
        fi
        column=1
        row=$((row+1))
    done

    # draw info within the PADD field
    tput cup 2 2; printf "Console width: %s" "${console_width}"
    tput cup 3 2; printf "Console height: %s" "${console_height}"
    tput cup 4 2; printf "PADD width: %s" "${width}"
    tput cup 5 2; printf "PADD height: %s" "${height}"
    tput cup 6 2; printf "PADD size: %s" "${padd_size}"

    # move the cursor to the lower rigth corner
    tput cup $((height-1)) $((width-2))
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
    kill "${sleepPID}" > /dev/null 2>&1

    exit $err # exit the script with saved $?
}

TerminalResize(){
    # if a terminal resize is trapped, kill the sleep function within the
    # loop to trigger SizeChecker

    kill "${sleepPID}" > /dev/null 2>&1
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
