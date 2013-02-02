/* Hyllian's Data Dependent Triangulation Shader
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
varying vec2 v_xy;
varying vec2 v_zw;

void main() {
    texco = texcoord;
    gl_Position = (projection * modelview) * vertex;

    vec2 tx = 1.0 / texture_size;
    v_xy = vec2(tx.x, 0.0);
    v_zw = vec2(0.0, tx.y);
    loc = texco * texture_size;
}
