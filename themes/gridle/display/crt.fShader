/*
    cgwg's CRT shader

    Copyright (C) 2010-2011 cgwg, Themaister

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.

    (cgwg gave their consent to have their code distributed under the GPL in
    this message:

        http://board.byuu.org/viewtopic.php?p=26075#p26075

        "Feel free to distribute my shaders under the GPL. After all, the
        barrel distortion code was taken from the Curvature shader, which is
        under the GPL."
    )
*/

#version 120

// Macros.
#define FIX(c) max(abs(c), 1e-5);
#define PI 3.141592653589
 
#ifdef LINEAR_PROCESSING
#       define TEX2D(c) pow(texture2D(map_diffuse, (c)), vec4(CRTgamma))
#else
#       define TEX2D(c) texture2D(map_diffuse, (c))
#endif
 
uniform sampler2D map_diffuse;
uniform vec2 input_size;
uniform vec2 storage_size;
uniform float obj_opacity;
uniform float curv_radius;
uniform float distance;
uniform float monitorgamma;
uniform float cornersize;
uniform float cornersmooth;

uniform vec2 overscan;
uniform vec2 aspect;
uniform float CRTgamma;
 
varying vec2 texCoord;
varying vec2 one;
varying float mod_factor;

varying vec3 stretch;
varying vec2 sinangle;
varying vec2 cosangle;
 
float intersect(vec2 xy)
{
  float A = dot(xy,xy)+distance*distance;
  float B = 2.0*(curv_radius*(dot(xy,sinangle)-distance*cosangle.x*cosangle.y)-distance*distance);
  float C = distance*distance + 2.0*curv_radius*distance*cosangle.x*cosangle.y;
  return (-B-sqrt(B*B-4.0*A*C))/(2.0*A);
}
 
vec2 bkwtrans(vec2 xy)
{
  float c = intersect(xy);
  vec2 point = vec2(c)*xy;
  point -= vec2(-curv_radius)*sinangle;
  point /= vec2(curv_radius);
  vec2 tang = sinangle/cosangle;
  vec2 poc = point/cosangle;
  float A = dot(tang,tang)+1.0;
  float B = -2.0*dot(poc,tang);
  float C = dot(poc,poc)-1.0;
  float a = (-B+sqrt(B*B-4.0*A*C))/(2.0*A);
  vec2 uv = (point-a*sinangle)/cosangle;
  float r = FIX(curv_radius*acos(a));
  return uv*r/sin(r/curv_radius);
}
 
vec2 transform(vec2 coord)
{
  coord *= storage_size / input_size;
  coord = (coord-vec2(0.5))*aspect*stretch.z+stretch.xy;
  return (bkwtrans(coord)/overscan/aspect+vec2(0.5)) * input_size / storage_size;
}
 
float corner(vec2 coord)
{
  coord *= storage_size / input_size;
  coord = (coord - vec2(0.5)) * overscan + vec2(0.5);
  coord = min(coord, vec2(1.0)-coord) * aspect;
  vec2 cdist = vec2(cornersize);
  coord = (cdist - min(coord,cdist));
  float dist = sqrt(dot(coord,coord));
  return clamp((cdist.x-dist)*cornersmooth,0.0, 1.0);
}
 
// Calculate the influence of a scanline on the current pixel.
//
// 'distance' is the distance in texture coordinates from the current
// pixel to the scanline in question.
// 'color' is the colour of the scanline at the horizontal location of
// the current pixel.
vec4 scanlineWeights(float distance, vec4 color)
{
  // "wid" controls the width of the scanline beam, for each RGB channel
  // The "weights" lines basically specify the formula that gives
  // you the profile of the beam, i.e. the intensity as
  // a function of distance from the vertical center of the
  // scanline. In this case, it is gaussian if width=2, and
  // becomes nongaussian for larger widths. Ideally this should
  // be normalized so that the integral across the beam is
  // independent of its width. That is, for a narrower beam
  // "weights" should have a higher peak at the center of the
  // scanline than for a wider beam.
#ifdef USEGAUSSIAN
  vec4 wid = 0.3 + 0.1 * pow(color, vec4(3.0));
  vec4 weights = vec4(distance / wid);
  return 0.4 * exp(-weights * weights) / wid;
#else
  vec4 wid = 2.0 + 2.0 * pow(color, vec4(4.0));
  vec4 weights = vec4(distance / 0.3);
  return 1.4 * exp(-pow(weights * inversesqrt(0.5 * wid), wid)) / (0.6 + 0.2 * wid);
#endif
}
 
