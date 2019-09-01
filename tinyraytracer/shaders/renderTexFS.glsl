#version 430

out vec4 FragColor;

uniform sampler2D tex;

void main() {
    vec2 texCoord = gl_FragCoord.xy / vec2(1024, 768);

    FragColor = texture(tex, texCoord);
}