uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
  vec4 col = texture2D(map_diffuse, texco);
  col.a = col.a * obj_opacity;
  gl_FragColor = col;
}
