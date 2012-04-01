uniform mat4 modelview;
uniform mat4 projection;

uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;
uniform vec2 rubyTextureSize;

	// Define some calculations that will be used in fragment shader.
varying vec2 texCoord;
varying vec2 one;
varying float mod_factor;

attribute vec4 vertex;
attribute vec2 texcoord;

void
main ()
{
  // Do the standard vertex processing.
  gl_Position = (projection * modelview) * vertex;

  // Precalculate a bunch of useful values we'll need in the fragment
  // shader.

  // Texture coords.
  texCoord = texcoord;

  // The size of one texel, in texture-coordinates.
  one = 1.0 / rubyTextureSize;

  // Resulting X pixel-coordinate of the pixel we're drawing.
  mod_factor =
    texCoord.x * rubyTextureSize.x * rubyOutputSize.x / rubyInputSize.x;
}
