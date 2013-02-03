/* Hyllian's xBR upscaler
 * (c) 2011-2012 Hyllian/Jararaca - segiogdb@gmail.com
 * License: GPLv2
 */

#version 120

attribute vec2 texcoord;
attribute vec4 vertex;

uniform mat4 modelview;
uniform mat4 projection;
uniform vec2 texture_size;

varying vec2 texco;
varying vec2 loc;

varying vec4 t1;
varying vec4 t2;
varying vec4 t3;
varying vec4 t4;
varying vec4 t5;
varying vec4 t6;
varying vec4 t7;

void main() {
    texco = texcoord;
    gl_Position = (projection * modelview) * vertex;

    vec2 tx = 1.0 / texture_size;
    float dx = tx.x;
    float dy = tx.y;

    vec4 xxxy = texcoord.xxxy;
    t1 = xxxy + vec4(-dx, 0, dx, -2.0 * dy);
    t2 = xxxy + vec4(-dx, 0, dx,        dy);
    t3 = xxxy + vec4(-dx, 0, dx,         0);
    t4 = xxxy + vec4(-dx, 0, dx,        dy);
    t5 = xxxy + vec4(-dx, 0, dx,  2.0 * dy);
    t6 = xxxy + vec4(-2.0 * dx, -dy, 0, dy);
    t7 = xxxy + vec4( 2.0 * dx, -dy, 0, dy);

    loc = texco * texture_size;
}
