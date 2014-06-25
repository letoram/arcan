/*
 * Arcan Package Format [APF]
 * These are just rough sketches of the planned format/feature, nothing to see
 * here yet, really.
 *
 * Key points
 *  - Separation between code, data and meta
 *    Each package is split into independently versioned segments,
 *    with the local package tool maintaining a manifest which
 *    contains pointers to the active version of each segment type.
 *
 *    The governing principle is that binaries, libraries and scripts
 *    are present in code segments (with a header that flags if we need
 *    binaries / libraries support or if it's a strict arcan- app).
 *    Local device policy may filter on this flag (and block exec() style calls).
 *
 *    while we cannot protect against a developer creating a binary encoding,
 *    putting it into data and have the code-block load and execute a data segment,
 *    the point is to encourage this split in updates and in local configuration;
 *    artists and similar content creators should not necessarily be able to sign
 *    or update code.
 *
 *    Meta segments should rarely, if ever, be updated and contains the public
 *    keys used to verify the active segments along with contact information.
 *    It is the contents of this segment that the user has to go on to verify
 *    the identity of the package and there's no CA- style hierarchy in place for
 *    the first installation. It can also be used to blacklist certain versions
 *    and let the project recover from corrupted segments coming from a compromised
 *    set of keys. Therefore, the Meta- key should be kept offline. There's a
 *    limited amount of meta updates allowed, think of it as a finite resource
 *    that costs user trust every time it is used.
 *
 *  - Rollback to earlier versions
 *    When applying an update, it is appended to the existing package, rather
 *    than as a diff to easily allow rollbacks, compactions, invalidations etc.
 *    The namespace is consolidated for all previous versions and a collision
 *    is resolved to the advantage of a new update. A consequence of this is that
 *    an entry cannot be removed, only shadowed. It should be possible for a user
 *    to obtain a base-package from a trusted source, and apply updates from
 *    untrusted sources.
 *
 *  - FUSE- driver friendly & Resource Map
 *    Part of the idea is to have a chain-loader create a userspace mount
 *    in a fuse- based sandbox to which we chroot in order to intercept
 *    system calls (along with other possible local features e.g. seccomp
 *    and capsicum). Certain paths in the namespace works as links to resources
 *    that follows the "everything is a file"- adage. The desired such resources
 *    are specified in a map that's part of the data segment. The format does
 *    not define any ontology for this map as such, it's left to the specific
 *    system arcan is used as a component in.
 *
 *  - No compression!
 *    Domain-specific compression in individual data formats is, of course,
 *    encouraged (e.g. texture compression), but the whole "lets wrap things
 *    in a zip" thing need to stop. Have a compression capable communication
 *    or storage channel if storage size are important and re-use the tried
 *    and true .tar.gz style of chaining compression formats.
 *    The additional headache of dealing with unpacking in memory,
 *    not being able to map resources unless they're stored uncompressed,
 *    expansion attacks, risk of namespace collision problems (see Android+APK)
 *    and so on is not worth the effort.
 *
 * Internal Structural Details
 *
 *   [Data Block]
 *    - Full entries limited to 4k (path + name) djb+sha+relativeofs+length+data
 *
 *    - Resource map has a domainid to distinguish between different app
 *      environments (private, system, user, ...) Can be used to define
 *      system- level resource partitioning.
 *
 *    - Flat namespace, shared between data and resource map,
 *      sha-512 hash for data. djbhash for path lookup. Collisions
 *      are marked as a verification failure / broken package.
 *
 *   Idea to explores:
 *   mapping / installation, use something akin to GNU gperf to generate 
 *   minimal perfect hash tables for namespace lookups.
 */
#ifndef HAVE_ARCAN_APF
#define HAVE_ARCAN_APF

enum apf_verifymode {
/*
 * Disable all verfication (on map and fetch, modifications always verify)
 * Should only be used for trusted/local cache (R/O mapped partition etc.)
 */
	VERIFY_NONE,

/*
 * Check signature on segment headers, the entry log and path:hash map
 * but don't verify data blocks.
 */
	VERIFY_PARTIAL,

/*
 * Check signature on segment headers, check sha-512 sum for data blocks.
 */
	VERIFY_FULL
};

/*
 * Should be defined in the build system, may be different for chainloading
 * (e.g. arcan_lwa), embedding (arcan[_lwa) + apf-file in ELF) and for
 * system level (static linked, R/O mounted source)
 */
#ifndef ARCAN_APF_ALWAYSVERIFY
#define ARCAN_APF_ALWAYSVERIFY VERIFY_PARTIAL
#endif

static const enum apf_verifymode apf_verification_mode = ARCAN_APF_ALWAYSVERIFY;

/*
 * This can be set to "./" or an absolute path or something else,
 * but it's a build-system integration property
 */
#ifndef ARCAN_APF_MANIFESTPATH
unsigned char unspecified_manifestpath_define_ARCAN_APF_MANIFESTPATH[-1];
#else
static const char* apf_manifest_path = ARCAN_APF_MANIFESTPATH;
#endif

/*
 * These structures are not a serialization format,
 * use the appropriate apf_package_*** bound functions for
 * that purpose. Look in the apf.c source for the actual storage
 * format.
 */
struct apf_package_header
{
	unsigned char ident[4]; /* _APF */
	unsigned char group[9]; /* shared, static namespace, a-Z0-9_- */
	unsigned char org[9];   /* allocatable namespace, a-Z0-9_-    */
	unsigned char name[9];  /* allocatable namespace, a->Z0-9_-   */

	char reserved[32];
};

struct apf_package_user
{
/* load_resource (fallback),
 * map_package (),
 *
 * apply_update(char* src, size_t nb, _Bool forward)
 * apply_update_stream(FILE*)
 *
 * extract_version(FILE*, int code, int data, int msg)
 * index_version(FILE*)
 *
 * Manifest- related.
 * rollback(int code, int data, int msg)
 *
 */
	char reserved[64];
};

struct apf_package_admin
{
	/* add_to_data
	 * add_to_code
	 * set_message_description
	 * set_message_uri
	 * add_to_message_resource_map
	 * remove_from_message_resource_map
	 * finalize
	 */
};

/*
 * generate the public/private keys,
 * set up an admin struct that can be used to populate,
 * package and release.
 */
struct apf_package_admin apf_create_empty_package(
	const char* group, const char* org, const char* name);

struct apf_package_user apf_open_package(FILE* source);
struct apf_package_admin apf_manage_package(FILE* source,
	const unsigned char* message_key,
	const unsigned char* data_key,
	const unsigned char* code_key);
#endif
