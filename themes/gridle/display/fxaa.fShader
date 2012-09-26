#version 120

uniform sampler2D map_diffuse;
uniform vec2 pixel_size;

varying vec2 texco;

#define span_max 8.0
#define reduce_mul (1.0 / 8.0)
#define reduce_min (1.0 / 128.0)

void main() {
  vec2 dir;

  vec3 c_ul = texture2D(map_diffuse, texco.xy + (vec2(-1.0, -1.0) * pixel_size)).xyz;
  vec3 c_ur = texture2D(map_diffuse, texco.xy + (vec2(+1.0, -1.0) * pixel_size)).xyz;
  vec3 c_ll = texture2D(map_diffuse, texco.xy + (vec2(-1.0, +1.0) * pixel_size)).xyz;
  vec3 c_le = texture2D(map_diffuse, texco.xy + (vec2(+1.0, +1.0) * pixel_size)).xyz;
  vec3 c_mp = texture2D(map_diffuse, texco.xy).xyz;

  vec3 luma = vec3(0.299, 0.587, 0.114);
  float l_ul = dot(c_ul, luma);
  float l_ur = dot(c_ur, luma);
  float l_ll = dot(c_ll, luma);
  float l_lr = dot(c_le, luma);
  float l_mp = dot( c_mp, luma);

  float l_min = min(l_mp, min(min(l_ul, l_ur), min(l_ll, l_lr)));
  float l_max = max(l_mp, max(max(l_ul, l_ur), max(l_ll, l_lr)));

  dir.x = -((l_ul + l_ur) - (l_ll + l_lr));
  dir.y =  ((l_ul + l_ll) - (l_ur + l_lr));

  float dirred = max((l_ul + l_ur + l_ll + l_lr) * (0.25 * reduce_mul), reduce_min);
  float dirmin = 1.0/(min(abs(dir.x), abs(dir.y)) + dirred);

  dir = min(
	vec2(span_max,  span_max), max(vec2(-span_max, -span_max), dir * dirmin)
    ) * pixel_size;

  vec3 rgb_1= (1.0/2.0) * (
              texture2D(map_diffuse, texco.xy + dir * (1.0/3.0 - 0.5)).xyz +
              texture2D(map_diffuse, texco.xy + dir * (2.0/3.0 - 0.5)).xyz
    );

  vec3 rgb_2= rgb_1 * (1.0/2.0) + (1.0/4.0) * (
              texture2D(map_diffuse, texco.xy + dir * (0.0/3.0 - 0.5)).xyz +
              texture2D(map_diffuse, texco.xy + dir * (3.0/3.0 - 0.5)).xyz
    );

  float luma_dp = dot(rgb_2, luma);
  gl_FragColor.rgb = ( luma_dp < l_min || luma_dp > l_max) ? rgb_1 : rgb_2;
  gl_FragColor.a = 1.0;
}
