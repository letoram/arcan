function(AbiName_get outputVar)
    try_compile(compileResult
        ${CMAKE_BINARY_DIR}/okcompilers/
        ${CMAKE_SOURCE_DIR}/okcompilers/abiname_xcompile.c
        OUTPUT_VARIABLE compileOut
    )
    string(REGEX MATCH "ABI_IS_[^_]*__" abi "${compileOut}")
    string(REGEX REPLACE "ABI_IS_([^_]*)__" "\\1" abi "${abi}")
    set(${outputVar} ${abi} PARENT_SCOPE)
endfunction()
