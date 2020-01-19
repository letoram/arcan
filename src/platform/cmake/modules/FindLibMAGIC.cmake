find_library(MAGIC_LIBRARIES
	NAMES	libmagic.so
	PATHS
	/usr/local/lib
	/usr/lib
)
IF( MAGIC_LIBRARIES )
	SET( MAGIC_FOUND TRUE )
ENDIF( MAGIC_LIBRARIES )
