project(openhmd C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(HMD_SOURCES
	openhmd.c
	omath.c
	platform-posix.c
	fusion_madgwick.c
	shaders.c
	drv_oculus_rift/rift.c
	drv_oculus_rift/packet.c
	drv_oculus_rift/rift-hmd-radio.c
	drv_deepoon/deepoon.c
	drv_deepoon/packet.c
	drv_wmr/wmr.c
	drv_wmr/packet.c
	drv_psvr/psvr.c
	drv_psvr/packet.c
	drv_htc_vive/vive.c
	drv_htc_vive/packet.c
	drv_vrtek/vrtek.c
	drv_vrtek/packet.c
	drv_nolo/nolo.c
	drv_nolo/packet.c
	drv_3glasses/xgvr.c
	drv_3glasses/packet.c
	ext_deps/nxjson.c
)

if (MADGWICK_AHRS)
	list(APPEND HMD_SOURCES ../ahrs.c)
	list(APPEND HMD_SOURCES fusion_madgwick.c)
else()
	list(APPEND HMD_SOURCES fusion.c)
endif()

add_library(openhmd STATIC ${HMD_SOURCES})
target_include_directories(openhmd PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/../../../../external/hidapi)

target_compile_definitions(openhmd PRIVATE
	-DDRIVER_OCULUS_RIFT
	-DDRIVER_DEEPON
	-DDRIVER_WMR
	-DDRIVER_PSVR
	-DDRIVER_VRTEK
	-DDRIVER_HTC_VIVE
	-DDRIVER_NOLO
	-DDRIVER_XGVR
	-DOHMD_STATIC
)
