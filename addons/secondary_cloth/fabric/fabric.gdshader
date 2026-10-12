shader_type spatial;
// Fabric surface: weave micro-normal, soft fibre sheen (no sparkle), darker inner side,
// optional light transmission for thin textiles.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, hint_default_white;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.3;

// Weave / grain detail. UV units of the outfits are metres (box projection) or the
// texture atlas: weave_scale is the number of repetitions per UV unit.
uniform sampler2D weave_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float weave_scale = 60.0;
uniform float weave_strength : hint_range(0.0, 2.0) = 0.3;
// The weave fades out with distance so it never aliases into glitter.
uniform float weave_fade_distance = 6.0;

// Fibre sheen: a broad, low rim at grazing angles tinted by the cloth colour.
uniform float sheen : hint_range(0.0, 1.0) = 0.2;
uniform float sheen_tint : hint_range(0.0, 1.0) = 0.75;

// Inside of the garment (lining, back faces) is darker: gives the fabric thickness.
uniform float inner_darkening : hint_range(0.0, 1.0) = 0.35;
// Thin fabrics let light through (BACKLIGHT).
uniform float translucency : hint_range(0.0, 1.0) = 0.0;
// Soft occlusion in the folds, from screen-space curvature of the shading normal.
uniform float fold_shadow : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 col = albedo.rgb * tex.rgb;
	if (!FRONT_FACING) {
		col *= 1.0 - inner_darkening;
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = specular;

	float dist = length(VERTEX);
	float detail = weave_strength * clamp(1.0 - dist / weave_fade_distance, 0.0, 1.0);
	NORMAL_MAP = texture(weave_normal, UV * weave_scale).xyz;
	NORMAL_MAP_DEPTH = detail;

	RIM = sheen;
	RIM_TINT = sheen_tint;

	// Concave folds: the normal turns fast across the screen there.
	vec3 dn = fwidth(NORMAL);
	float curvature = clamp((dn.x + dn.y + dn.z) * 3.0, 0.0, 1.0);
	AO = 1.0 - curvature * fold_shadow;
	AO_LIGHT_AFFECT = 0.35;

	BACKLIGHT = col * translucency;
}
