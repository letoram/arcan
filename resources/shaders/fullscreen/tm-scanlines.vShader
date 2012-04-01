/*  Scanline shader
    Author: Themaister
    This code is hereby placed in the public domain.
*/

uniform vec2 rubyTextureSize;
uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;

uniform mat4 modelview;
uniform mat4 projection;

attribute vec2 texcoord;
attribute vec4 vertex;

varying vec2 omega;
varying vec2 texco;

void main()
{
  gl_Position = (projection * modelview) * vertex;
  texco = texcoord;
  omega = vec2(3.1415 * rubyOutputSize.x * rubyTextureSize.x / rubyInputSize.x, 2.0 * 3.1415 * rubyTextureSize.y);
}
