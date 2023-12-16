This folder only contains quick on-off tests for evaluating and debugging
specific engine features that require user interaction.

Running some of this natively with arcan as the primary display server
takes some precaution if you don't want to ssh in and kill the instance,
as most of the scripts lack a shutdown mechanism.

To achieve that otherwise, you can use the hookscript, like so:

    arcan -H hook/shutdown.lua appl

arcantarget - tests the arcantarget mechanism for subsegment allocation
              (requires lwa and outer arcan instance)

bchunk - (requires fsrv) opening io streams to/from a client
         via the bchunk mechanism.

blend - goes through different blend states

canvasresize - rest resizing the primary output canvas
               in the response to a button press

clip - tests different clipping hierarchy configurations

clockreq - (requires fsrv) test monotonic, dynamic and user
           requested timers

decortest - testing the builtin surface decorator helper script

dpmstest - (low level platform) test setting dpms states on/off

eventtest - draw information text describing incoming input events

failadopt - test adopt handler on script failure

failover - goes with failadopt, one set of scripts that die, another
           that takes over. run failadopt as fallback appl

fonttest - testing format string rendering

interp - test different interpolation functions

imagetest - test image load/store stack pop/push

itest - two different kinds of externally provided input injection

kbdtest - test keyboard repeat period and repeat delay

ledtest - test connected led controllers

lwarztest - test dynamic resize response (epilepsy warning)
            for lwa instances (need lwa + main)

mdispcl - test multiple displays (map, unmap, ...)

mdispwm - test compositor surface script, deprecated

movietest - test decode frameserver, deprecated

outputs - test some map-display calls

picktest - test mouse/cursor based surface picking

prim3d - single cube, directional lighting, mouse rotation and shifted origo

recordtest - test encode frameserver

rgbswitch - cycles r,g,b colors on a timer and on digital input

rtdensity - test rendertarget density switching

rtfmt - test different rendertarget storage formats

scan - test display mode switching and surface mapping

segreq - test subsegment requests and mapping

soundtest - deprecated, test sample and streaming playback

switcher - test appl switching

touchtest - test touch input

tracetst - using benchmark function to generate chrome friendly system trace

vidtag - another record testing

vrtest - test mapping limbs to reference geometry

vrtest2 - test hmd setup, distortion pipeline , ...

vrtest3 - extended scratchpad on vrtest2

wltest - testing the builtin wayland window manager helper script

xwmroot - rootful Xarcan decomposition test

xwm - redirected Xarcan deferred composition test

nettest - tests sourcing and sinking to/from local passive-beacon discovery
