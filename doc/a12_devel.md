Developing Networked Arcan Applications
=======================================

This (in progress) document covers how to tailor an arcan appl for network use
when it is hosted by an arcan-a12 directory server. It is assumed that you
already know how to write a regular arcan appl.

# Client Side

To initiate a network connection, the `net_open` call is used. This is normally
used to connect to keys in your keystore, or through servers discovered through
`net_discover`. When used like this, it is to source a sink or run an appl
through a directory. This connection behaves like a normal frameserver.

From the perspective of an appl running from a directory server, the reserved
host '@stdin' or (@stdin:myname) is used. This represents the existing connection
to the directory the appl was downloaded from.

    arcan-net @myserver test

    function test()
        directory =
            net_open("test",
                            function(source, status)
                            end
                    )
    end

The 'registered' event is delivered when the connection is active. Other than
that, 'message' {string: message, bool: multipart} event will be received when
someone else using the appl sends a message.

This is done with `message_target`. If the appl has a server side controller
attached, it is responsible for validation and routing. If there is no
controller, the message will be broadcast to all users of the same appl within
the directory network.

Messages should only used for short coordination as there is substantial
framing overhead (MAC + event packet header) and longer messages gets chunked.
There is no source identity attached to the message in the broadcast form, the
only guarantee is that each message(multipart=true), ...
message(multipart=false) chain will be complete and unbroken when received from
the server.

## File transfers

The `open_nonblock` function can be used to send or receive binary streams,
just as it is used with local frameservers. Use the reference from `net_open`
as the first argument:

    local input = open_nonblock(directory, false, "appl:/.index")

See the documentation for `open_nonblock` for details on how to read and write.
What is special for the appl case is that the "." prefix is reserved for special
files, with ".index" used to request a listing of files.

There are two possible namespaces for file store; a private one controlled by
the main directory server process tied to the user authentication key, and the
other by the controller VM. By default an appl does not have access to the
private one. It can be requested in manifest permissions, but the user may also
reject that.

The reason is simply to prevent an appl from scraping the private store and
forwarding it to the one its controller has access to. For certain applications
this is a valid use-case, e.g. a desktop environment application like Durden.

The file names are restricted to short, 59 alphanum (. allowed) characters (64
- 'appl:' - \0) by protocol. It is recommended that the returned .index has a
mapping to longer user presentable text and other indexing metadata.

## Searching

(Being Implemented)
Just like `glob_resource` can be used to find matching files locally, it can
be used to generate a filtered .index based on search critera.

   local nbio = glob\_resource(directory, "files of images of cats")

This is handled by an indexing / search resolver.

## Dynamic sources

Just as the directory server can host interactive 'sources' for a client to
sink, the appl can also access them as part of its code, and they act like any
other frameserver that something like `launch_decode` would.

Public ones either global to the directory or open-to-all created by the
controller are announced via via 'state' events in the normal `net_open` event
handler. These also have the 'source' member of the 'status' table set to true
(it can also be a sink or another directory).

To request to sink such a source, you message the directory with the name of
the source and a '<' prefix. If the request goes through (some sources might be
first come first serve and single use -- another user might have reached it
first) you will receive a `segment_request` event that you could call
`accept_target` on just like a regular shmif client requesting a new window.

    net_open("@stdin",
        function(source, status)
            if status.kind == "state" and status.source then
                message_target(source, "<" .. status.name)

            elseif status.kind == "segment_request" then
                accept_target(source, 0, 0, event_handler)
            end
        end
    )

These can also arrive without any prior request if the controller explicitly
sends something to you. On the server end that would be something like:

    launch_target(some_client_id, "some_target")

## Dynamic sharing

The appl side can also share composed results via `define_recordtarget` and
the use is similar to how one would stream output to another shmif client:

    local surface = alloc_surface(640, 480)
    define_recordtarget(surface, directory, "", {vid1, vid2}, {aid1, aid2},
                        RENDERTARGET_DETACH, RENDERTARGET_NOSCALE,
                        function(source, status)
                         ...
                        end
                       )

This would appear as a new source on the controller event (see 'Server Side'
section. Then it can be routed to another client, including server side
controlled ones for transcoding.

# Server Side

We have indirectly touched upon the controller side a few times through the
examples in the 'Client Side' section. These look and feel quite similar to
a regular appl, including how it's created.

Say we host an appl called 'test' and want to add controller logic to it, and
the config.lua for arcan-net on the hosting machine points
`config.paths.appl_server` to '/home/a12/ctrl'.

    mkdir /home/a12/ctrl/test
    echo "function test()\n    end\n" > /home/a12/ctrl/test

Then restart (or send SIGUSR1) to the arcan-net -c config.lua process and
there is your controller.

Now this one is fairly useless, we need to fill out some entry points to
add our logic. This also looks similar to how an appl is made, you prefix
the reserved name with the name of your appl (here, test) and the software
will invoke as necessary.

The set of entry points are:

 * `_clock_pulse(ticks)` - 25Hz monotonic clock
 * `_message(clid, msg)` -
 * `_join(clid, ident)`  - A client has joined
 * `_leave(clid)`        - A client has disconnected
 * `_index(clid, nbio)`  - Client requests an index of available files
 * `_load(clid, name)`   - Client requests a file or data stream
 * `_store(clid, name)`  - Client wants to send a file or stream data

The set of functions available:

 * `message_target`
 * `store_key`
 * `match_keys`
 * `list_targets`
 * `launch_target`

`open_nonblock`, `launch_decode`, `system_load`, `bond_target`.

Full documentation for the functions are in `doc/ctrl/*.lua` in the arcan
source tree.

# Examples

## File Upload

For the first example, we will look at a simple

   - Click to request from outer desktop

## Sharing a camera

   - Launch Decode
     - define recordtarget

   - Controller side
     - bind source to multiplexer
     - announce to others

## Links and Link Types

# Development Tools

## Dynamic Uploads and Hot-Reload

## Crash Triaging

## File Management

## Debugging

### Cat9 and Debug arcan
