/* vim: set et fde fdm=syntax ft=c.doxygen ts=4 sts=4 sw=4 : */
/*
 * Copyright © 2010-2011 Saleem Abdulrasool <compnerd@compnerd.org>.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 * EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
 * OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
 * OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef eds_cea861_h
#define eds_cea861_h

#define CEA861_NO_DTDS_PRESENT                          (0x04)

enum cea861_data_block_type {
    CEA861_DATA_BLOCK_TYPE_RESERVED0,
    CEA861_DATA_BLOCK_TYPE_AUDIO,
    CEA861_DATA_BLOCK_TYPE_VIDEO,
    CEA861_DATA_BLOCK_TYPE_VENDOR_SPECIFIC,
    CEA861_DATA_BLOCK_TYPE_SPEAKER_ALLOCATION,
    CEA861_DATA_BLOCK_TYPE_VESA_DTC,
    CEA861_DATA_BLOCK_TYPE_RESERVED6,
    CEA861_DATA_BLOCK_TYPE_EXTENDED,
};

enum cea861_audio_format {
    CEA861_AUDIO_FORMAT_RESERVED,
    CEA861_AUDIO_FORMAT_LPCM,
    CEA861_AUDIO_FORMAT_AC_3,
    CEA861_AUDIO_FORMAT_MPEG_1,
    CEA861_AUDIO_FORMAT_MP3,
    CEA861_AUDIO_FORMAT_MPEG2,
    CEA861_AUDIO_FORMAT_AAC_LC,
    CEA861_AUDIO_FORMAT_DTS,
    CEA861_AUDIO_FORMAT_ATRAC,
    CEA861_AUDIO_FORMAT_DSD,
    CEA861_AUDIO_FORMAT_E_AC_3,
    CEA861_AUDIO_FORMAT_DTS_HD,
    CEA861_AUDIO_FORMAT_MLP,
    CEA861_AUDIO_FORMAT_DST,
    CEA861_AUDIO_FORMAT_WMA_PRO,
    CEA861_AUDIO_FORMAT_EXTENDED,
};

struct __attribute__ (( packed )) cea861_timing_block {
    /* CEA Extension Header */
    uint8_t  tag;
    uint8_t  revision;
    uint8_t  dtd_offset;

    /* Global Declarations */
    unsigned native_dtds           : 4;
    unsigned yuv_422_supported     : 1;
    unsigned yuv_444_supported     : 1;
    unsigned basic_audio_supported : 1;
    unsigned underscan_supported   : 1;

    uint8_t  data[123];

    uint8_t  checksum;
};

struct __attribute__ (( packed )) cea861_data_block_header {
    unsigned length : 5;
    unsigned tag    : 3;
};

struct __attribute__ (( packed )) cea861_short_video_descriptor {
    unsigned video_identification_code : 7;
    unsigned native                    : 1;
};

struct __attribute__ (( packed )) cea861_video_data_block {
    struct cea861_data_block_header      header;
    struct cea861_short_video_descriptor svd[];
};

struct __attribute__ (( packed )) cea861_short_audio_descriptor {
    unsigned channels              : 3; /* = value + 1 */
    unsigned audio_format          : 4;
    unsigned                       : 1;

    unsigned sample_rate_32_kHz    : 1;
    unsigned sample_rate_44_1_kHz  : 1;
    unsigned sample_rate_48_kHz    : 1;
    unsigned sample_rate_88_2_kHz  : 1;
    unsigned sample_rate_96_kHz    : 1;
    unsigned sample_rate_176_4_kHz : 1;
    unsigned sample_rate_192_kHz   : 1;
    unsigned                       : 1;

    union {
        struct __attribute__ (( packed )) {
            unsigned bitrate_16_bit : 1;
            unsigned bitrate_20_bit : 1;
            unsigned bitrate_24_bit : 1;
            unsigned                : 5;
        } lpcm;

        uint8_t maximum_bit_rate;       /* formats 2-8; = value * 8 kHz */

        uint8_t format_dependent;       /* formats 9-13; */

        struct __attribute__ (( packed )) {
            unsigned profile : 3;
            unsigned         : 5;
        } wma_pro;

        struct __attribute__ (( packed )) {
            unsigned      : 3;
            unsigned code : 5;
        } extension;
    } flags;
};

struct __attribute__ (( packed )) cea861_audio_data_block {
    struct cea861_data_block_header      header;
    struct cea861_short_audio_descriptor sad[];
};

