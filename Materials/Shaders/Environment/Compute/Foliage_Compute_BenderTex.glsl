#[compute]
#version 450
#extension GL_NV_compute_shader_derivatives : enable

// One invocation per texel
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0,binding = 0, r32f) uniform restrict readonly image2D IN_FOLIAGE_BENDER;

layout(set = 0,binding = 1, r32f) uniform restrict image2D OUT_FOLIAGE_BENDER;

layout(set = 0, binding = 2, std430) restrict readonly buffer FParameters {
    float DECAY_RATE_PER_SECOND;
    float DELTA;

    // The accumulator is no longer a chunk-sized mask in chunk space. It is a
    // fixed window that follows the player, anchored in WORLD texel space and
    // addressed toroidally, so trails stay on the ground they were pressed into
    // while the window scrolls over them.
    int MASK_RES;
    int WINDOW_ORIGIN_X;
    int WINDOW_ORIGIN_Y;
    int PREV_WINDOW_ORIGIN_X;
    int PREV_WINDOW_ORIGIN_Y;
    int SOURCE_FLIP_BITS;
} FPARAMETERS;

void main()
{
    const ivec2 local_texel = ivec2(gl_GlobalInvocationID.xy);
    const int res = FPARAMETERS.MASK_RES;

    if(local_texel.x >= res || local_texel.y >= res)
    {
        return;
    }

    // The bender camera sits under the world looking up, so its render comes out mirrored, reverse that here
    ivec2 source_texel = local_texel;
    if((FPARAMETERS.SOURCE_FLIP_BITS & 1) != 0)
    {
        source_texel.x = res - 1 - source_texel.x;
    }
    if((FPARAMETERS.SOURCE_FLIP_BITS & 2) != 0)
    {
        source_texel.y = res - 1 - source_texel.y;
    }

    const float incoming = imageLoad(IN_FOLIAGE_BENDER, source_texel).x;

    const ivec2 window_origin = ivec2(FPARAMETERS.WINDOW_ORIGIN_X, FPARAMETERS.WINDOW_ORIGIN_Y);
    const ivec2 prev_origin = ivec2(FPARAMETERS.PREV_WINDOW_ORIGIN_X, FPARAMETERS.PREV_WINDOW_ORIGIN_Y);
    const ivec2 world_texel = window_origin + local_texel;

    // res is a power of two, so the toroidal wrap is a bitmask. Do NOT use %
    // here: integer modulo is undefined for negative operands, and world texel
    // indices go negative across half the world.
    const ivec2 accum_texel = ivec2(world_texel.x & (res - 1), world_texel.y & (res - 1));

    // Texels the window has just slid onto still hold the history of whatever
    // world texel previously mapped to that slot. Start those fresh rather than
    // dragging a trail in from the far side of the window.
    const bool is_new = world_texel.x < prev_origin.x
        || world_texel.y < prev_origin.y
        || world_texel.x >= prev_origin.x + res
        || world_texel.y >= prev_origin.y + res;

    const float current_val = is_new ? 0.0 : imageLoad(OUT_FOLIAGE_BENDER, accum_texel).x;

    //fall of towards 0
    const float ReduceAmount = FPARAMETERS.DECAY_RATE_PER_SECOND * FPARAMETERS.DELTA;
    const float reduced = max(current_val - ReduceAmount, 0.0);
    const float newVal = max(incoming, reduced);

    imageStore(OUT_FOLIAGE_BENDER, accum_texel, vec4(newVal));
}
