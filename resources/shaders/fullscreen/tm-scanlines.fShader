/* Scanline shader
    Author: Themaister
    This code is hereby placed in the public domain.
*/

uniform sampler2D rubyTexture;
uniform vec2 rubyTextureSize;
uniform vec2 rubyInputSize;
uniform vec2 rubyOutputSize;

varying vec2 omega;
varying vec2 texco;
     
const float base_brightness = 0.95;
const vec2 sine_comp = vec2(0.05, 0.15);

void main ()
{
	vec4 c11 = texture2D(rubyTexture, texco);

	vec4 scanline = c11 * (base_brightness + dot(sine_comp * sin(gl_TexCoord[0].xy * omega), vec2(1.0)));
	gl_FragColor = clamp(scanline, 0.0, 1.0);
}
