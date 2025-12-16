#include "common_ps_fxc.h"

sampler BASETEXTURE	: register(s0); // albedo
sampler TEXTURE1	: register(s1); // Ambient Occlusion
sampler TEXTURE2	: register(s2); // Normal

struct PS_INPUT {
	float2 uv            : TEXCOORD0;	
	//float3 pos           : TEXCOORD1;
	//float3 normal        : TEXCOORD2;
};

// gm_construct ambient color
#define AMBIENT_COLOR float3(0.308251, 0.454464, 0.547380)
#define SUN_DIR normalize(float3(1.0, 1.0, 1.0))

float4 main(PS_INPUT frag) : COLOR {
	float3 world_normal = tex2D(TEXTURE2, frag.uv).xyz * 2.0 - 1.0;
	float3 color = float3(1.0, 1.0, 1.0);

	// simple diffuse material calculation
	//color *= max(dot(world_normal, SUN_DIR), 0.0);	// sun direction
	//color += AMBIENT_COLOR;							// ambient color
	color *= tex2D(BASETEXTURE, frag.uv).xyz;		// albedo
	color *= tex2D(TEXTURE1, frag.uv).xyz;			// ambient occlusion

	return FinalOutput(float4(color, 1.0f), 0, PIXEL_FOG_TYPE_NONE, TONEMAP_SCALE_LINEAR);
}