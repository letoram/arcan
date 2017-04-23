Leddec is a simple PoC for an external FIFO based LED controller.

To enable, simply create a FIFO (global namespace), e.g.
mkfifo /tmp/led

and then set the corresponding key:
arcan\_db add\_appl\_kv arcan ext\_led /tmp/led

Run leddec /tmp/led and then arcan with some appl that uses the led
functionality. If ARCAN\_CONNPATH environment is set, the tool will
first try to connect via that point, and draw draw the state of the
simulated LEDs back to the buffer as a means of testing the appl to
led-fifo path.
