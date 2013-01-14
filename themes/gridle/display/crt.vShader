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

uniform mat4 modelview;
uniform mat4 projection;

/* these could be packed into one mat4 should the overhead of many uniform locations be too many */
uniform vec2 input_size;
uniform vec2 storage_size;
uniform vec2 output_size;
uniform float CRTgamma;
uniform float monitorgamma;
uniform float distance;
uniform float curv_radius;
uniform float cornersize;
uniform float cornersmooth;
uniform vec2 tilt_angle;
uniform vec2 aspect;
uniform vec2 overscan;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texCoord;
varying vec2 one;
varying float mod_factor;
varying vec3 stretch;
varying vec2 sinangle;
varying vec2 cosangle;
 
#define FIX(c) max(abs(c), 1e-5);
 
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
  float r = curv_radius*acos(a);
  return uv*r/sin(r/curv_radius);
}
 
vec2 fwtrans(vec2 uv)
{
  float r = FIX(sqrt(dot(uv,uv)));
  uv *= sin(r/curv_radius)/r;
  float x = 1.0-cos(r/curv_radius);
  float D = distance/curv_radius + x*cosangle.x*cosangle.y+dot(uv,sinangle);
  return distance*(uv*cosangle-x*sinangle)/D;
}
 
vec3 maxscale()
{
  vec2 c = bkwtrans(-curv_radius * sinangle / (1.0 + curv_radius/distance*cosangle.x*cosangle.y));
  vec2 a = vec2(0.5,0.5)*aspect;
  vec2 lo = vec2(fwtrans(vec2(-a.x,c.y)).x,
                 fwtrans(vec2(c.x,-a.y)).y)/aspect;
  vec2 hi = vec2(fwtrans(vec2(+a.x,c.y)).x,
                 fwtrans(vec2(c.x,+a.y)).y)/aspect;
  return vec3((hi+lo)*aspect*0.5,max(hi.x-lo.x,hi.y-lo.y));
}
 
void main()
{
  gl_Position = (projection * modelview) * vertex;

  sinangle = sin(tilt_angle);
  cosangle = cos(tilt_angle);
  stretch = maxscale();
 
  one = 1.0 / storage_size;
  mod_factor = texcoord.x * storage_size.x * output_size.x / input_size.x;

  texCoord = texcoord; 
}