void main()
{
  // Here's a helpful diagram to keep in mind while trying to
  // understand the code:
  //
  //  |      |      |      |      |
  // -------------------------------
  //  |      |      |      |      |
  //  |  01  |  11  |  21  |  31  | <-- current scanline
  //  |      | @    |      |      |
  // -------------------------------
  //  |      |      |      |      |
  //  |  02  |  12  |  22  |  32  | <-- next scanline
  //  |      |      |      |      |
  // -------------------------------
  //  |      |      |      |      |
  //
  // Each character-cell represents a pixel on the output
  // surface, "@" represents the current pixel (always somewhere
  // in the bottom half of the current scan-line, or the top-half
  // of the next scanline). The grid of lines represents the
  // edges of the texels of the underlying texture.
 
  // Texture coordinates of the texel containing the active pixel.
#ifdef CURVATURE
  vec2 xy = transform(texCoord);
#else
  vec2 xy = texCoord;
#endif
  float cval = corner(xy);
 
  // Of all the pixels that are mapped onto the texel we are
  // currently rendering, which pixel are we currently rendering?
  vec2 ratio_scale = xy * storage_size - vec2(0.5);
#ifdef OVERSAMPLE
  float filter = fwidth(ratio_scale.y);
#endif
  vec2 uv_ratio = fract(ratio_scale);
 
  // Snap to the center of the underlying texel.
  xy = (floor(ratio_scale) + vec2(0.5)) / storage_size;
 
  // Calculate Lanczos scaling coefficients describing the effect
  // of various neighbour texels in a scanline on the current
  // pixel.
  vec4 coeffs = PI * vec4(1.0 + uv_ratio.x, uv_ratio.x, 1.0 - uv_ratio.x, 2.0 - uv_ratio.x);
 
  // Prevent division by zero.
  coeffs = FIX(coeffs);
 
  // Lanczos2 kernel.
  coeffs = 2.0 * sin(coeffs) * sin(coeffs / 2.0) / (coeffs * coeffs);
 
  // Normalize.
  coeffs /= dot(coeffs, vec4(1.0));
 
  // Calculate the effective colour of the current and next
  // scanlines at the horizontal location of the current pixel,
  // using the Lanczos coefficients above.
  vec4 col  = clamp(mat4(
                         TEX2D(xy + vec2(-one.x, 0.0)),
                         TEX2D(xy),
                         TEX2D(xy + vec2(one.x, 0.0)),
                         TEX2D(xy + vec2(2.0 * one.x, 0.0))) * coeffs,
                    0.0, 1.0);
  vec4 col2 = clamp(mat4(
                         TEX2D(xy + vec2(-one.x, one.y)),
                         TEX2D(xy + vec2(0.0, one.y)),
                         TEX2D(xy + one),
                         TEX2D(xy + vec2(2.0 * one.x, one.y))) * coeffs,
                    0.0, 1.0);
 
#ifndef LINEAR_PROCESSING
  col  = pow(col , vec4(CRTgamma));
  col2 = pow(col2, vec4(CRTgamma));
#endif
 
  // Calculate the influence of the current and next scanlines on
  // the current pixel.
  vec4 weights  = scanlineWeights(uv_ratio.y, col);
  vec4 weights2 = scanlineWeights(1.0 - uv_ratio.y, col2);
#ifdef OVERSAMPLE
  uv_ratio.y =uv_ratio.y+1.0/3.0*filter;
  weights = (weights+scanlineWeights(uv_ratio.y, col))/3.0;
  weights2=(weights2+scanlineWeights(abs(1.0-uv_ratio.y), col2))/3.0;
  uv_ratio.y =uv_ratio.y-2.0/3.0*filter;
  weights=weights+scanlineWeights(abs(uv_ratio.y), col)/3.0;
  weights2=weights2+scanlineWeights(abs(1.0-uv_ratio.y), col2)/3.0;
#endif
  vec3 mul_res  = (col * weights + col2 * weights2).rgb * vec3(cval);
 
  // dot-mask emulation:
  // Output pixels are alternately tinted green and magenta.
  vec3 dotMaskWeights = mix(
          vec3(1.0, 0.7, 1.0),
          vec3(0.7, 1.0, 0.7),
          floor(mod(mod_factor, 2.0))
      );
                                       
  mul_res *= dotMaskWeights;
 
  // Convert the image gamma for display on our output device.
  mul_res = pow(mul_res, vec3(1.0 / monitorgamma));
 
  // Color the texel.
  gl_FragColor = vec4(mul_res, obj_opacity);
}

