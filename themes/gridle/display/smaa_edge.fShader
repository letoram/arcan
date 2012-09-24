uniform sampler2D map_diffuse;

varying vec2 texco;
varying vec4 offset[3];

void main()
{
    vec4 delta;
    vec2 threshold = vec2(0.1, 0.1);
    vec3 weights   = vec3(0.2126, 0.7152, 0.0722);

    float L     = dot(texture2D(map_diffuse, texco).rgb,    weights);
    float Lleft = dot(texture2D(map_diffuse, offset[0].xy).rgb, weights);
    float Ltop  = dot(texture2D(map_diffuse, offset[0].zw).rgb, weights);

    delta.xy   = abs(L - vec2(Lleft, Ltop));
    vec2 edges = step(threshold, delta.xy);

    if (dot(edges, vec2(1.0, 1.0)) == 0.0)
        discard;

    float Lright = dot(texture2D(map_diffuse, offset[1].xy).rgb, weights);
    float Lbottom = dot(texture2D(map_diffuse, offset[1].zw).rgb, weights);
    delta.zw = abs(L - vec2(Lright, Lbottom));

    vec2 maxDelta = max(delta.xy, delta.zw);
    maxDelta = max(maxDelta.xx, maxDelta.yy);

    float Lleftleft = dot(texture2D(map_diffuse, offset[2].xy).rgb, weights);
    float Ltoptop = dot(texture2D(map_diffuse, offset[2].zw).rgb, weights);
    delta.zw = abs(vec2(Lleft, Ltop) - vec2(Lleftleft, Ltoptop));

    maxDelta = max(maxDelta.xy, delta.zw);
    edges.xy *= step(0.5 * maxDelta, delta.xy);

/* the blend shader will only ever use .r, .g so set .a to 1 for debugging */
    gl_FragColor = vec4(edges, 0.0, 1.0);
}
