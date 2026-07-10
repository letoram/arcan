// slug_sdf_grade.cl — OpenCL port of slug_sdf_grade.comp.
// SDF atlas grading + ADMM LASSO optimizer for the Slug AA parameters
// (ramp, alpha, beta). Two-phase: accumulate Jacobian-FD columns (mode
// 0/1/2), then solve via ADMM (mode 3).

#define ADMM_H       0.01f
#define ADMM_LAMBDA  0.01f
#define ADMM_RHO     1.0f
#define ADMM_EPS     1e-4f
#define WG_SIZE      256

typedef struct {
    float match_pct;
    float mse;
    float ramp;
    uint  status;
} GlyphQuality;

typedef struct {
    uint codepoint;
    uint sdf_x, sdf_y, cell_w, cell_h;
    uint sample_count;
    uint _pad0, _pad1;
} GlyphRegion;

// 96 bytes per glyph
typedef struct {
    float theta0, theta1, theta2;
    float z0, z1, z2;
    float u0, u1, u2;
    float mu;
    float JtJ_00, JtJ_01, JtJ_02, JtJ_11, JtJ_12, JtJ_22;
    float Jtr_0, Jtr_1, Jtr_2;
    uint  accum_n;
    uint  converged;
    float _pad0, _pad1;
} AdmmState;

