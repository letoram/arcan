set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_auth/hmacsha512256"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_auth/hmacsha512256/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_auth_hmacsha512256_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_auth/hmacsha512256/ref/hmac.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_auth/hmacsha512256/ref/verify.c)
set_target_properties(crypto_auth_hmacsha512256_ref PROPERTIES LINKER_LANGUAGE C)
