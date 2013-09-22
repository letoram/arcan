/* SABR v1.1 Shader
Joshua Street

Portions of this algorithm were taken from Hyllian's 5xBR v3.7c
shader.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

#version 120

attribute vec2 texcoord;
attribute vec4 vertex;

uniform mat4 modelview;
uniform mat4 projection;

uniform vec2 storage_size;

varying vec2 tc;
varying vec4 xyp_1_2_3;
varying vec4 xyp_5_10_15;
varying vec4 xyp_6_7_8;
varying vec4 xyp_9_14_9;
varying vec4 xyp_11_12_13;
varying vec4 xyp_16_17_18;
varying vec4 xyp_21_22_23;

void main() {
    gl_Position = (projection * modelview) * vertex;

    vec2 one = 1.0 / storage_size;

    float x = one.x;
    float y = one.y;
 
    tc = vec2(texcoord.s, texcoord.t);

    xyp_1_2_3    = tc.xxxy + vec4(      -x, 0.0,   x, -2.0 * y);
    xyp_6_7_8    = tc.xxxy + vec4(      -x, 0.0,   x,       -y);
    xyp_11_12_13 = tc.xxxy + vec4(      -x, 0.0,   x,      0.0);
    xyp_16_17_18 = tc.xxxy + vec4(      -x, 0.0,   x,        y);
    xyp_21_22_23 = tc.xxxy + vec4(      -x, 0.0,   x,  2.0 * y);
    xyp_5_10_15  = tc.xyyy + vec4(-2.0 * x,  -y, 0.0,        y);
    xyp_9_14_9   = tc.xyyy + vec4( 2.0 * x,  -y, 0.0,        y);
}
