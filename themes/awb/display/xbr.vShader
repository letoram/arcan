/* Hyllian's xBR upscaler
 * (c) 2011-2012 Hyllian/Jararaca - segiogdb@gmail.com
 * License: GPLv2
 */

#version 120

attribute vec2 texcoord;
attribute vec4 vertex;

uniform mat4 modelview;
uniform mat4 projection;

uniform vec2 storage_size;

varying vec2 tc;

varying vec4 t1;
varying vec4 t2;
varying vec4 t3;
varying vec4 t4;
varying vec4 t5;
varying vec4 t6;
varying vec4 t7;

void main() {
    gl_Position = (projection * modelview) * vertex;

    vec2 one = 1.0 / storage_size;

    float x = one.x;
    float y = one.y;

    tc = texcoord;

    vec4 xxxy = texcoord.xxxy;
    t1 = xxxy + vec4(-x, 0, x, -2.0 * y);
    t2 = xxxy + vec4(-x, 0, x,        y);
    t3 = xxxy + vec4(-x, 0, x,        0);
    t4 = xxxy + vec4(-x, 0, x,        y);
    t5 = xxxy + vec4(-x, 0, x,  2.0 * y);
    t6 = xxxy + vec4(-2.0 * x, -y, 0, y);
    t7 = xxxy + vec4( 2.0 * x, -y, 0, y);
}
