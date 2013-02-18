set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_onetimeauth/poly1305"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_onetimeauth/poly1305/amd64"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_onetimeauth_poly1305_amd64 /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_onetimeauth/poly1305/amd64/auth.s;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_onetimeauth/poly1305/amd64/constants.s;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_onetimeauth/poly1305/amd64/verify.c)
set_target_properties(crypto_onetimeauth_poly1305_amd64 PROPERTIES LINKER_LANGUAGE C)
