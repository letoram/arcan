set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_scalarmult/curve25519"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_scalarmult/curve25519/donna_c64"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_scalarmult_curve25519_donna_c64 /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_scalarmult/curve25519/donna_c64/smult.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_scalarmult/curve25519/donna_c64/base.c)
set_target_properties(crypto_scalarmult_curve25519_donna_c64 PROPERTIES LINKER_LANGUAGE C)
