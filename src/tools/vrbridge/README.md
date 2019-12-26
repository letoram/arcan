# About

The VR- bridge act as a driver layer to aggregate VR- related devices and
repacking their output and control to integrate well with the main arcan
engine. It uses the privileged 'VR' SHMIF substructure and the process is
spawned by arcan explicitly through the scripting layer (see vr\_setup).

It is kept as a separate process to offload and protect the main engine from
the many possible instabilities, licensing issues, API variations and so- on
that comes with an area that is so aggressively 'in flux' and in conflict with
device manufacturers with an inherently open-source unfriendly bias.

# Building / Testing

Build like normal, e.g.

    cmake ../ ; make

Set as vrbridge application:

    arcan_db add_appl_kv arcan ext_vr /absolute/path/to/build/vrbridge

Or install into the normal /usr/local/bin or /usr/bin (linux/BSD). You can
run the arcan\_vr tool directly from the command-line, and it will enter a
debug- mode where some of the HMD sample outputs will be written. Use this
to verify permissions and device access / support before using it in arcan.

## OpenHMD

The main dependency for input device support is via OpenHMD. The default build
uses a manually maintained in-source build. To use OpenHMD as a normal library
dependency, cmake with:

    cmake -DNO_BUILTIN_OPENHMD ../ ; make

This version also pulls in madgwicks AHRS implementation as an alternate way
of doing sensor-fusion / filtering. Enable with -DMAGWICK\_AHRS

# Model

The VR substructure in SHMIF covers a small synchronization/metadata structure
(allocation, dirty\_in, dirty\_out, display parameters) and an array of (up to
64) 'limbs' that are containers for sanitized/filtered position, sensor
information and metadata. The metadata covers things like timestamps, accuracy,
and a checksum. The checksum is validated whenever the engine-side synchs the
position information with the container object on the other side. In arcan
parlerance, limbs are mapped to normal vids and will override the respective
positional information.

On launch, the VR bridge scans for available devices, and it is on a per/device
per/driver basis that limbs can be requested to be allocated. It is then up to
the running appl- scripts to define VIDs that these limbs should map to,
configure 3d- model mapping and so on.

# Open-Ended Questions

Many HMD devices come with video feed as well, often through built-in cameras.
Though we can add support for subsegments as normal decode feeds without much
problem, maybe it makes more sense to just let the normal decode frameserver
provide access to these through normal v4l means and keep visual processing
and analysis on the appl- level in order to avoid giving the VR bridge direct
GPU or CUDA/OpenCL access.

Another problem is the part on how distortion is supposed to be applied. There
is some paths prepared for allowing the device driver to provide a fitting
distortion model, but it might not be needed/useful/better than simply having
a parameter to mesh generation support script and use that.

Then we have the situation with multiple positional systems as part of
aggregated devices that all provide the same 'limb' and how to work with
such edge cases, some priority system or preferences in precision vs. latency?

Another point of conflict is coordinate spaces, where limbs are treated in an
'avatar' space and possible metadata to map to a room-space. This becomes more
problematic when we have inside- out tracking, AR- like spaces and so on.

# Todo

There are a number of VR SDKs that we should map and add support for, though
some restraint is probably best until we see something concrete from OpenXR.

- [p] OpenHMD support
  - [x] metadata
  - [x] head tracking
  - [ ] misc. events (buttons, ...)
- [ ] Arbitrary
- [ ] Special Cameras to shmif segments
- [ ] Adafruit 9-DOF BNO055 to arbitrary limb

# Experiments

Find a way to modify/fault-inject various degrees of broken sensors and try to
compensate and filter out "impossible" motion through something like ragdoll/
human-modelled IK as a predictive model for a kalman filter.
