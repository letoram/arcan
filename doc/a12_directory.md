A12-Directory
=============

This document is an (in progress) guide on how to use the 'directory server'
part of the arcan-net tool. The directory server is an extension to the
[A12](a12.md) protocol that provides:

 * Discovery, Rendezvous and Tunneling for A12 sources and sinks.
 * State and file hosting.
 * Messaging and data processing.
 * Running and hosting Arcan-SHMIF compatible clients.

It can act as a single hosted server, or as a dynamic mesh of servers for load
distribution and forming links for letting users of resources of one server
mesh find and access other ones.

Setup
=====

The 'arcan-net' command-line tool has a number of different uses, but this document will
only cover those related to the directory mode specifically.

You can start a server simply by saying `arcan-net -c /path/to/config.lua`, and the
config.lua.example file in (default installation path /usr/local/share/arcan/config.lua.example)
act as a template for that. The basic configuration is static and safe.

When the server first executes the config.lua it runs the init() function which defines
permissions and available features. Some of the permissions can be changed during runtime
for advanced use, see the 'Administration' section for that.

Most of the values are covered by the comments in the example script, the most important
ones for first use are the fields in the 'config.paths' table. These are as follows:

    config.paths.appl = '/home/a12/appl'

This sets the folder where downloadable client side arcan applications can be
found. See the Arcan developer guide for how those work, or provide one from
our reference set (durden, pipeworld, safespaces), if desired.

    config.paths.appl_server = '/home/a12/appl-ctrl'

This sets the folder where server-side processing and message routing scripts
tied to each hostable appl can be found. There doesn't have to be a matching
controller for each appl, as they revert to broadcast messaging between users
(if needed).

    config.paths.keystore = '/home/a12/state'

This sets the directory tree that will be used for the default 'naive' keystore
and user state (see Administration). It expects it to contain subdirectories
for 'accepted', 'hostkeys', 'state' and 'signing.

Accepted contains the public keys that the server trusts, and a set of , separated
tags that define which permissions the owner of that key will have.

Hostkeys are used for private keys that the server use to make outbound
connections, and a 'default' it will use for replies to inbound connections.

Signing keys are only used by clients making outbound connections, and enables
signatures for uploaded state, indexes and appls.

The 'default' key will be created automatically on first use.

'State' creates a subdirectory for an 'accepted' key when the owner first connects
and authenticates. It acts as a private file store for state and other files.

    config.paths.database = '/home/a12/myserver.sqlite'

Points to a sqlite database (which can be modified with the `arcan_db` tool)
that the config script can use for storing custom information, and each appl
controller can use for storing state.

Administration
==============

# Tags, Users and Keys
# Permissions
# Defining permitted launch targets
# Autostart
# Remote configuration
# Backup

Hosting (sourcing) an Application
=================================

Acessing (sinking) a source
===========================

Configuration Scripting
=======================

 `link_directory`, `launch_target`, `match_keys`, `store_key`, `get_key`.

globals: autostart

entry-points: init, new_source, register_unknown, unregister, register, ready

metatable: dircl :write, :endpoint

Linking Directories
===================

This feature is in active development and subject to change. A directory server
can be linked to in two ways - unified and referential.

A unified link has the directory act as part of a larger, flat, namespace. It
allows multiple servers to share the load of hosting sources, sinks, serving
files and running appl controllers.

In the 'ready' handler of your config.lua:

    function ready()
        link_directory("myserver",
            function(source, status)
            end
        )
    end

If there is a 'myserver' tag associated key in the keystore, a new link process
will be spawned and create an outbound connection to that server. For this to
work, the server 'myserver' tag references need to have the user tag in the
config.permissions.dir string.

A referential link works much the same, but you use the `reference_directory`
function to initiate the link instead. This will make the linked directory
appear in the dynamic list of available sources and the client can open it like
any other, either tunneled through the directory referencing it, or negotiate
connection primitives (host, keys, ...).

Architecture
============

This section covers the high level architecture of the server itself, to assist
with development and troubleshooting.