__attribute__((reqd_work_group_size(WG_SIZE, 1, 1)))
__kernel void slug_sdf_grade_compute(
    __global const float *sdf_atlas,
    const int   atlas_stride,
    __global const float *stb_ref,
    __global const float *cov_plus,
    __global const float *cov_minus,
    __global GlyphQuality *qualities,
    __global const GlyphRegion *regions,
    const uint  num_glyphs,
    const uint  tolerance,
    const uint  mode,            // 0,1,2 = accumulate column; 3 = solve
    __global AdmmState *admm)
{
    const uint gi  = get_group_id(0);
    if (gi >= num_glyphs) return;
    const uint lid = get_local_id(0);

    const float THETA0[3]    = {0.5f, 0.0f, 0.0f};
    const float THETA_MIN[3] = {0.1f, 0.0f, 0.0f};
    const float THETA_MAX[3] = {2.0f, 1.0f, 0.0f};

    // ── MODE 3: SOLVE (pure ADMM, one thread per glyph) ──
    if (mode == 3u) {
        if (lid != 0u) return;
        if (admm[gi].converged == 1u) return;
        if (admm[gi].accum_n == 0u) return;

        float fn = (float)admm[gi].accum_n;
        float A00 = admm[gi].JtJ_00 / fn;
        float A11 = admm[gi].JtJ_11 / fn;
        float A22 = admm[gi].JtJ_22 / fn;
        float b0_base = admm[gi].Jtr_0 / fn;
        float b1_base = admm[gi].Jtr_1 / fn;
        float b2_base = admm[gi].Jtr_2 / fn;

        float th[3] = {admm[gi].theta0, admm[gi].theta1, admm[gi].theta2};
        float zz[3] = {admm[gi].z0,     admm[gi].z1,     admm[gi].z2};
        float uu[3] = {admm[gi].u0,     admm[gi].u1,     admm[gi].u2};
        const float rho = ADMM_RHO;
        const float B0 = 1.0f / (A00 + rho);
        const float B1 = 1.0f / (A11 + rho);
        const float B2 = 1.0f / (A22 + rho);
        float prev_th[3] = {th[0], th[1], th[2]};

        for (int k = 0; k < 200; ++k) {
            th[0] = B0 * (b0_base + rho * (zz[0] + THETA0[0] - uu[0]));
            th[1] = B1 * (b1_base + rho * (zz[1] + THETA0[1] - uu[1]));
            th[2] = B2 * (b2_base + rho * (zz[2] + THETA0[2] - uu[2]));
            for (int j = 0; j < 3; ++j)
                th[j] = clamp(th[j], THETA_MIN[j], THETA_MAX[j]);
            const float kappa = ADMM_LAMBDA / rho;
            for (int j = 0; j < 3; ++j) {
                float v = th[j] - THETA0[j] + uu[j];
                zz[j] = sign(v) * fmax(fabs(v) - kappa, 0.0f);
            }
            for (int j = 0; j < 3; ++j)
                uu[j] = uu[j] + th[j] - THETA0[j] - zz[j];
            float r_pri = 0.0f;
            for (int j = 0; j < 3; ++j)
                r_pri += fabs(th[j] - THETA0[j] - zz[j]);
            if (r_pri < ADMM_EPS) break;
        }
        float delta = fabs(th[0] - prev_th[0]) + fabs(th[1] - prev_th[1]) + fabs(th[2] - prev_th[2]);
        uint conv = (delta < ADMM_EPS) ? 1u : 0u;
        admm[gi].theta0 = th[0]; admm[gi].theta1 = th[1]; admm[gi].theta2 = th[2];
        admm[gi].z0 = zz[0]; admm[gi].z1 = zz[1]; admm[gi].z2 = zz[2];
        admm[gi].u0 = uu[0]; admm[gi].u1 = uu[1]; admm[gi].u2 = uu[2];
        admm[gi].converged = conv;
        qualities[gi].ramp   = th[0];
        qualities[gi].status = (conv == 1u) ? 3u : 0u;
        return;
    }

    // ── MODE 0/1/2: ACCUMULATE Jacobian column ──
    GlyphRegion region = regions[gi];
    uint n_pixels = region.cell_w * region.cell_h;
    if (n_pixels == 0) return;

    __local uint  shared_match;
    __local float s_mse[WG_SIZE];
    __local float s_Jcol[WG_SIZE];
    __local float s_Jr[WG_SIZE];

    if (lid == 0u) shared_match = 0;
    barrier(CLK_LOCAL_MEM_FENCE);

    uint  local_match = 0;
    float local_mse   = 0.0f;
    float local_Jcol  = 0.0f;
    float local_Jr    = 0.0f;

    for (uint p = lid; p < n_pixels; p += WG_SIZE) {
        uint px = p % region.cell_w;
        uint py = p / region.cell_w;
        uint ax = region.sdf_x + px;
        uint ay = region.sdf_y + py;
        const int idx = ay * atlas_stride + ax;

        float sdf_cov   = sdf_atlas[idx];
        float stb_cov   = stb_ref[idx];
        float plus_cov  = cov_plus[idx];
        float minus_cov = cov_minus[idx];

        int sdf_val = (int)clamp(sdf_cov * 255.0f, 0.0f, 255.0f);
        int stb_val = (int)clamp(stb_cov * 255.0f, 0.0f, 255.0f);
        if (abs(sdf_val - stb_val) <= (int)tolerance) local_match++;

        float fdiff = sdf_cov - stb_cov;
        local_mse += fdiff * fdiff;

        float weight, residual;
        if (stb_cov > 0.5f) { residual = stb_cov - sdf_cov;  weight = 1.5f; }
        else if (stb_cov < 0.1f) { residual = -sdf_cov;       weight = 1.0f; }
        else                  { residual = stb_cov - sdf_cov;  weight = 0.1f; }

        float J_p = (plus_cov - minus_cov) / (2.0f * ADMM_H);
        local_Jcol += (J_p * weight) * (J_p * weight);
        local_Jr   += (J_p * weight) * (residual * weight);
    }

    atomic_add(&shared_match, local_match);
    s_mse[lid]  = local_mse;
    s_Jcol[lid] = local_Jcol;
    s_Jr[lid]   = local_Jr;
    barrier(CLK_LOCAL_MEM_FENCE);

    for (uint stride = WG_SIZE / 2; stride > 0; stride >>= 1) {
        if (lid < stride) {
            s_mse[lid]  += s_mse[lid + stride];
            s_Jcol[lid] += s_Jcol[lid + stride];
            s_Jr[lid]   += s_Jr[lid + stride];
        }
        barrier(CLK_LOCAL_MEM_FENCE);
    }

    if (lid == 0u) {
        float fn = (float)n_pixels;
        qualities[gi].match_pct = 100.0f * (float)shared_match / fn;
        qualities[gi].mse  = s_mse[0] / fn;
        qualities[gi].ramp = admm[gi].theta0;
        uint status = 0u;
        if (admm[gi].converged == 1u)            status = 3u;
        else if (region.sample_count >= 16u)     status = (qualities[gi].match_pct >= 80.0f) ? 1u : 2u;
        qualities[gi].status = status;

        float Jcol_norm = s_Jcol[0] / fn;
        float Jr_norm   = s_Jr[0]   / fn;
        if (mode == 0u) { admm[gi].JtJ_00 += Jcol_norm; admm[gi].Jtr_0 += Jr_norm; }
        if (mode == 1u) { admm[gi].JtJ_11 += Jcol_norm; admm[gi].Jtr_1 += Jr_norm; }
        if (mode == 2u) { admm[gi].JtJ_22 += Jcol_norm; admm[gi].Jtr_2 += Jr_norm; }
        admm[gi].accum_n += 1u;
    }
}
