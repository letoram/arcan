This folder only contains quick on-off tests for evaluating
and debugging specific engine features that require user
interaction.

bchunk - (requires fsrv) opening io streams to/from a client
         via the bchunk mechanism.

canvasresize - rest resizing the primary output canvas
               in the response to a button press

clockreq - (requires fsrv) test monotonic, dynamic and user
           requested timers

dpmstest - (low level platform) test setting dpms states on/off

eventtest - draw information text describing incoming input events

failadopt - test adopt handler on script failure

failover - goes with failadopt, one set of scripts that die, another
           that takes over. run failadopt as fallback appl

fonttest - testing format string rendering

imagetest - test image load/store stack pop/push

interp - test different interpolation functions

kbdtest - test keyboard repeat period and repeat delay

ledtest - test connected led controllers

lwarztest - test dynamic resize response (epilepsy warning)
            for lwa instances (need lwa + main)

mdispcl - test multiple displays (map, unmap, ...)

mdispwm - test compositor surface script, deprecated

movietest - test decode frameserver, deprecated

outputs - test some map-display calls

picktest - test mouse/cursor based surface picking

recordtest - test encode frameserver

rtdensity - test rendertarget density switching

rtfmt - test different rendertarget storage formats

scan - test display mode switching and surface mapping

segreq - test subsegment requests and mapping

soundtest - deprecated, test sample and streaming playback

switcher - test appl switching

vidtag - another record testing

vrtest - test mapping limbs to reference geometry

vrtest2 - test hmd setup, distortion pipeline , ...

vrtest3 - extended scratchpad on vrtest2

