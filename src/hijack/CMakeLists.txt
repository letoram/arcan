# Expects:
# arcan_shmif (target)
# FSRV_ROOT (defined in frameservers/CMakeLists.txt)
#
set(HIJACK_LIBSTRING "")
add_subdirectory(sdl12)
#add_subdirectory(x)
amsg("${CL_YEL}hijack   \t${CL_GRN}${HIJACK_LIBSTRING}${CL_RST}")
