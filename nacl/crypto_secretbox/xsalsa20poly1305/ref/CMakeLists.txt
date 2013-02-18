set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_secretbox/xsalsa20poly1305"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_secretbox/xsalsa20poly1305/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_secretbox_xsalsa20poly1305_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_secretbox/xsalsa20poly1305/ref/box.c)
set_target_properties(crypto_secretbox_xsalsa20poly1305_ref PROPERTIES LINKER_LANGUAGE C)
