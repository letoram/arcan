set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_box_curve25519xsalsa20poly1305_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305/ref/keypair.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305/ref/after.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305/ref/box.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_box/curve25519xsalsa20poly1305/ref/before.c)
set_target_properties(crypto_box_curve25519xsalsa20poly1305_ref PROPERTIES LINKER_LANGUAGE C)
