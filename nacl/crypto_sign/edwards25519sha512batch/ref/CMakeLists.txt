set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_sign_edwards25519sha512batch_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch/ref/fe25519.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch/ref/sign.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch/ref/sc25519.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_sign/edwards25519sha512batch/ref/ge25519.c)
set_target_properties(crypto_sign_edwards25519sha512batch_ref PROPERTIES LINKER_LANGUAGE C)