struct __attribute__ (( packed )) cea861_speaker_allocation {
    unsigned front_left_right        : 1;
    unsigned front_lfe               : 1;   /* low frequency effects */
    unsigned front_center            : 1;
    unsigned rear_left_right         : 1;
    unsigned rear_center             : 1;
    unsigned front_left_right_center : 1;
    unsigned rear_left_right_center  : 1;
    unsigned front_left_right_wide   : 1;

    unsigned front_left_right_high   : 1;
    unsigned top_center              : 1;
    unsigned front_center_high       : 1;
    unsigned                         : 5;

    unsigned                         : 8;
};

struct __attribute__ (( packed )) cea861_speaker_allocation_data_block {
    struct cea861_data_block_header  header;
    struct cea861_speaker_allocation payload;
};

struct __attribute__ (( packed )) cea861_vendor_specific_data_block {
    struct cea861_data_block_header  header;
    uint8_t                          ieee_registration[3];
    uint8_t                          data[30];
};

static const struct cea861_timing {
    const uint16_t hactive;
    const uint16_t vactive;
    const enum {
        INTERLACED,
        PROGRESSIVE,
    } mode;
    const uint16_t htotal;
    const uint16_t hblank;
    const uint16_t vtotal;
    const double   vblank;
    const double   hfreq;
    const double   vfreq;
    const double   pixclk;
} cea861_timings[] = {
    [1]  = {  640,  480, PROGRESSIVE,  800,  160,  525, 45.0,  31.469,  59.940,  25.175 },
    [2]  = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0,  31.469,  59.940,  27.000 },
    [3]  = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0,  31.469,  59.940,  27.000 },
    [4]  = { 1280,  720, PROGRESSIVE, 1650,  370,  750, 30.0,  45.000,  60.000,  74.250 },
    [5]  = { 1920, 1080,  INTERLACED, 2200,  280, 1125, 22.5,  33.750,  60.000,  72.250 },
    [6]  = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  15.734,  59.940,  27.000 },
    [7]  = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  15.734,  59.940,  27.000 },
    [8]  = { 1440,  240, PROGRESSIVE, 1716,  276,  262, 22.0,  15.734,  60.054,  27.000 },  /* 9 */
    [9]  = { 1440,  240, PROGRESSIVE, 1716,  276,  262, 22.0,  15.734,  59.826,  27.000 },  /* 8 */
    [10] = { 2880,  480,  INTERLACED, 3432,  552,  525, 22.5,  15.734,  59.940,  54.000 },
    [11] = { 2880,  480,  INTERLACED, 3432,  552,  525, 22.5,  15.734,  59.940,  54.000 },
    [12] = { 2880,  240, PROGRESSIVE, 3432,  552,  262, 22.0,  15.734,  60.054,  54.000 },  /* 13 */
    [13] = { 2880,  240, PROGRESSIVE, 3432,  552,  262, 22.0,  15.734,  59.826,  54.000 },  /* 12 */
    [14] = { 1440,  480, PROGRESSIVE, 1716,  276,  525, 45.0,  31.469,  59.940,  54.000 },
    [15] = { 1440,  480, PROGRESSIVE, 1716,  276,  525, 45.0,  31.469,  59.940,  54.000 },
    [16] = { 1920, 1080, PROGRESSIVE, 2200,  280, 1125, 45.0,  67.500,  60.000, 148.500 },
    [17] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0,  31.250,  50.000,  27.000 },
    [18] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0,  31.250,  50.000,  27.000 },
    [19] = { 1280,  720, PROGRESSIVE, 1980,  700,  750, 30.0,  37.500,  50.000,  74.250 },
    [20] = { 1920, 1080,  INTERLACED, 2640,  720, 1125, 22.5,  28.125,  50.000,  74.250 },
    [21] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  15.625,  50.000,  27.000 },
    [22] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  15.625,  50.000,  27.000 },
    [23] = { 1440,  288, PROGRESSIVE, 1728,  288,  312, 24.0,  15.625,  50.080,  27.000 },  /* 24 */
    [24] = { 1440,  288, PROGRESSIVE, 1728,  288,  313, 25.0,  15.625,  49.920,  27.000 },  /* 23 */
 // [24] = { 1440,  288, PROGRESSIVE, 1728,  288,  314, 26.0,  15.625,  49.761,  27.000 },
    [25] = { 2880,  576,  INTERLACED, 3456,  576,  625, 24.5,  15.625,  50.000,  54.000 },
    [26] = { 2880,  576,  INTERLACED, 3456,  576,  625, 24.5,  15.625,  50.000,  54.000 },
    [27] = { 2880,  288, PROGRESSIVE, 3456,  576,  312, 24.0,  15.625,  50.080,  54.000 },  /* 28 */
    [28] = { 2880,  288, PROGRESSIVE, 3456,  576,  313, 25.0,  15.625,  49.920,  54.000 },  /* 27 */
 // [28] = { 2880,  288, PROGRESSIVE, 3456,  576,  314, 26.0,  15.625,  49.761,  54.000 },
    [29] = { 1440,  576, PROGRESSIVE, 1728,  288,  625, 49.0,  31.250,  50.000,  54.000 },
    [30] = { 1440,  576, PROGRESSIVE, 1728,  288,  625, 49.0,  31.250,  50.000,  54.000 },
    [31] = { 1920, 1080, PROGRESSIVE, 2640,  720, 1125, 45.0,  56.250,  50.000, 148.500 },
    [32] = { 1920, 1080, PROGRESSIVE, 2750,  830, 1125, 45.0,  27.000,  24.000,  74.250 },
    [33] = { 1920, 1080, PROGRESSIVE, 2640,  720, 1125, 45.0,  28.125,  25.000,  74.250 },
    [34] = { 1920, 1080, PROGRESSIVE, 2200,  280, 1125, 45.0,  33.750,  30.000,  74.250 },
    [35] = { 2880,  480, PROGRESSIVE, 3432,  552,  525, 45.0,  31.469,  59.940, 108.500 },
    [36] = { 2880,  480, PROGRESSIVE, 3432,  552,  525, 45.0,  31.469,  59.940, 108.500 },
    [37] = { 2880,  576, PROGRESSIVE, 3456,  576,  625, 49.0,  31.250,  50.000, 108.000 },
    [38] = { 2880,  576, PROGRESSIVE, 3456,  576,  625, 49.0,  31.250,  50.000, 108.000 },
    [39] = { 1920, 1080,  INTERLACED, 2304,  384, 1250, 85.0,  31.250,  50.000,  72.000 },
    [40] = { 1920, 1080,  INTERLACED, 2640,  720, 1125, 22.5,  56.250, 100.000, 148.500 },
    [41] = { 1280,  720, PROGRESSIVE, 1980,  700,  750, 30.0,  75.000, 100.000, 148.500 },
    [42] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0,  62.500, 100.000,  54.000 },
    [43] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0,  62.500, 100.000,  54.000 },
    [44] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  31.250, 100.000,  54.000 },
    [45] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  31.250, 100.000,  54.000 },
    [46] = { 1920, 1080,  INTERLACED, 2200,  280, 1125, 22.5,  67.500, 120.000, 148.500 },
    [47] = { 1280,  720, PROGRESSIVE, 1650,  370,  750, 30.0,  90.000, 120.000, 148.500 },
    [48] = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0,  62.937, 119.880,  54.000 },
    [49] = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0,  62.937, 119.880,  54.000 },
    [50] = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  31.469, 119.880,  54.000 },
    [51] = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  31.469, 119.880,  54.000 },
    [52] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0, 125.000, 200.000, 108.000 },
    [53] = {  720,  576, PROGRESSIVE,  864,  144,  625, 49.0, 125.000, 200.000, 108.000 },
    [54] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  62.500, 200.000, 108.000 },
    [55] = { 1440,  576,  INTERLACED, 1728,  288,  625, 24.5,  62.500, 200.000, 108.000 },
    [56] = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0, 125.874, 239.760, 108.000 },
    [57] = {  720,  480, PROGRESSIVE,  858,  138,  525, 45.0, 125.874, 239.760, 108.000 },
    [58] = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  62.937, 239.760, 108.000 },
    [59] = { 1440,  480,  INTERLACED, 1716,  276,  525, 22.5,  62.937, 239.760, 108.000 },
    [60] = { 1280,  720, PROGRESSIVE, 3300, 2020,  750, 30.0,  18.000,  24.000,  59.400 },
    [61] = { 1280,  720, PROGRESSIVE, 3960, 2680,  750, 30.0,  18.750,  25.000,  74.250 },
    [62] = { 1280,  720, PROGRESSIVE, 3300, 2020,  750, 30.0,  22.500,  30.000,  74.250 },
    [63] = { 1920, 1080, PROGRESSIVE, 2200,  280, 1125, 45.0, 135.000, 120.000, 297.000 },
    [64] = { 1920, 1080, PROGRESSIVE, 2640,  720, 1125, 45.0, 112.500, 100.000, 297.000 },
};

#endif

