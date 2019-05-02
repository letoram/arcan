/* Suppress the warnings for this include, since we don't care about them for external dependencies
 * Requires at least GCC 4.6 or higher
*/
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wstrict-aliasing"
#pragma GCC diagnostic ignored "-Wswitch"
#pragma GCC diagnostic ignored "-Wimplicit-function-declaration"
#pragma GCC diagnostic ignored "-Wmisleading-indentation"
#include "../ext_deps/miniz.c"
#pragma GCC diagnostic pop
