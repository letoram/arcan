uniform sampler2D map_diffuse;
varying vec2 texco;

void main(){
  gl_FragColor = texture2D(map_diffuse, texco);
}
