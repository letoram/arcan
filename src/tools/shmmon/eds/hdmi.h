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

#ifndef eds_hdmi_h
#define eds_hdmi_h

#include "cea861.h"

/*! \todo figure out a better way to determine the offsets */
#define HDMI_VSDB_EXTENSION_FLAGS_OFFSET        (0x06)
#define HDMI_VSDB_MAX_TMDS_OFFSET               (0x07)
#define HDMI_VSDB_LATENCY_FIELDS_OFFSET         (0x08)

static const uint8_t HDMI_OUI[]                 = { 0x00, 0x0C, 0x03 };

struct __attribute__ (( packed )) hdmi_vendor_specific_data_block {
    struct cea861_data_block_header header;

    uint8_t  ieee_registration_id[3];           /* LSB */

    unsigned port_configuration_b      : 4;
    unsigned port_configuration_a      : 4;
    unsigned port_configuration_d      : 4;
    unsigned port_configuration_c      : 4;

    /* extension fields */
    unsigned dvi_dual_link             : 1;
    unsigned                           : 2;
    unsigned yuv_444_supported         : 1;
    unsigned colour_depth_30_bit       : 1;
    unsigned colour_depth_36_bit       : 1;
    unsigned colour_depth_48_bit       : 1;
    unsigned audio_info_frame          : 1;

    uint8_t  max_tmds_clock;                    /* = value * 5 */

    unsigned                           : 6;
    unsigned interlaced_latency_fields : 1;
    unsigned latency_fields            : 1;

    uint8_t  video_latency;                     /* = (value - 1) * 2 */
    uint8_t  audio_latency;                     /* = (value - 1) * 2 */
    uint8_t  interlaced_video_latency;
    uint8_t  interlaced_audio_latency;

    uint8_t  reserved[];
};

#endif

